-- 20261026_event_link_and_created_notice.sql
-- Applied to prod 2026-10-26 (MCP apply_migration).
--
-- 1) Adds an optional `link` column to events for the simplified Event form.
--    Nullable; no backfill; existing rows/records untouched.
-- 2) Updates notify_event_created so the event-created push states the title +
--    scheduled date/time. Recipient fan-out (department via team_id, creator
--    excluded) and the notifications->FCM push trigger are unchanged.

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS link text;

CREATE OR REPLACE FUNCTION public.notify_event_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.notify_fanout(
    NEW.team_id,
    'calendar_event',
    'New Event: ' || NEW.title,
    to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo', 'YYYY-MM-DD')
      || ' · '
      || to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo', 'HH24:MI')
      || ' – '
      || to_char(NEW.end_time   AT TIME ZONE 'Africa/Cairo', 'HH24:MI'),
    'event',
    NEW.id,
    NULL,
    NEW.created_by
  );
  RETURN NEW;
END;
$function$;
