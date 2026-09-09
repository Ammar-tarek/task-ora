-- Attendance status rules:
--   * Late    — first automatic check-in at/after 3 PM Cairo.
--   * Present — first automatic check-in before 3 PM Cairo.
--   * Absent  — no attendance row for the day (created by a daily job so the
--               record persists and admins can edit / cancel it).
-- Admin controls already exist in the app (AttendanceRepository.overrideAttendance
-- sets any status incl. changing an absence to present = "cancel absence";
-- setLateAttendance / approve / reject). Those set is_overridden / is_approved /
-- is_manual, which the auto-status trigger below always respects.

-- (A) Auto status on check-in. Runs ONLY when an automatic path writes or
-- changes check_in_time; never overrides admin overrides/approvals/manual
-- entries, and never fires on unrelated status updates (e.g. "mark late").
CREATE OR REPLACE FUNCTION public.tr_compute_attendance_status()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.check_in_time IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.check_in_time IS DISTINCT FROM OLD.check_in_time)
     AND COALESCE(NEW.is_overridden, false) = false
     AND COALESCE(NEW.is_approved, false) = false
     AND COALESCE(NEW.is_manual, false) = false
  THEN
    IF (NEW.check_in_time AT TIME ZONE 'Africa/Cairo')::time >= TIME '15:00' THEN
      NEW.status := 'late';
    ELSE
      NEW.status := 'present';
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_attendance_compute_status ON public.attendance;
CREATE TRIGGER on_attendance_compute_status
  BEFORE INSERT OR UPDATE OF check_in_time ON public.attendance
  FOR EACH ROW EXECUTE FUNCTION public.tr_compute_attendance_status();

-- (B) Absent by default. Idempotent; gated to Cairo midnight so it stamps the
-- new day. A later check-in flips the row to present/late via trigger (A).
CREATE OR REPLACE FUNCTION public.mark_daily_absentees()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  cairo_now   timestamp := now() AT TIME ZONE 'Africa/Cairo';
  today_cairo date      := (now() AT TIME ZONE 'Africa/Cairo')::date;
  cnt integer := 0;
BEGIN
  IF EXTRACT(HOUR FROM cairo_now)::int <> 0 THEN RETURN 0; END IF;
  WITH ins AS (
    INSERT INTO public.attendance (employee_id, attendance_date, status)
    SELECT p.id, today_cairo, 'absent'
    FROM public.profiles p
    WHERE p.status = 'active' AND p.role IN ('employee', 'manager')
      AND NOT EXISTS (SELECT 1 FROM public.attendance a
        WHERE a.employee_id = p.id AND a.attendance_date = today_cairo)
    ON CONFLICT (employee_id, attendance_date) DO NOTHING
    RETURNING 1)
  SELECT count(*) INTO cnt FROM ins;
  RETURN cnt;
END; $$;

DO $$ BEGIN PERFORM cron.unschedule('attendance-mark-absentees'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('attendance-mark-absentees', '15 * * * *', $q$SELECT public.mark_daily_absentees();$q$);
