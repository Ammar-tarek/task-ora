-- 20261026_event_end_time_reminders_v2.sql
-- Applied to prod 2026-10-26 (MCP apply_migration).
--
-- End-time event reminders + unified recipient set. Sends three department-scoped
-- notifications per event (all via the notifications->FCM pipeline):
--   • on create (notify_event_created, AFTER INSERT)
--   • 60 min before end_time   (send_event_reminders, cron every minute)
--   • 5  min before end_time   (send_event_reminders, cron every minute)
-- Recipients (all three): the creator + all admins/super-admins (company-wide) +
-- the event department's managers + active employees. Clients never included.
-- Dedup via event_reminders UNIQUE (event_id, profile_id, offset_minutes).
-- The reminder-reset trigger is removed so a reschedule cannot resend an
-- already-sent offset (the sent-log is preserved).

-- A) Shared recipient set.
CREATE OR REPLACE FUNCTION public.event_recipient_ids(p_team uuid, p_creator uuid)
 RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT DISTINCT id FROM (
    SELECT p_creator AS id WHERE p_creator IS NOT NULL
    UNION
    SELECT id FROM public.profiles WHERE role = 'admin' OR is_super_admin = true
    UNION
    SELECT id FROM public.profiles WHERE role = 'manager'  AND p_team IS NOT NULL AND team_id = p_team
    UNION
    SELECT id FROM public.profiles WHERE role = 'employee' AND status = 'active'
                                     AND p_team IS NOT NULL AND team_id = p_team
  ) x;
$$;
REVOKE ALL ON FUNCTION public.event_recipient_ids(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.event_recipient_ids(uuid, uuid) TO service_role;

-- B) Immediate event-created push — includes the creator.
CREATE OR REPLACE FUNCTION public.notify_event_created()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_title text := 'New Event: ' || NEW.title;
  v_body  text := to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo','YYYY-MM-DD')
                  || ' · ' || to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo','HH24:MI')
                  || ' – ' || to_char(NEW.end_time   AT TIME ZONE 'Africa/Cairo','HH24:MI');
BEGIN
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id)
  SELECT rid, 'calendar_event', v_title, v_body, 'event', NEW.id
  FROM public.event_recipient_ids(NEW.team_id, NEW.created_by) AS rid
  WHERE NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_id = rid AND n.reference_type = 'event' AND n.reference_id = NEW.id
  );
  RETURN NEW;
END;
$function$;

-- C) Allow the 5-minute offset (event_reminders was empty at apply time).
ALTER TABLE public.event_reminders DROP CONSTRAINT event_reminders_offset_minutes_check;
ALTER TABLE public.event_reminders
  ADD CONSTRAINT event_reminders_offset_minutes_check CHECK (offset_minutes = ANY (ARRAY[5, 60]));

-- D) End-time reminders — one atomic statement; idempotent + concurrency-safe.
CREATE OR REPLACE FUNCTION public.send_event_reminders()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions'
AS $function$
DECLARE inserted integer;
BEGIN
  WITH due AS (
    SELECT e.id AS event_id, r AS profile_id, o.offset_minutes, e.title, e.end_time
    FROM public.events e
    CROSS JOIN (VALUES (60),(5)) AS o(offset_minutes)
    CROSS JOIN LATERAL public.event_recipient_ids(e.team_id, e.created_by) AS r
    WHERE e.team_id IS NOT NULL
      AND e.status NOT IN ('cancelled','cancelled_by_client','cancelled_by_us','done','completed')
      AND e.end_time > now()
      AND e.end_time <= now() + make_interval(mins => o.offset_minutes)
  ),
  recorded AS (
    INSERT INTO public.event_reminders (event_id, profile_id, offset_minutes, sent_at)
    SELECT event_id, profile_id, offset_minutes, now() FROM due
    ON CONFLICT (event_id, profile_id, offset_minutes) DO NOTHING
    RETURNING event_id, profile_id, offset_minutes
  )
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read)
  SELECT r.profile_id, 'meeting_reminder',
    CASE WHEN r.offset_minutes = 60
         THEN 'Event Ending in 1 Hour: ' ELSE 'Event Ending in 5 Minutes: ' END
      || COALESCE(d.title,'event'),
    'Ends ' || to_char(d.end_time AT TIME ZONE 'Africa/Cairo','YYYY-MM-DD HH24:MI'),
    'event', r.event_id, false
  FROM recorded r JOIN due d USING (event_id, profile_id, offset_minutes);
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Event end-time reminders sent: %', inserted;
END;
$function$;

-- E) Remove the reminder-reset trigger + function (no sent-log wipe on reschedule).
DROP TRIGGER IF EXISTS trg_event_reset_reminders ON public.events;
DROP FUNCTION IF EXISTS public.tg_event_reset_reminders();

-- F) One-minute poll — guarded in-place update of the existing job by validated id.
DO $$
DECLARE
  v_jobid  bigint;
  v_count  integer;
  v_sched  text;
  v_cmd    text;
  v_active boolean;
BEGIN
  SELECT count(*) INTO v_count
  FROM cron.job WHERE jobname = 'event-reminders-5min' AND username = 'postgres';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Abort: expected exactly 1 cron job "event-reminders-5min" owned by postgres, found %', v_count;
  END IF;
  SELECT jobid INTO v_jobid
  FROM cron.job WHERE jobname = 'event-reminders-5min' AND username = 'postgres';
  PERFORM cron.alter_job(job_id := v_jobid, schedule := '* * * * *');
  SELECT schedule, command, active INTO v_sched, v_cmd, v_active
  FROM cron.job WHERE jobid = v_jobid;
  IF v_sched <> '* * * * *'
     OR v_cmd <> 'SELECT public.send_event_reminders();'
     OR v_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Abort: cron job % unexpected after update (schedule=%, command=%, active=%)',
      v_jobid, v_sched, v_cmd, v_active;
  END IF;
END $$;
