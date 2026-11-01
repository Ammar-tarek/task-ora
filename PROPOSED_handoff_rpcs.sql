-- ============================================================================
-- PROPOSED (NOT APPLIED) — Task Handoff RPC, DIRECT-TRANSFER model. Needs
-- explicit approval. APPLY ORDER: this file FIRST (its RPC sets the
-- `app.task_handoff` transaction GUC the guard triggers read), then
-- PROPOSED_task_handoff_field_lock.sql.
--
-- MODEL (user-approved 2026-10-31 — Option A, Direct Transfer):
--   * handoff IMMEDIATELY transfers ownership: tasks.team_id is set to the
--     RECEIVING team (not NULL). There is NO pending accept/reject step.
--   * handoff_from_team_id is stamped with the SENDER team — this both (a) marks
--     the task "transferred" so the definition lock engages, and (b) drives the
--     sender's SELECT-only policy (see field-lock file).
--   * handoff_to_team_id is forced NULL (the old pending column is unused now).
--   * assignees are cleared; the receiving manager assigns fresh.
--   * sender loses ALL write (team no longer matches its RLS); keeps view only.
--   * receiving MANAGER (team_id = my_team_id) owns the task and assignment.
--   * definition is DB-locked for everyone but a global admin (field-lock file).
--
-- REMOVED vs the previous proposal: accept_handoff() and reject_handoff(). The
-- direct model has no pending state, so they are deleted here (idempotent DROPs
-- below). They were PROPOSED-only (never applied), so nothing in prod depends on
-- them. The Flutter calls to 'accept_handoff'/'reject_handoff' are string RPC
-- names (no compile dependency); see HANDOFF_DIRECT_TRANSFER_REVIEW.md §UI for
-- the screen/repo cleanup to remove the now-dead accept/reject UI.
--
-- GUC NOTE: handoff_task sets `app.task_handoff='1'` TRANSACTION-LOCAL so the
-- guard triggers let its own plumbing writes (team_id + handoff_*) and its
-- assignee-clear through. An end user CANNOT set this GUC: the Supabase data API
-- runs one client statement per transaction and exposes no SET/set_config to
-- clients; custom app.* GUCs are not client-settable via PostgREST; the flag is
-- transaction-scoped so it never leaks across requests; and the only function
-- that sets it is this one, AFTER its authority check. The field-lock trigger
-- also bounds the flag so it can only widen the allow-set to handoff PLUMBING
-- columns, never a definition field.
-- ============================================================================

-- Remove the pending-acceptance RPCs from the previous proposal (idempotent).
DROP FUNCTION IF EXISTS public.accept_handoff(uuid);
DROP FUNCTION IF EXISTS public.reject_handoff(uuid);

-- HANDOFF (direct transfer): source manager (of the task's current team) or
-- global admin. Sets team_id = destination immediately.
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
  v_prev_from uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lock the task row; lock + state checks + update run in this one function
  -- transaction, so a concurrent handoff cannot race.
  SELECT team_id, handoff_from_team_id INTO v_src, v_prev_from
    FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_src IS NULL THEN
    RAISE EXCEPTION 'Task has no owning department (unknown or in an invalid state).'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Authority: the CURRENT owning team's manager, or a global admin. (After a
  -- transfer the owning team is the receiver, so this same check also gates
  -- re-routing — which is then blocked below for non-admins.)
  IF NOT (public.is_global_admin()
          OR (public.is_manager() AND public.my_team_id() = v_src)) THEN
    RAISE EXCEPTION 'Not authorized to hand off this task.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- NO department-level re-transfer: a task already transferred once
  -- (handoff_from_team_id set) may be routed onward ONLY by a global admin.
  IF v_prev_from IS NOT NULL AND NOT public.is_global_admin() THEN
    RAISE EXCEPTION 'This task was already transferred; only an admin can route it onward.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Mark this transaction as a handoff so the guard triggers let the plumbing
  -- writes (team_id + handoff_*) and the assignee-clear through. Transaction-local.
  PERFORM set_config('app.task_handoff', '1', true);

  IF NOT EXISTS (SELECT 1 FROM public.teams WHERE id = p_to_team_id AND is_active) THEN
    RAISE EXCEPTION 'Destination department is invalid or inactive.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF p_to_team_id = v_src THEN
    RAISE EXCEPTION 'Destination department equals source.' USING ERRCODE = 'check_violation';
  END IF;

  -- DIRECT TRANSFER: ownership moves now. team_id = receiving team.
  UPDATE public.tasks SET
    team_id              = p_to_team_id,
    handoff_from_team_id = v_src,
    handoff_to_team_id   = NULL,       -- no pending state in the direct model
    handoff_by           = v_actor,
    handoff_note         = p_note,
    updated_at           = now()
  WHERE id = p_task_id;

  -- Clear assignees: the receiving manager assigns fresh within their team.
  DELETE FROM public.task_assignees WHERE task_id = p_task_id;

  INSERT INTO public.task_audit_log (task_id, actor_id, action, old_value, new_value, notes)
  VALUES (p_task_id, v_actor, 'handoff',
          jsonb_build_object('team_id', v_src),
          jsonb_build_object('team_id', p_to_team_id,
                             'handoff_from_team_id', v_src),
          p_note);
END;
$$;

-- Lock down execution to authenticated users (the function self-checks authority).
REVOKE EXECUTE ON FUNCTION public.handoff_task(uuid,uuid,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.handoff_task(uuid,uuid,text) TO authenticated;

-- ── Rollback (removes ONLY what this file introduces) ───────────────────────
--   DROP FUNCTION IF EXISTS public.handoff_task(uuid, uuid, text);
--   -- (accept_handoff/reject_handoff were dropped by this migration; to restore
--   --  the old pending model, re-apply the previous proposal revision.)
