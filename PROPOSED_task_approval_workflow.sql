-- ============================================================================
-- PROPOSED (NOT APPLIED) — Manager/Admin Task Approval Workflow + status guard.
-- Needs explicit approval before running in production.
--
-- DECISION (locked with product): internal review only — NO client gate.
--   in_progress ─(employee submits)→ employee_done  [Pending Review]
--   employee_done ─(manager/admin approve)→ completed
--   employee_done ─(manager/admin reject)→ changes_requested  (reason, back to employee)
--   changes_requested ─(employee)→ in_progress / employee_done  (resubmit)
--
-- WHY THIS MIGRATION:
--   1. SECURITY HOLE: RLS `tasks_employee_update` lets ANY assignee update the
--      task row with no column/value guard, so an employee can set status
--      straight to 'completed' or 'client_approved' and self-approve. There is
--      NO status-transition guard trigger today (only a payment guard).
--   2. task_approvals (built for this) is NEVER written by the app: 173 tasks
--      sit 'employee_done' with 0 approval rows — no reviewer / time / reason.
--
-- WHAT IT DOES (all additive / safe):
--   A. adds enum value 'changes_requested' to task_status (additive).
--   B. adds review columns to task_approvals (reviewer / decision / reason).
--   C. guard trigger: role-based allowed status transitions (closes the hole).
--   D. SECURITY DEFINER RPCs submit_task_for_review() + review_task() that
--      write status + task_approvals + audit atomically.
--   E. extends notify_task_status so approve/reject notify assignees (single
--      source of truth — the app must STOP sending its own duplicate note).
--
-- HISTORICAL DATA: existing 'employee_done' rows are LEFT AS-IS (still pending
-- review). Nothing is bulk-converted. No existing 'completed' task changes.
--
-- AFTER APPLY — app changes (see task_repository.dart):
--   * employee submit  → _client.rpc('submit_task_for_review', {p_task_id})
--   * manager/admin    → _client.rpc('review_task', {p_task_id,p_decision,p_reason})
--   * DROP the client-side notifyAction('task_status_changed') on these paths
--     (the trigger now notifies) to kill the double-notification.
-- ROLLBACK: see ROLLBACK_task_approval_workflow.sql.
-- ============================================================================

-- ── A. enum value (additive; enum values cannot be dropped — see rollback) ──
-- APPLY ORDER: `ALTER TYPE ... ADD VALUE` CANNOT run inside a transaction and
-- the new label cannot be referenced in the SAME transaction it is added in.
-- So apply this ONE statement on its own first (autocommit), THEN run the rest
-- of this file (sections B–F) as a second step. The MCP apply path does exactly
-- this: execute_sql for the line below, then apply_migration for B–F.
ALTER TYPE public.task_status ADD VALUE IF NOT EXISTS 'changes_requested';

-- ── B. review metadata on task_approvals ────────────────────────────────────
ALTER TABLE public.task_approvals
  ADD COLUMN IF NOT EXISTS reviewer_id      uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS reviewed_at      timestamptz,
  ADD COLUMN IF NOT EXISTS review_decision  text
      CHECK (review_decision IS NULL OR review_decision IN ('approved','changes_requested')),
  ADD COLUMN IF NOT EXISTS review_reason    text;

COMMENT ON COLUMN public.task_approvals.reviewer_id     IS 'Manager/admin who approved or requested changes.';
COMMENT ON COLUMN public.task_approvals.review_decision IS 'approved | changes_requested (internal review, no client gate).';

-- ── C. status-transition guard (role-based; path-independent) ───────────────
-- Enforced for EVERY update, including via the RPCs below (they run as
-- SECURITY DEFINER but auth.uid()/get_my_role() still resolve to the caller),
-- so the rule is identical whether the write comes from an RPC or a direct
-- PostgREST call with a hand-crafted payload. This is what closes the hole.
CREATE OR REPLACE FUNCTION public.guard_task_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role public.user_role := public.get_my_role();
BEGIN
  -- No status change, or privileged caller → nothing to guard.
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  IF public.is_global_admin() OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Managers may drive review transitions, but only on their own team's tasks.
  IF v_role = 'manager' THEN
    IF COALESCE(NEW.team_id, OLD.team_id) = public.my_team_id() THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Managers can only change status on their own department tasks.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Employees: may move work forward, but NEVER approve/complete/reject.
  IF v_role = 'employee' THEN
    IF NEW.status IN ('not_started','in_progress','employee_done','on_hold') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Employees cannot set status "%". Submit for review instead.', NEW.status
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Clients and any other role: no task status changes.
  RAISE EXCEPTION 'Not allowed to change task status.' USING ERRCODE = 'insufficient_privilege';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_task_status_transition ON public.tasks;
CREATE TRIGGER trg_guard_task_status_transition
  BEFORE UPDATE OF status ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_task_status_transition();

-- ── D. RPCs: atomic status + approval metadata + audit ──────────────────────

-- Employee submits a task for review.
CREATE OR REPLACE FUNCTION public.submit_task_for_review(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_status public.task_status;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT status INTO v_status FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE = 'no_data_found';
  END IF;

  -- Caller must be an assignee or the creator (admins/managers use review_task).
  IF NOT (
    EXISTS (SELECT 1 FROM public.task_assignees WHERE task_id = p_task_id AND profile_id = v_actor)
    OR EXISTS (SELECT 1 FROM public.tasks WHERE id = p_task_id AND created_by = v_actor)
  ) THEN
    RAISE EXCEPTION 'You are not assigned to this task.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_status NOT IN ('not_started','in_progress','changes_requested','on_hold') THEN
    RAISE EXCEPTION 'Task cannot be submitted from status "%".', v_status
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.tasks SET status = 'employee_done' WHERE id = p_task_id;

  INSERT INTO public.task_approvals (task_id, employee_done_at, employee_done_by)
  VALUES (p_task_id, now(), v_actor)
  ON CONFLICT (task_id) DO UPDATE
    SET employee_done_at = now(),
        employee_done_by = v_actor,
        reviewer_id      = NULL,   -- fresh review needed after resubmission
        reviewed_at      = NULL,
        review_decision  = NULL,
        review_reason    = NULL,
        updated_at       = now();

  INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
  VALUES (p_task_id, v_actor, 'submit_for_review', 'Submitted for review');
END;
$$;

-- Manager (own team) or global admin approves / requests changes.
CREATE OR REPLACE FUNCTION public.review_task(
  p_task_id  uuid,
  p_decision text,            -- 'approved' | 'changes_requested'
  p_reason   text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor  uuid := auth.uid();
  v_team   uuid;
  v_status public.task_status;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('approved','changes_requested') THEN
    RAISE EXCEPTION 'Invalid decision "%".', p_decision USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision = 'changes_requested' AND COALESCE(btrim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'A reason is required when requesting changes.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT team_id, status INTO v_team, v_status
  FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE = 'no_data_found';
  END IF;

  -- Authorization: global admin, or the task team's manager.
  IF NOT (
    public.is_global_admin()
    OR (public.get_my_role() = 'manager' AND v_team = public.my_team_id())
  ) THEN
    RAISE EXCEPTION 'Not authorized to review this task.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Concurrency: only a task that is still pending review can be reviewed.
  IF v_status <> 'employee_done' THEN
    RAISE EXCEPTION 'Task is not pending review (current status "%").', v_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_decision = 'approved' THEN
    UPDATE public.tasks
      SET status = 'completed', completion_percentage = 100
      WHERE id = p_task_id;
  ELSE
    UPDATE public.tasks
      SET status = 'changes_requested'
      WHERE id = p_task_id;
  END IF;

  UPDATE public.task_approvals
    SET reviewer_id     = v_actor,
        reviewed_at     = now(),
        review_decision = p_decision,
        review_reason   = p_reason,
        updated_at      = now()
  WHERE task_id = p_task_id;
  IF NOT FOUND THEN
    INSERT INTO public.task_approvals (task_id, reviewer_id, reviewed_at, review_decision, review_reason)
    VALUES (p_task_id, v_actor, now(), p_decision, p_reason);
  END IF;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
  VALUES (p_task_id, v_actor,
          CASE WHEN p_decision = 'approved' THEN 'approved' ELSE 'changes_requested' END,
          COALESCE(p_reason, p_decision));
END;
$$;

REVOKE ALL ON FUNCTION public.submit_task_for_review(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.review_task(uuid, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submit_task_for_review(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_task(uuid, text, text) TO authenticated;

-- ── E. notifications: approve/reject notify assignees (single source) ───────
-- Extends the existing notify_task_status trigger fn. The app must DROP its
-- own notifyAction on the status-change path or notes double up.
CREATE OR REPLACE FUNCTION public.notify_task_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE aid uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='employee_done' THEN
      PERFORM public.notify_fanout(NEW.team_id,'task_done','Task awaiting review',
        '"'||NEW.title||'" was submitted and awaits your review.','task',NEW.id,NULL);
    ELSIF NEW.status='completed' AND OLD.status='employee_done' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_approved','Task approved',
          '"'||NEW.title||'" was approved and completed.','task',NEW.id,aid);
      END LOOP;
    ELSIF NEW.status='changes_requested' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_rejected','Changes requested',
          '"'||NEW.title||'" needs changes before it can be approved.','task',NEW.id,aid);
      END LOOP;
    -- legacy client gate (kept harmless for old data / direct admin edits)
    ELSIF NEW.status='client_approved' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_approved','Task approved',
          '"'||NEW.title||'" was approved.','task',NEW.id,aid);
      END LOOP;
    ELSIF NEW.status='client_rejected' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_rejected','Task needs rework',
          '"'||NEW.title||'" was rejected.','task',NEW.id,aid);
      END LOOP;
    END IF;
  END IF;

  IF NEW.handoff_to_team_id IS NOT NULL
     AND NEW.handoff_to_team_id IS DISTINCT FROM OLD.handoff_to_team_id THEN
    PERFORM public.notify_fanout(NEW.handoff_to_team_id,'system','New task handoff',
      '"'||NEW.title||'" was sent to your department. Check the Waiting List.','task',NEW.id,NULL);
  END IF;
  RETURN NEW;
END;
$$;

-- ── F. Finance CRM: fire on internal approval ('completed'), de-duplicated ──
-- Old behaviour fired on 'client_approved'. The new flow approves to
-- 'completed', so CRM must fire there. Fires on EITHER revenue state but is
-- guarded by NOT EXISTS so a task can only ever create ONE task-sourced entry
-- (covers approve→completed, any legacy client_approved, and retries). Keeps
-- amount/client/currency(default EGP)/status(default unpaid) rules; also stamps
-- team_id for department revenue reporting. Historical completed tasks are NOT
-- touched (trigger only runs on an UPDATE that changes status).
CREATE OR REPLACE FUNCTION public.create_crm_from_task()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('completed','client_approved')
  AND OLD.status IS DISTINCT FROM NEW.status
  AND NEW.client_id IS NOT NULL
  AND NEW.cost IS NOT NULL
  AND NEW.cost > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.crm_entries
    WHERE source_type = 'task' AND source_id = NEW.id
  )
  THEN
    INSERT INTO public.crm_entries (
      client_id, team_id, source_type, source_id,
      title, amount, status, created_by
    ) VALUES (
      NEW.client_id,
      NEW.team_id,
      'task',
      NEW.id,
      'Task Completed: ' || NEW.title,
      NEW.cost,
      'unpaid',
      NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$function$;

-- ── G. notify_fanout: include pure super admins as recipients ───────────────
-- Old admin union used role='admin' only, missing a super_admin whose role is
-- not 'admin'. Add `OR is_super_admin = true`.
CREATE OR REPLACE FUNCTION public.notify_fanout(p_team uuid, p_type notification_type, p_title text, p_body text, p_ref_type text, p_ref_id uuid, p_primary uuid, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.notifications(recipient_id,type,title,body,reference_type,reference_id)
  SELECT DISTINCT r, p_type, p_title, p_body, p_ref_type, p_ref_id
  FROM (
    SELECT p_primary AS r WHERE p_primary IS NOT NULL
    UNION
    SELECT id FROM public.profiles WHERE role='admin' OR is_super_admin = true
    UNION
    SELECT id FROM public.profiles
      WHERE role='manager' AND p_team IS NOT NULL AND team_id=p_team
  ) x
  WHERE r IS NOT NULL AND (p_exclude IS NULL OR r <> p_exclude);
END $function$;

-- ── VALIDATION (run after apply, expect the described result) ───────────────
-- 1. enum has the new label:
--    SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid=t.oid
--     WHERE t.typname='task_status' AND e.enumlabel='changes_requested';  -- 1 row
-- 2. employee self-approve blocked (run as an employee session):
--    UPDATE tasks SET status='completed' WHERE id='<task assigned to that employee>';
--    -- expect: ERROR insufficient_privilege "Employees cannot set status ..."
-- 3. happy path (employee session then manager session):
--    SELECT submit_task_for_review('<task>');      -- status → employee_done
--    SELECT review_task('<task>','approved',NULL);  -- status → completed, approval row written
-- 4. concurrent double review: second review_task on same task → check_violation.
