-- ============================================================================
-- Attendance reminder scheduled job.
--
-- Official attendance time is 11:00 AM (Africa/Cairo). One hour later, at
-- 12:00 PM Cairo, every active non-admin employee who has NOT yet checked in
-- today receives an `attendance_alert` notification. That row insert flows
-- through the existing pipeline automatically:
--   notifications INSERT -> tr_send_fcm_notification -> FCM push to phone
--                        -> Supabase Realtime -> in-app / local notification
-- No client changes are required (the app already renders `attendance_alert`).
--
-- DST-safe: the 12 PM check uses `now() AT TIME ZONE 'Africa/Cairo'`, which
-- honours Egypt's daylight-saving rules via the Postgres tz database rather
-- than a fixed UTC offset. The cron job runs hourly and the function itself
-- gates on the Cairo hour, so no separate summer/winter schedule is needed.
-- ============================================================================

-- 1. Make sure the notification enum can carry the reminder type.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'notification_type'
      AND e.enumlabel = 'attendance_alert'
  ) THEN
    ALTER TYPE public.notification_type ADD VALUE 'attendance_alert';
  END IF;
END
$$;

-- 2. Scheduler extension. On Supabase pg_cron installs into schema `cron`,
--    so its functions are referenced as `cron.schedule` / `cron.unschedule`.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 3. Reminder function.
CREATE OR REPLACE FUNCTION public.send_attendance_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  cairo_now   timestamp := now() AT TIME ZONE 'Africa/Cairo';
  today_cairo date      := (now() AT TIME ZONE 'Africa/Cairo')::date;
  inserted    integer;
BEGIN
  -- Only fire at 12:00 PM Cairo (one hour after the 11 AM official time).
  -- The cron job runs every hour; every other hour is a no-op.
  IF EXTRACT(HOUR FROM cairo_now)::int <> 12 THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT
    p.id,
    'attendance_alert',
    'Attendance reminder',
    'You have not checked in yet. The official attendance time was 11:00 AM — please check in now.',
    'attendance_reminder',
    NULL,
    false,
    'in_app'
  FROM public.profiles p
  WHERE p.status = 'active'
    -- All non-admin staff. Clients are excluded (they don't attend).
    AND p.role NOT IN ('admin', 'client')
    -- No check-in recorded for today.
    AND NOT EXISTS (
      SELECT 1
      FROM public.attendance a
      WHERE a.employee_id = p.id
        AND a.attendance_date = today_cairo
        AND a.check_in_time IS NOT NULL
    )
    -- Don't remind twice in the same day.
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.recipient_id = p.id
        AND n.type = 'attendance_alert'
        AND n.reference_type = 'attendance_reminder'
        AND (n.created_at AT TIME ZONE 'Africa/Cairo')::date = today_cairo
    );

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Attendance reminders sent: %', inserted;
END;
$$;

-- 4. Schedule it hourly (the function gates itself to 12 PM Cairo).
--    Re-registering is idempotent: unschedule any prior copy first.
DO $$
BEGIN
  PERFORM cron.unschedule('attendance-reminder-hourly');
EXCEPTION WHEN OTHERS THEN
  -- Job did not exist yet; ignore.
  NULL;
END
$$;

SELECT cron.schedule(
  'attendance-reminder-hourly',
  '0 * * * *',
  $$SELECT public.send_attendance_reminders();$$
);
