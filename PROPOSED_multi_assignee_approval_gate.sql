-- ============================================================================
-- EDIT 1 — Hide "Approve" until EVERY assignee has submitted for review.
-- ============================================================================
-- Before: submit_task_for_review flipped the whole task to 'employee_done' the
-- moment ONE assignee submitted, so the Approve button (keyed on status=
-- 'employee_done') showed to the manager/admin even though teammates were not
-- done. We now track submission PER assignee. The task only reaches
-- 'employee_done' (and thus shows Approve + fires the "submitted for review"
-- push) once all active assignees have submitted.
--
-- Apply in the Supabase SQL editor. Idempotent / safe to re-run.
-- ============================================================================

-- 1. Per-assignee submission flag ------------------------------------------------
ALTER TABLE public.task_assignees
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz;

-- Backfill: any task already in review keeps its Approve button — mark its
-- active assignees as submitted so in-flight reviews are not reset.
UPDATE public.task_assignees a
  SET submitted_at = now()
FROM public.tasks t
WHERE a.task_id = t.id
  AND t.status = 'employee_done'
  AND a.submitted_at IS NULL
  AND a.response IS DISTINCT FROM 'rejected';

-- 2. Submit = mark MY part done; flip task only when all assignees are in -------
CREATE OR REPLACE FUNCTION public.submit_task_for_review(p_task_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor     uuid := auth.uid();
  v_status    public.task_status;
  v_total     int;
  v_submitted int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT status INTO v_status FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE = 'no_data_found';
  END IF;

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

  -- Mark THIS assignee's part submitted (a creator who is not an assignee
  -- updates no row, which is fine — the all-submitted check below still flips).
  UPDATE public.task_assignees
    SET submitted_at = now()
    WHERE task_id = p_task_id AND profile_id = v_actor;

  -- Count active assignees (rejected rows excluded) and how many submitted.
  SELECT count(*) FILTER (WHERE response IS DISTINCT FROM 'rejected'),
         count(*) FILTER (WHERE response IS DISTINCT FROM 'rejected' AND submitted_at IS NOT NULL)
    INTO v_total, v_submitted
  FROM public.task_assignees WHERE task_id = p_task_id;

  IF v_total = 0 OR v_submitted >= v_total THEN
    -- Everyone is in (or a creator-only task with no assignees) → go to review.
    -- This status change fires notify_task_status → "submitted for review" push.
    UPDATE public.tasks SET status = 'employee_done' WHERE id = p_task_id;

    INSERT INTO public.task_approvals (task_id, employee_done_at, employee_done_by)
    VALUES (p_task_id, now(), v_actor)
    ON CONFLICT (task_id) DO UPDATE
      SET employee_done_at = now(),
          employee_done_by = v_actor,
          reviewer_id      = NULL,
          reviewed_at      = NULL,
          review_decision  = NULL,
          review_reason    = NULL,
          updated_at       = now();

    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'submit_for_review', 'Submitted for review');
  ELSE
    -- Partial: keep the task in progress so Approve stays HIDDEN. Log only;
    -- no manager push until the last teammate submits.
    IF v_status <> 'in_progress' THEN
      UPDATE public.tasks SET status = 'in_progress' WHERE id = p_task_id;
    END IF;

    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'submit_partial',
            'Submitted their part (' || v_submitted || '/' || v_total || ')');
  END IF;
END;
$function$;

-- 3. Un-submit: pull MY part back out before the task reaches review ------------
CREATE OR REPLACE FUNCTION public.unsubmit_task_for_review(p_task_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.task_assignees
    SET submitted_at = NULL
    WHERE task_id = p_task_id AND profile_id = v_actor;

  -- If the task had just reached review on my submission, pull it back.
  UPDATE public.tasks SET status = 'in_progress'
    WHERE id = p_task_id AND status = 'employee_done';
END;
$function$;

GRANT EXECUTE ON FUNCTION public.unsubmit_task_for_review(uuid) TO authenticated;

-- 4. Requesting changes resets the submission cycle ----------------------------
CREATE OR REPLACE FUNCTION public.review_task(p_task_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  IF NOT (
    public.is_global_admin()
    OR (public.get_my_role() = 'manager' AND v_team = public.my_team_id())
  ) THEN
    RAISE EXCEPTION 'Not authorized to review this task.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision = 'approved' THEN
    IF v_status <> 'employee_done' THEN
      RAISE EXCEPTION 'Task is not pending review (current status "%").', v_status
        USING ERRCODE = 'check_violation';
    END IF;
    UPDATE public.tasks
      SET status = 'completed', completion_percentage = 100
      WHERE id = p_task_id;
  ELSE
    IF v_status NOT IN ('employee_done','completed') THEN
      RAISE EXCEPTION 'Changes can only be requested on a submitted or completed task (current status "%").', v_status
        USING ERRCODE = 'check_violation';
    END IF;
    UPDATE public.tasks
      SET status = 'changes_requested'
      WHERE id = p_task_id;
  END IF;

  -- Reset every assignee's submission so the next round needs fresh submits
  -- from all of them before Approve can show again.
  UPDATE public.task_assignees SET submitted_at = NULL WHERE task_id = p_task_id;

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
$function$;
