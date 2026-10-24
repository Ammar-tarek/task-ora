-- ============================================================================
-- ROLLBACK for PROPOSED_task_approval_workflow.sql
-- Reverses code objects. NOTE: a Postgres enum value CANNOT be dropped, so
-- 'changes_requested' stays in task_status (harmless if unused). If any task
-- is still in that state, move it back first (e.g. to 'in_progress') or the
-- app will show an unknown status.
-- ============================================================================

-- Move any tasks out of the new state before rolling back the app/UI.
-- UPDATE public.tasks SET status='in_progress' WHERE status='changes_requested';

DROP TRIGGER IF EXISTS trg_guard_task_status_transition ON public.tasks;
DROP FUNCTION IF EXISTS public.guard_task_status_transition();
DROP FUNCTION IF EXISTS public.submit_task_for_review(uuid);
DROP FUNCTION IF EXISTS public.review_task(uuid, text, text);

-- Restore notify_task_status to its pre-migration body.
CREATE OR REPLACE FUNCTION public.notify_task_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE aid uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='employee_done' THEN
      PERFORM public.notify_fanout(NEW.team_id,'task_done','Task marked done',
        '"'||NEW.title||'" is done and awaits review.','task',NEW.id,NULL);
    ELSIF NEW.status='client_approved' THEN
      FOR aid IN SELECT profile_id FROM public.task_assignees WHERE task_id=NEW.id LOOP
        PERFORM public.notify_fanout(NEW.team_id,'task_approved','Task approved',
          '"'||NEW.title||'" was approved.','task',NEW.id,aid);
      END LOOP;
      IF NOT EXISTS (SELECT 1 FROM public.task_assignees WHERE task_id=NEW.id) THEN
        PERFORM public.notify_fanout(NEW.team_id,'task_approved','Task approved',
          '"'||NEW.title||'" was approved.','task',NEW.id,NULL);
      END IF;
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
$$;

-- Restore create_crm_from_task to its pre-migration body (fires on client_approved).
CREATE OR REPLACE FUNCTION public.create_crm_from_task()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF  NEW.status    = 'client_approved'
  AND OLD.status   != 'client_approved'
  AND NEW.client_id IS NOT NULL
  AND NEW.cost      IS NOT NULL
  AND NEW.cost      > 0
  THEN
    INSERT INTO public.crm_entries (
      client_id, source_type, source_id,
      title, amount, status, created_by
    ) VALUES (
      NEW.client_id, 'task', NEW.id,
      'Task Completed: ' || NEW.title, NEW.cost, 'unpaid', NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$function$;

-- Review columns are left in place by default (harmless). To remove:
-- ALTER TABLE public.task_approvals
--   DROP COLUMN IF EXISTS reviewer_id,
--   DROP COLUMN IF EXISTS reviewed_at,
--   DROP COLUMN IF EXISTS review_decision,
--   DROP COLUMN IF EXISTS review_reason;
