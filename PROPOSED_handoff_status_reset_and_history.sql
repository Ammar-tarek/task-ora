-- ============================================================================
-- (NOT APPLIED) — On handoff: reset the task to "To Do", and record a readable
-- history line "Transferred from <dept> to <dept> by <name>".
--
-- Replaces public.handoff_task. Two additions vs the current version:
--   1) the UPDATE now sets status='not_started' and completion_percentage=0, so
--      a transferred task restarts at To Do for the receiving department.
--   2) the task_audit_log 'handoff' row's notes is now a human-readable message
--      with the source + destination DEPARTMENT NAMES and the transferrer NAME,
--      so Task Details > Edit History shows who moved it and from where.
--
-- Safe: on the first transfer the definition guard returns early
-- (OLD.handoff_from_team_id IS NULL), and status/progress are always allowed;
-- the handoff GUC lets the plumbing columns through as before.
-- Apply in the Supabase SQL Editor.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handoff_task(
  p_task_id uuid, p_to_team_id uuid, p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor      uuid := auth.uid();
  v_src        uuid;
  v_prev_from  uuid;
  v_src_name   text;
  v_dst_name   text;
  v_actor_name text;
  v_msg        text;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT team_id, handoff_from_team_id INTO v_src, v_prev_from
    FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_src IS NULL THEN
    RAISE EXCEPTION 'Task has no owning department (unknown or in an invalid state).'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT (public.is_global_admin()
          OR (public.is_manager() AND public.my_team_id() = v_src)) THEN
    RAISE EXCEPTION 'Not authorized to hand off this task.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_prev_from IS NOT NULL AND NOT public.is_global_admin() THEN
    RAISE EXCEPTION 'This task was already transferred; only an admin can route it onward.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM set_config('app.task_handoff', '1', true);

  IF NOT EXISTS (SELECT 1 FROM public.teams WHERE id = p_to_team_id AND is_active) THEN
    RAISE EXCEPTION 'Destination department is invalid or inactive.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF p_to_team_id = v_src THEN
    RAISE EXCEPTION 'Destination department equals source.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT name INTO v_src_name   FROM public.teams    WHERE id = v_src;
  SELECT name INTO v_dst_name   FROM public.teams    WHERE id = p_to_team_id;
  SELECT full_name INTO v_actor_name FROM public.profiles WHERE id = v_actor;

  -- DIRECT TRANSFER: ownership moves now; the task restarts at To Do.
  UPDATE public.tasks SET
    team_id               = p_to_team_id,
    handoff_from_team_id  = v_src,
    handoff_to_team_id    = NULL,
    handoff_by            = v_actor,
    handoff_note          = p_note,
    status                = 'not_started',
    completion_percentage = 0,
    updated_at            = now()
  WHERE id = p_task_id;

  -- Clear assignees: the receiving manager assigns fresh.
  DELETE FROM public.task_assignees WHERE task_id = p_task_id;

  v_msg := 'Transferred from ' || COALESCE(v_src_name, 'another department')
           || ' to '  || COALESCE(v_dst_name, 'another department')
           || ' by '  || COALESCE(v_actor_name, 'someone')
           || CASE WHEN COALESCE(btrim(p_note), '') <> '' THEN ' — ' || p_note ELSE '' END;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, old_value, new_value, notes)
  VALUES (p_task_id, v_actor, 'handoff',
          jsonb_build_object('team_id', v_src),
          jsonb_build_object('team_id', p_to_team_id, 'handoff_from_team_id', v_src),
          v_msg);
END;
$$;
