-- ============================================================================
-- Retire attendance automation — disable the three attendance pg_cron jobs.
--
-- The Attendance feature was removed from the app (UI + background service).
-- These scheduled jobs are the last app-independent automation still running:
--
--   1. attendance-mark-absentees   '15 * * * *'  SELECT public.mark_daily_absentees();
--      → inserts an 'absent' row into public.attendance for every active
--        employee/manager with no row (the ONLY automatic writer of attendance).
--   2. attendance-reminder-hourly  '0 * * * *'   SELECT public.send_attendance_reminders();
--      → inserts attendance_alert reminder notifications at 12 PM Cairo.
--   3. attendance-summary-hourly   '5 * * * *'   SELECT public.send_attendance_summaries();
--      → inserts attendance summary notifications to managers/admins.
--
-- This migration ONLY unschedules those three jobs. It is fully reversible and
-- DELIBERATELY NON-DESTRUCTIVE:
--   • It does NOT drop the backing functions (mark_daily_absentees,
--     send_attendance_reminders, send_attendance_summaries) — they stay, so a
--     rollback just re-schedules them.
--   • It does NOT touch the attendance / attendance_reminders tables, their
--     rows, RLS policies, triggers, or any reporting function/RPC.
--   • It does NOT touch the unrelated jobs 'event-reminders-5min' and
--     'event-reminders-cleanup-daily'.
--
-- Each unschedule is wrapped so a job that is already gone does not error,
-- making the migration safe to re-run.
-- ============================================================================

DO $$ BEGIN
  PERFORM cron.unschedule('attendance-mark-absentees');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  PERFORM cron.unschedule('attendance-reminder-hourly');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  PERFORM cron.unschedule('attendance-summary-hourly');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ============================================================================
-- ROLLBACK (run manually to fully restore the previous behaviour). The job
-- names, schedules, and commands below match the live registrations exactly:
--
--   SELECT cron.schedule('attendance-reminder-hourly', '0 * * * *',
--     $$SELECT public.send_attendance_reminders();$$);
--   SELECT cron.schedule('attendance-summary-hourly', '5 * * * *',
--     $$SELECT public.send_attendance_summaries();$$);
--   SELECT cron.schedule('attendance-mark-absentees', '15 * * * *',
--     $$SELECT public.mark_daily_absentees();$$);
-- ============================================================================
