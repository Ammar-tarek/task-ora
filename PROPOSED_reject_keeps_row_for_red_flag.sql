-- ============================================================================
-- (NOT APPLIED) — Keep a rejected assignment ON the task (marked 'rejected')
-- instead of deleting it, so managers/admins can see a task that an employee
-- rejected and highlight it RED until it is reassigned.
--
-- Only respond_to_assignment changes: on REJECT it now UPDATEs the assignee row
-- to response='rejected' (was: DELETE). Accept is unchanged. Reassigning
-- (assignEmployees deletes all + inserts fresh) clears the rejected row; if the
-- new assignee also rejects, the task turns red again.
--
-- The app hides a rejected row from the rejecting employee's own list, so they
-- no longer see the task they declined. Apply in the Supabase SQL Editor.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.respond_to_assignment(p_task_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
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

  SELECT response INTO v_current
  FROM public.task_assignees
  WHERE task_id = p_task_id AND profile_id = v_actor
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not assigned to this task.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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
    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'assignment_rejected', btrim(p_reason));
    -- Keep the row, marked rejected (was DELETE), so the task shows as needing
    -- reassignment (red) to managers/admins until it is reassigned.
    UPDATE public.task_assignees
       SET response = 'rejected', responded_at = now(), response_reason = btrim(p_reason)
     WHERE task_id = p_task_id AND profile_id = v_actor;
  END IF;

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
