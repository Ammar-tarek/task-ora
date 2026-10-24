-- ============================================================================
-- PROPOSED (NOT APPLIED) — Assignment accept/reject + employee field lockdown.
-- Needs explicit approval before running in production.
--
-- WHY:
--  (1) Employees must accept/reject a task assignment. `task_assignees` has no
--      response field and employees have no UPDATE on it (SELECT-own only). Add
--      response columns + a SECURITY DEFINER RPC the employee calls.
--  (2) Employees must NOT edit management fields (priority, cost, payment_status,
--      progress, team, client, title, description…). Today RLS `tasks_employee_update`
--      lets an assignee update ANY column; only `status` is guarded. Add a field
--      guard so employees may change ONLY due_date (+ status, already guarded).
--
-- DECISIONS (documented, ticket-aligned):
--  * Assignment rejection NEVER changes tasks.status (completion/review stay
--    intact). On reject the RPC: (1) writes an append-only task_audit_log row
--    (durable history), (2) DELETES only the rejecting employee's task_assignees
--    row so they leave the active assignment and the task becomes reassignable,
--    (3) notifies the team's managers + admins. Other assignees are untouched.
--    Rejection history lives in task_audit_log, so it survives the row delete
--    and any later reassignment. Accept just sets response = 'accepted'.
--  * A reason is REQUIRED when rejecting an assignment.
--  * Existing task_assignees rows keep response = NULL (legacy = treated as
--    accepted by the app). New assignments default to 'pending' (DB default).
--  * Duplicate-safe: a retried reject finds no assignee row and raises
--    'not assigned' — no second history row or notification. A reassigned
--    employee has a fresh row; the removed one cannot reject the old assignment.
--
-- ROLLBACK: ROLLBACK_task_assignment_response.sql
-- ============================================================================

-- ── 1. Assignment response columns (additive; existing rows stay NULL) ──────
ALTER TABLE public.task_assignees
  ADD COLUMN IF NOT EXISTS response text
      CHECK (response IS NULL OR response IN ('pending','accepted','rejected')),
  ADD COLUMN IF NOT EXISTS responded_at   timestamptz,
  ADD COLUMN IF NOT EXISTS response_reason text;

-- Backfill-safe: ADD COLUMN above leaves existing 202 rows NULL (= legacy,
-- implicitly accepted). Setting the DEFAULT only AFTER adding the column makes
-- NEW inserts auto-'pending' WITHOUT touching existing rows and WITHOUT the app
-- needing to send the field (backward-compatible with un-updated clients).
ALTER TABLE public.task_assignees ALTER COLUMN response SET DEFAULT 'pending';

COMMENT ON COLUMN public.task_assignees.response IS
  'Employee assignment response: pending | accepted | rejected. NULL = legacy (implicitly accepted). Distinct from task review status.';

-- ── 2. RPC: employee accepts / rejects their own assignment ─────────────────
CREATE OR REPLACE FUNCTION public.respond_to_assignment(
  p_task_id  uuid,
  p_decision text,            -- 'accepted' | 'rejected'
  p_reason   text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor   uuid := auth.uid();
  v_current text;
  v_title   text;
  v_team    uuid;
  v_name    text;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'Invalid decision "%".', p_decision USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision = 'rejected' AND COALESCE(btrim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'A reason is required to reject an assignment.' USING ERRCODE = 'check_violation';
  END IF;

  -- Caller must own this assignment row. Lock it to serialize double-clicks.
  SELECT response INTO v_current
  FROM public.task_assignees
  WHERE task_id = p_task_id AND profile_id = v_actor
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not assigned to this task.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Only an undecided assignment (NULL/pending) may be answered → no conflicting
  -- or duplicate decisions.
  IF v_current IS NOT NULL AND v_current <> 'pending' THEN
    RAISE EXCEPTION 'Assignment already answered (%).', v_current USING ERRCODE = 'check_violation';
  END IF;

  SELECT title, team_id INTO v_title, v_team FROM public.tasks WHERE id = p_task_id;
  SELECT full_name INTO v_name FROM public.profiles WHERE id = v_actor;

  IF p_decision = 'accepted' THEN
    UPDATE public.task_assignees
       SET response = 'accepted', responded_at = now(), response_reason = NULL
     WHERE task_id = p_task_id AND profile_id = v_actor;
    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'assignment_accepted', 'Assignment accepted');
  ELSE
    -- Durable history FIRST (task_audit_log is append-only: no UPDATE/DELETE
    -- policy), so the rejection survives removing the active assignee row.
    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'assignment_rejected', btrim(p_reason));
    -- Remove ONLY this employee from the active assignment (others untouched).
    -- The task keeps its status/review history and becomes reassignable.
    DELETE FROM public.task_assignees
     WHERE task_id = p_task_id AND profile_id = v_actor;
  END IF;

  -- Notify the task's team managers + admins. A notification failure must NOT
  -- roll back the recorded response above, so it is guarded. Duplicates are
  -- prevented upstream: a retried reject finds no assignee row → 'not assigned'.
  BEGIN
    PERFORM public.notify_fanout(
      v_team,
      CASE WHEN p_decision='accepted' THEN 'task_assigned' ELSE 'task_rejected' END,
      CASE WHEN p_decision='accepted' THEN 'Assignment accepted' ELSE 'Task Assignment Rejected' END,
      CASE WHEN p_decision='accepted'
        THEN '"'||COALESCE(v_title,'Task')||'" was accepted by '||COALESCE(v_name,'an employee')||'.'
        ELSE '"'||COALESCE(v_title,'Task')||'" was rejected by '||COALESCE(v_name,'an employee')||
             ' on '||to_char(now() AT TIME ZONE 'Africa/Cairo','YYYY-MM-DD HH24:MI')||
             ' — '||btrim(p_reason) END,
      'task', p_task_id, NULL, v_actor);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'respond_to_assignment: notification failed for task %: %', p_task_id, SQLERRM;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.respond_to_assignment(uuid,text,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_assignment(uuid,text,text) TO authenticated;

-- ── 3. Field guard: employees may change ONLY due_date (and status) ─────────
-- Runs for every UPDATE; only restricts employees. Admin/manager/service pass.
-- status is left to the existing trg_guard_task_status_transition.
CREATE OR REPLACE FUNCTION public.guard_task_employee_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.is_global_admin() OR auth.role() = 'service_role'
     OR public.get_my_role() <> 'employee' THEN
    RETURN NEW;
  END IF;

  -- Employee path: reject any change to a management-controlled column.
  IF NEW.priority              IS DISTINCT FROM OLD.priority
     OR NEW.cost               IS DISTINCT FROM OLD.cost
     OR NEW.payment_status     IS DISTINCT FROM OLD.payment_status
     OR NEW.completion_percentage IS DISTINCT FROM OLD.completion_percentage
     OR NEW.team_id            IS DISTINCT FROM OLD.team_id
     OR NEW.client_id          IS DISTINCT FROM OLD.client_id
     OR NEW.hidden_from_client IS DISTINCT FROM OLD.hidden_from_client
     OR NEW.title              IS DISTINCT FROM OLD.title
     OR NEW.description        IS DISTINCT FROM OLD.description
     OR NEW.board_id           IS DISTINCT FROM OLD.board_id
     OR NEW.board_column_id    IS DISTINCT FROM OLD.board_column_id
     OR NEW.parent_task_id     IS DISTINCT FROM OLD.parent_task_id
     OR NEW.is_template        IS DISTINCT FROM OLD.is_template
  THEN
    RAISE EXCEPTION 'Employees may edit only the task deadline.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_task_employee_fields ON public.tasks;
CREATE TRIGGER trg_guard_task_employee_fields
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_task_employee_fields();

-- ── VALIDATION (after apply) ────────────────────────────────────────────────
-- employee session:
--   SELECT respond_to_assignment('<my task>','accepted');          -- ok
--   SELECT respond_to_assignment('<my task>','rejected','busy');   -- ok (reason)
--   SELECT respond_to_assignment('<not my task>','accepted');      -- ERROR not assigned
--   UPDATE tasks SET due_date = now() WHERE id='<my task>';         -- ok
--   UPDATE tasks SET cost = 1 WHERE id='<my task>';                 -- ERROR employees may edit only the deadline
-- existing rows keep response = NULL (no forced re-acceptance).
