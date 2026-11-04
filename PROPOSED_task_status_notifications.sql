-- PROPOSED (run in Supabase SQL Editor) — richer task status-change push notifications.
-- Approved 2026-11-04. Redefines the ONE authoritative notifier notify_task_status()
-- (AFTER UPDATE trigger on public.tasks). MCP apply_migration was blocked by the
-- Production-Deploy guard (DDL), so run this manually.
--
-- Adds / changes (all departments):
--   • START WORK  — when an employee starts a task (not_started → in_progress ONLY;
--     withdraw-from-review is employee_done → in_progress and must NOT fire this),
--     notify the department managers + admins: "<name> started "<task>"." (actor excluded).
--   • SUBMIT FOR REVIEW — body now names the submitter: "<name> submitted "<task>" for
--     review." → department managers + admins (actor excluded). [was generic before]
--   • APPROVE AFTER REVIEW — assignees get "<task>" was approved after review. [kept]
--   • CHANGES REQUESTED — assignees get "<task>" needs changes… [kept]
--   • client_approved / client_rejected / handoff — unchanged.
-- Recipients + authorization are unchanged (notify_fanout = primary + admins + the
-- team's managers). Notifications carry reference_type='task', reference_id=task id,
-- so tapping a push deep-links to /tasks/detail/<id> (app side).

CREATE OR REPLACE FUNCTION public.notify_task_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  aid uuid;
  v_actor uuid := auth.uid();
  v_actor_name text;
BEGIN
  IF v_actor IS NOT NULL THEN
    SELECT full_name INTO v_actor_name FROM public.profiles WHERE id = v_actor;
  END IF;
  v_actor_name := COALESCE(NULLIF(btrim(v_actor_name), ''), 'Someone');

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='in_progress' AND OLD.status='not_started' THEN
      PERFORM public.notify_fanout(NEW.team_id,'system','Task started',
        v_actor_name||' started "'||NEW.title||'".','task',NEW.id,NULL,v_actor);
    ELSIF NEW.status='employee_done' THEN
      PERFORM public.notify_fanout(NEW.team_id,'task_done','Task submitted for review',
        v_actor_name||' submitted "'||NEW.title||'" for review.','task',NEW.id,NULL,v_actor);
    ELSIF NEW.status='completed' AND OLD.status='employee_done' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_approved','Task approved',
          '"'||NEW.title||'" was approved after review.','task',NEW.id,aid);
      END LOOP;
    ELSIF NEW.status='changes_requested' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_rejected','Changes requested',
          '"'||NEW.title||'" needs changes before it can be approved.','task',NEW.id,aid);
      END LOOP;
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
$function$;
