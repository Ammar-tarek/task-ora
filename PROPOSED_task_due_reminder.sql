-- ============================================================================
-- EDIT 2 — Task due-date reminder: push the assignees 1 hour before deadline.
-- ============================================================================
-- tasks.due_date is ALREADY timestamptz, so day + hour + minute need NO schema
-- change (the Flutter app just stopped chopping the time off). This file only
-- adds the 1-hour-before reminder, mirroring the existing event reminder system
-- (send_event_start_reminders + event_start_reminder_log + 1-min cron).
--
-- Recipients = the task's ACTIVE assignees (rejected rows excluded) — i.e. "the
-- assigned one(s)". The notification lands as reference_type='task', so tapping
-- it deep-links to the task (GoRoute /tasks/detail/:id).
--
-- Apply in the Supabase SQL editor. Idempotent / safe to re-run.
-- ============================================================================

-- 1. One-shot-per-(task,person,offset) log, so a reminder is sent only once ----
CREATE TABLE IF NOT EXISTS public.task_due_reminder_log (
  task_id        uuid NOT NULL REFERENCES public.tasks(id)    ON DELETE CASCADE,
  profile_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  offset_minutes int  NOT NULL,
  sent_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (task_id, profile_id, offset_minutes)
);
-- Written only by SECURITY DEFINER cron fn below; no end-user access needed.
ALTER TABLE public.task_due_reminder_log ENABLE ROW LEVEL SECURITY;

-- 2. The sender: run every minute, fire once when due_date is <= 60 min away ---
CREATE OR REPLACE FUNCTION public.send_task_due_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public','extensions'
AS $function$
DECLARE inserted integer;
BEGIN
  WITH due AS (
    SELECT t.id AS task_id, a.profile_id, 60 AS offset_minutes, t.title, t.due_date
    FROM public.tasks t
    JOIN public.task_assignees a
      ON a.task_id = t.id AND a.response IS DISTINCT FROM 'rejected'
    WHERE t.due_date IS NOT NULL
      AND t.is_archived = false
      AND t.status NOT IN ('completed','client_approved','client_rejected')
      AND t.due_date > now()
      AND t.due_date <= now() + interval '60 minutes'
  ),
  recorded AS (
    INSERT INTO public.task_due_reminder_log (task_id, profile_id, offset_minutes, sent_at)
    SELECT task_id, profile_id, offset_minutes, now() FROM due
    ON CONFLICT (task_id, profile_id, offset_minutes) DO NOTHING
    RETURNING task_id, profile_id, offset_minutes
  )
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read)
  SELECT r.profile_id, 'system',
    'Task Due in 1 Hour: ' || COALESCE(d.title,'task'),
    'Due ' || to_char(d.due_date AT TIME ZONE 'Africa/Cairo','YYYY-MM-DD HH24:MI'),
    'task', r.task_id, false
  FROM recorded r JOIN due d USING (task_id, profile_id, offset_minutes);

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Task due reminders sent: %', inserted;
END;
$function$;

-- 3. Re-arm the reminder when the deadline is moved ----------------------------
CREATE OR REPLACE FUNCTION public.tg_task_due_reset_reminders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.due_date IS DISTINCT FROM OLD.due_date THEN
    DELETE FROM public.task_due_reminder_log WHERE task_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_task_due_reset_reminders ON public.tasks;
CREATE TRIGGER trg_task_due_reset_reminders
  AFTER UPDATE OF due_date ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.tg_task_due_reset_reminders();

-- 4. Schedule it every minute (same cadence as the event reminders) ------------
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'task-due-reminders-1min';
SELECT cron.schedule('task-due-reminders-1min', '* * * * *',
                     $$SELECT public.send_task_due_reminders();$$);
