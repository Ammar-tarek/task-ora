-- ============================================================================
-- FIX — Duplicate task notifications (approve / request-changes / client).
-- ============================================================================
-- notify_task_status looped notify_fanout ONCE PER ASSIGNEE for the approve,
-- changes_requested, client_approved and client_rejected branches. Every
-- notify_fanout call ALSO inserts for all admins + the team's managers, so a
-- task with N assignees gave every admin/manager N identical rows (verified:
-- "Task approved" / "Changes requested" inserted twice, same timestamp).
--
-- Fix: send ONE row per recipient. New helper notify_task_all() inserts a single
-- DISTINCT row for (all the task's assignees ∪ admins ∪ team managers), minus
-- the actor. The trigger calls it once per branch — no loop, no duplicates.
-- (The 'started' and 'submitted for review' branches already called fanout once,
-- so they were never duplicated and are unchanged.)
--
-- Apply in the Supabase SQL editor. Idempotent / safe to re-run.
-- ============================================================================

-- 1. One DISTINCT row per recipient for a task-wide notification ---------------
CREATE OR REPLACE FUNCTION public.notify_task_all(
  p_team    uuid,
  p_type    public.notification_type,
  p_title   text,
  p_body    text,
  p_task    uuid,
  p_exclude uuid DEFAULT NULL
)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id)
  SELECT DISTINCT r, p_type, p_title, p_body, 'task', p_task
  FROM (
    SELECT profile_id AS r FROM public.task_assignees WHERE task_id = p_task
    UNION
    SELECT id FROM public.profiles WHERE role = 'admin' OR is_super_admin = true
    UNION
    SELECT id FROM public.profiles
      WHERE role = 'manager' AND p_team IS NOT NULL AND team_id = p_team
  ) x
  WHERE r IS NOT NULL AND (p_exclude IS NULL OR r <> p_exclude);
$function$;

-- 2. Trigger function: replace the per-assignee loops with one call each -------
CREATE OR REPLACE FUNCTION public.notify_task_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor      uuid := auth.uid();
  v_actor_name text;
BEGIN
  IF v_actor IS NOT NULL THEN
    SELECT full_name INTO v_actor_name FROM public.profiles WHERE id = v_actor;
  END IF;
  v_actor_name := COALESCE(NULLIF(btrim(v_actor_name), ''), 'Someone');

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'in_progress' AND OLD.status = 'not_started' THEN
      PERFORM public.notify_fanout(NEW.team_id,'system','Task started',
        v_actor_name||' started "'||NEW.title||'".','task',NEW.id,NULL,v_actor);
    ELSIF NEW.status = 'employee_done' THEN
      PERFORM public.notify_fanout(NEW.team_id,'task_done','Task submitted for review',
        v_actor_name||' submitted "'||NEW.title||'" for review.','task',NEW.id,NULL,v_actor);
    ELSIF NEW.status = 'completed' AND OLD.status = 'employee_done' THEN
      PERFORM public.notify_task_all(NEW.team_id,'task_approved','Task approved',
        '"'||NEW.title||'" was approved after review.',NEW.id,v_actor);
    ELSIF NEW.status = 'changes_requested' THEN
      PERFORM public.notify_task_all(NEW.team_id,'task_rejected','Changes requested',
        '"'||NEW.title||'" needs changes before it can be approved.',NEW.id,v_actor);
    ELSIF NEW.status = 'client_approved' THEN
      PERFORM public.notify_task_all(NEW.team_id,'task_approved','Task approved',
        '"'||NEW.title||'" was approved.',NEW.id,v_actor);
    ELSIF NEW.status = 'client_rejected' THEN
      PERFORM public.notify_task_all(NEW.team_id,'task_rejected','Task needs rework',
        '"'||NEW.title||'" was rejected.',NEW.id,v_actor);
    END IF;
  END IF;

  IF NEW.handoff_to_team_id IS NOT NULL
     AND NEW.handoff_to_team_id IS DISTINCT FROM OLD.handoff_to_team_id THEN
    PERFORM public.notify_fanout(NEW.handoff_to_team_id,'system','New task handoff',
      '"'||NEW.title||'" was sent to your department. Check the Waiting List.','task',NEW.id,NULL);
  END IF;
  RETURN NEW;
END;
$function$;
