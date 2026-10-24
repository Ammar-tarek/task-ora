-- ============================================================================
-- PROPOSED (NOT APPLIED) — secure Task Handoff RPCs. Needs explicit approval.
--
-- Why: handoff sets tasks.team_id = NULL, which the manager RLS WITH CHECK
-- (team_id = my_team_id()) cannot allow — so handoff currently runs on the
-- service-role client, bypassing ALL authorization. These SECURITY DEFINER
-- RPCs move handoff onto the authenticated session with server-side checks:
--   * caller identified via auth.uid() (never client-supplied)
--   * source authority derived from the TASK's current team (not a client arg)
--   * destination team validated (exists, active)
--   * only handoff fields touched; atomic; writes an audit row
--   * unauthorized callers rejected with insufficient_privilege
--
-- After APPLY, change task_repository to call these via the RLS client:
--   _client.rpc('handoff_task',   {p_task_id, p_to_team_id, p_note})
--   _client.rpc('accept_handoff', {p_task_id})
--   _client.rpc('reject_handoff', {p_task_id})
-- and drop the _adminClient writes in handoffTask/acceptHandoff/rejectHandoff
-- (keep the notification fan-out as-is). Do NOT change the repo before apply,
-- or handoff breaks.
-- ============================================================================

-- 1) HANDOFF: source manager (of the task's current team) or global admin.
CREATE OR REPLACE FUNCTION public.handoff_task(
  p_task_id uuid, p_to_team_id uuid, p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_src uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lock the task row; the lock + state checks + update run in this one
  -- function transaction, so concurrent handoff/accept/reject cannot race.
  SELECT team_id INTO v_src FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_src IS NULL THEN
    RAISE EXCEPTION 'Task has no source department (already handed off or unknown).'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT (public.is_global_admin()
          OR (public.is_manager() AND public.my_team_id() = v_src)) THEN
    RAISE EXCEPTION 'Not authorized to hand off this task.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.teams WHERE id = p_to_team_id AND is_active) THEN
    RAISE EXCEPTION 'Destination department is invalid or inactive.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF p_to_team_id = v_src THEN
    RAISE EXCEPTION 'Destination department equals source.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.tasks SET
    team_id              = NULL,
    handoff_from_team_id = v_src,
    handoff_to_team_id   = p_to_team_id,
    handoff_by           = v_actor,
    handoff_note         = p_note,
    updated_at           = now()
  WHERE id = p_task_id;

  DELETE FROM public.task_assignees WHERE task_id = p_task_id;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, old_value, new_value, notes)
  VALUES (p_task_id, v_actor, 'handoff',
          jsonb_build_object('team_id', v_src),
          jsonb_build_object('team_id', NULL,
                             'handoff_from_team_id', v_src,
                             'handoff_to_team_id', p_to_team_id),
          p_note);
END;
$$;

-- 2) ACCEPT: destination manager (of handoff_to_team) or global admin.
CREATE OR REPLACE FUNCTION public.accept_handoff(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_to uuid; v_old uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT handoff_to_team_id, team_id INTO v_to, v_old
  FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_to IS NULL THEN
    RAISE EXCEPTION 'Task is not awaiting a handoff.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT (public.is_global_admin()
          OR (public.is_manager() AND public.my_team_id() = v_to)) THEN
    RAISE EXCEPTION 'Not authorized to accept this handoff.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tasks SET
    team_id            = v_to,
    handoff_to_team_id = NULL,
    updated_at         = now()
  WHERE id = p_task_id;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, old_value, new_value)
  VALUES (p_task_id, v_actor, 'handoff_accepted',
          jsonb_build_object('team_id', v_old, 'handoff_to_team_id', v_to),
          jsonb_build_object('team_id', v_to, 'handoff_to_team_id', NULL));
END;
$$;

-- 3) REJECT: destination manager (of handoff_to_team) or global admin; task
--    returns to its source department.
CREATE OR REPLACE FUNCTION public.reject_handoff(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_to uuid; v_from uuid; v_old uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT handoff_to_team_id, handoff_from_team_id, team_id INTO v_to, v_from, v_old
  FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_to IS NULL THEN
    RAISE EXCEPTION 'Task is not awaiting a handoff.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT (public.is_global_admin()
          OR (public.is_manager() AND public.my_team_id() = v_to)) THEN
    RAISE EXCEPTION 'Not authorized to reject this handoff.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tasks SET
    team_id              = COALESCE(v_from, team_id),
    handoff_to_team_id   = NULL,
    handoff_from_team_id = NULL,
    updated_at           = now()
  WHERE id = p_task_id;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, old_value, new_value)
  VALUES (p_task_id, v_actor, 'handoff_rejected',
          jsonb_build_object('team_id', v_old,
                             'handoff_from_team_id', v_from,
                             'handoff_to_team_id', v_to),
          jsonb_build_object('team_id', COALESCE(v_from, v_old),
                             'handoff_to_team_id', NULL,
                             'handoff_from_team_id', NULL));
END;
$$;

-- Lock down execution to authenticated users (functions self-check authority).
REVOKE EXECUTE ON FUNCTION public.handoff_task(uuid,uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.accept_handoff(uuid)          FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reject_handoff(uuid)          FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.handoff_task(uuid,uuid,text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.accept_handoff(uuid)          TO authenticated;
GRANT  EXECUTE ON FUNCTION public.reject_handoff(uuid)          TO authenticated;
