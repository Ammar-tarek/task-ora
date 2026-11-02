-- ============================================================================
-- (NOT APPLIED) — Allow a manager/admin to REQUEST CHANGES after approval.
--
-- review_task used to require status = 'employee_done'. This relaxes it so:
--   * approve           : still only from 'employee_done'.
--   * changes_requested : from 'employee_done' OR 'completed' (reopen an
--                         already-approved task).
-- Everything else (authorization, reason-required, audit) is unchanged.
-- Apply in the Supabase SQL Editor.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.review_task(p_task_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
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
    -- changes_requested: allowed from pending review OR an already-completed task.
    IF v_status NOT IN ('employee_done','completed') THEN
      RAISE EXCEPTION 'Changes can only be requested on a submitted or completed task (current status "%").', v_status
        USING ERRCODE = 'check_violation';
    END IF;
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
