-- 20261026_notify_event_created_include_dept_employees.sql
-- Applied to prod 2026-10-26 (MCP apply_migration).
--
-- Updates notify_event_created ONLY. Keeps the existing fan-out (all
-- admins/super-admins + the owning department's managers, creator excluded) and
-- ADDS active employees of the event's own department. The shared notify_fanout
-- function is NOT modified. A NOT EXISTS guard prevents duplicate notifications
-- for anyone already notified for this event (also idempotent on re-fire). The
-- notification format (title + date · start–end, Africa/Cairo) is unchanged, and
-- the notifications->FCM push trigger (tg_notifications_fcm_push) is reused.
--
-- Reverse: restore the prior body (fan-out only) from
-- 20261026_event_link_and_created_notice.sql.

CREATE OR REPLACE FUNCTION public.notify_event_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_title text := 'New Event: ' || NEW.title;
  v_body  text := to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo', 'YYYY-MM-DD')
                  || ' · '
                  || to_char(NEW.start_time AT TIME ZONE 'Africa/Cairo', 'HH24:MI')
                  || ' – '
                  || to_char(NEW.end_time   AT TIME ZONE 'Africa/Cairo', 'HH24:MI');
BEGIN
  -- Unchanged: admins/super-admins (company-wide) + the owning department's
  -- managers, excluding the creator.
  PERFORM public.notify_fanout(
    NEW.team_id,
    'calendar_event',
    v_title,
    v_body,
    'event',
    NEW.id,
    NULL,
    NEW.created_by
  );

  -- Added: active EMPLOYEES of this event's department only (team_id match).
  -- Creator excluded. Skip anyone already notified for this event so no one
  -- gets a duplicate (also makes a re-fire idempotent). notifications insert
  -- → tg_notifications_fcm_push delivers via FCM (unchanged).
  IF NEW.team_id IS NOT NULL THEN
    INSERT INTO public.notifications
      (recipient_id, type, title, body, reference_type, reference_id)
    SELECT p.id, 'calendar_event', v_title, v_body, 'event', NEW.id
    FROM public.profiles p
    WHERE p.role = 'employee'
      AND p.status = 'active'
      AND p.team_id = NEW.team_id
      AND p.id <> NEW.created_by
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = p.id
          AND n.reference_type = 'event'
          AND n.reference_id = NEW.id
      );
  END IF;

  RETURN NEW;
END;
$function$;
