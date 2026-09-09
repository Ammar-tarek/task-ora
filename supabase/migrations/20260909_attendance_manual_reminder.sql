-- Manual attendance reminder (button in the app), on top of the automatic
-- 12 PM Cairo job. Manager (own team) / admin (all or one team) can nudge
-- everyone currently not checked in, any time, through the existing
-- notifications -> FCM -> Realtime pipeline. Idempotent on the reminder row
-- (keeps original sent_at); the push itself may repeat as a deliberate nudge.
CREATE OR REPLACE FUNCTION public.send_manual_attendance_reminders(
  p_team_id uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  caller_id   uuid := auth.uid();
  caller_role text;
  caller_team uuid;
  today_cairo date := (now() AT TIME ZONE 'Africa/Cairo')::date;
  cnt integer := 0;
BEGIN
  IF caller_id IS NULL THEN RETURN 0; END IF;
  SELECT role, team_id INTO caller_role, caller_team FROM public.profiles WHERE id = caller_id;
  IF caller_role NOT IN ('admin', 'manager') THEN RETURN 0; END IF;

  CREATE TEMP TABLE _targets ON COMMIT DROP AS
  SELECT p.id FROM public.profiles p
  WHERE p.status = 'active' AND p.role IN ('employee', 'manager')
    AND NOT EXISTS (SELECT 1 FROM public.attendance a
      WHERE a.employee_id = p.id AND a.attendance_date = today_cairo AND a.check_in_time IS NOT NULL)
    AND (
      (caller_role = 'admin' AND (p_team_id IS NULL OR p.team_id = p_team_id))
      OR (caller_role = 'manager' AND caller_team IS NOT NULL AND p.team_id = caller_team)
    );

  INSERT INTO public.attendance_reminders (employee_id, reminder_date, sent_at)
  SELECT id, today_cairo, now() FROM _targets
  ON CONFLICT (employee_id, reminder_date) DO NOTHING;

  INSERT INTO public.notifications (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT id, 'attendance_alert', 'Attendance reminder',
    'You have not checked in yet. Please check in now.',
    'attendance_reminder', NULL, false, 'in_app'
  FROM _targets;

  SELECT count(*) INTO cnt FROM _targets;
  RETURN cnt;
END; $$;

REVOKE ALL ON FUNCTION public.send_manual_attendance_reminders(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.send_manual_attendance_reminders(uuid) TO authenticated;
