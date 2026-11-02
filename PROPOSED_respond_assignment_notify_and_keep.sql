-- ============================================================================
-- (NOT APPLIED) — respond_to_assignment: keep the rejected row AND reliably
-- notify admins + the team's managers that the employee accepted/rejected.
--
-- The previous version relied on notify_fanout inside a BEGIN/EXCEPTION that
-- silently swallowed the notification (no task_rejected/accepted rows were
-- created). This inserts the notification DIRECTLY into public.notifications
-- (which fires the FCM push trigger), so the push always goes out:
--   "<name> rejected the task"  /  "<name> accepted the task".
-- Reject still KEEPS the assignee row marked 'rejected' (for the red flag).
-- Apply in the Supabase SQL Editor.
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
  v_ntype   notification_type;
  v_ntitle  text;
  v_nbody   text;
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
    v_ntype  := 'task_assigned';
    v_ntitle := 'Task Accepted';
    v_nbody  := COALESCE(v_name,'An employee') || ' accepted the task "' || COALESCE(v_title,'Task') || '".';
  ELSE
    INSERT INTO public.task_audit_log (task_id, actor_id, action, notes)
    VALUES (p_task_id, v_actor, 'assignment_rejected', btrim(p_reason));
    -- Keep the row, marked rejected, so the task shows red (needs reassignment).
    UPDATE public.task_assignees
       SET response = 'rejected', responded_at = now(), response_reason = btrim(p_reason)
     WHERE task_id = p_task_id AND profile_id = v_actor;
    v_ntype  := 'task_rejected';
    v_ntitle := 'Task Rejected';
    v_nbody  := COALESCE(v_name,'An employee') || ' rejected the task "' || COALESCE(v_title,'Task')
                || '" — ' || COALESCE(btrim(p_reason), '');
  END IF;

  -- Notify admins + the team's managers directly (fires the FCM push trigger).
  INSERT INTO public.notifications(recipient_id, type, title, body, reference_type, reference_id)
  SELECT DISTINCT p.id, v_ntype, v_ntitle, v_nbody, 'task', p_task_id
  FROM public.profiles p
  WHERE (p.role = 'admin' OR p.is_super_admin = true
         OR (p.role = 'manager' AND v_team IS NOT NULL AND p.team_id = v_team))
    AND p.id <> v_actor;
END;
$$;
