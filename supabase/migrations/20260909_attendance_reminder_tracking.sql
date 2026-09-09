-- ============================================================================
-- Attendance reminder TRACKING + daily summary.
--
-- Builds on 20260909_attendance_reminder_cron.sql. Reuses the existing
-- notifications -> FCM -> Realtime pipeline unchanged. Adds:
--   1. attendance_reminders  — one row per employee per day a reminder is sent.
--   2. Reminder job records those rows idempotently (unique employee/day).
--   3. Trigger on public.attendance links the real check-in back to the row.
--   4. 12:05 PM Cairo summary job (managers: own team, admins: company-wide).
--   5. SECURITY DEFINER RPC get_reminder_tracking() for the in-app screen,
--      enforcing team scoping server-side (managers cannot read other teams).
--
-- Timezone: business tz = Africa/Cairo, applied via `AT TIME ZONE` in one
-- place per concern (never a hard-coded numeric offset).
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Tracking table
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attendance_reminders (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id               uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reminder_date             date NOT NULL,
  -- When the reminder was SENT through the pipeline. FCM confirms send only,
  -- not delivery/open, so there is deliberately no `delivered_at` column.
  sent_at                   timestamptz NOT NULL DEFAULT now(),
  -- Filled by the attendance trigger when the employee checks in that day.
  checked_in_at             timestamptz,
  checked_in_after_reminder boolean NOT NULL DEFAULT false,
  created_at                timestamptz NOT NULL DEFAULT now(),
  -- One reminder per employee per day — makes the reminder job idempotent.
  CONSTRAINT attendance_reminders_emp_date_uk UNIQUE (employee_id, reminder_date)
);

CREATE INDEX IF NOT EXISTS attendance_reminders_date_idx
  ON public.attendance_reminders (reminder_date);
CREATE INDEX IF NOT EXISTS attendance_reminders_emp_idx
  ON public.attendance_reminders (employee_id);

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Reminder job — now records tracking rows AND notifies only NEW rows,
--    so a second cron run in the same hour never double-pushes.
-- ─────────────────────────────────────────────────────────────────────────
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
  -- Only fire at 12:00 PM Cairo (1 hour after the 11 AM official time).
  IF EXTRACT(HOUR FROM cairo_now)::int <> 12 THEN
    RETURN;
  END IF;

  -- Insert a tracking row for every active non-admin employee who has NOT
  -- checked in today. ON CONFLICT DO NOTHING makes retries idempotent, and
  -- RETURNING yields ONLY the rows actually created this run.
  WITH new_reminders AS (
    INSERT INTO public.attendance_reminders (employee_id, reminder_date, sent_at)
    SELECT p.id, today_cairo, now()
    FROM public.profiles p
    WHERE p.status = 'active'
      AND p.role NOT IN ('admin', 'client')      -- excludes super_admin (role='admin') + clients
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.employee_id = p.id
          AND a.attendance_date = today_cairo
          AND a.check_in_time IS NOT NULL
      )
    ON CONFLICT (employee_id, reminder_date) DO NOTHING
    RETURNING employee_id
  )
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT
    nr.employee_id, 'attendance_alert', 'Attendance reminder',
    'You have not checked in yet. The official attendance time was 11:00 AM — please check in now.',
    'attendance_reminder', NULL, false, 'in_app'
  FROM new_reminders nr;

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Attendance reminders sent: %', inserted;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. Link the real check-in back to today's reminder row.
--    Fires whenever check_in_time is written on public.attendance.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tr_link_checkin_to_reminder()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.check_in_time IS NOT NULL THEN
    UPDATE public.attendance_reminders r
    SET checked_in_at             = NEW.check_in_time,
        checked_in_after_reminder = (NEW.check_in_time > r.sent_at)
    WHERE r.employee_id = NEW.employee_id
      AND r.reminder_date = NEW.attendance_date;   -- never touches sent_at
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_attendance_checkin_link_reminder ON public.attendance;
CREATE TRIGGER on_attendance_checkin_link_reminder
  AFTER INSERT OR UPDATE OF check_in_time ON public.attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_link_checkin_to_reminder();

-- ─────────────────────────────────────────────────────────────────────────
-- 4. Daily summary — one notification per manager (own team) / admin (all).
--    Reuses the notifications -> FCM pipeline; type reuses 'attendance_alert'
--    (HR channel), distinguished by reference_type = 'attendance_summary'.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_attendance_summaries()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  cairo_now   timestamp := now() AT TIME ZONE 'Africa/Cairo';
  today_cairo date      := (now() AT TIME ZONE 'Africa/Cairo')::date;
BEGIN
  IF EXTRACT(HOUR FROM cairo_now)::int <> 12 THEN
    RETURN;
  END IF;

  -- Active staff (employees + managers) who have not checked in today.
  CREATE TEMP TABLE _absentees ON COMMIT DROP AS
  SELECT p.id, p.full_name, p.team_id
  FROM public.profiles p
  WHERE p.status = 'active'
    AND p.role IN ('employee', 'manager')
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a
      WHERE a.employee_id = p.id
        AND a.attendance_date = today_cairo
        AND a.check_in_time IS NOT NULL
    );

  -- 4a. Admins / super admins: company-wide summary (one row each).
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT
    adm.id, 'attendance_alert', 'Attendance summary',
    s.cnt || ' employees have not checked in today: ' || s.names,
    'attendance_summary', NULL, false, 'in_app'
  FROM (SELECT id FROM public.profiles
        WHERE status = 'active' AND role = 'admin') adm
  CROSS JOIN (SELECT count(*) cnt,
                     string_agg(full_name, ', ' ORDER BY full_name) names
              FROM _absentees) s
  WHERE s.cnt > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = adm.id
        AND n.reference_type = 'attendance_summary'
        AND (n.created_at AT TIME ZONE 'Africa/Cairo')::date = today_cairo
    );

  -- 4b. Managers: only their own team's absentees (one row each).
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT
    m.id, 'attendance_alert', 'Attendance summary',
    s.cnt || ' employees have not checked in today: ' || s.names,
    'attendance_summary', NULL, false, 'in_app'
  FROM public.profiles m
  JOIN LATERAL (
    SELECT count(*) cnt, string_agg(a.full_name, ', ' ORDER BY a.full_name) names
    FROM _absentees a
    WHERE a.team_id = m.team_id
  ) s ON true
  WHERE m.status = 'active' AND m.role = 'manager' AND m.team_id IS NOT NULL
    AND s.cnt > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = m.id
        AND n.reference_type = 'attendance_summary'
        AND (n.created_at AT TIME ZONE 'Africa/Cairo')::date = today_cairo
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. In-app tracking RPC — team scoping enforced here (server-side).
--    admin/super_admin: all (optional p_team_id filter).
--    manager: their own team only (p_team_id ignored).
--    others: only themselves.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_reminder_tracking(
  p_date    date DEFAULT (now() AT TIME ZONE 'Africa/Cairo')::date,
  p_team_id uuid DEFAULT NULL
)
RETURNS TABLE (
  employee_id                uuid,
  full_name                  text,
  team_id                    uuid,
  team_name                  text,
  reminder_sent_at           timestamptz,
  checked_in_at              timestamptz,
  checked_in_after_reminder  boolean,
  attendance_check_in_time   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id   uuid := auth.uid();
  caller_role text;
  caller_team uuid;
BEGIN
  IF caller_id IS NULL THEN
    RETURN;   -- no session, no rows
  END IF;

  SELECT role, profiles.team_id INTO caller_role, caller_team
  FROM public.profiles WHERE id = caller_id;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.team_id,
    t.name,
    r.sent_at,
    r.checked_in_at,
    COALESCE(r.checked_in_after_reminder, false),
    a.check_in_time
  FROM public.profiles p
  LEFT JOIN public.teams t ON t.id = p.team_id
  LEFT JOIN public.attendance_reminders r
    ON r.employee_id = p.id AND r.reminder_date = p_date
  LEFT JOIN public.attendance a
    ON a.employee_id = p.id AND a.attendance_date = p_date
  WHERE p.status = 'active'
    AND p.role IN ('employee', 'manager')
    AND (
      -- Admins see everyone, optionally narrowed to one team.
      (caller_role = 'admin'
        AND (p_team_id IS NULL OR p.team_id = p_team_id))
      -- Managers see ONLY their own team, regardless of client input.
      OR (caller_role = 'manager' AND caller_team IS NOT NULL
        AND p.team_id = caller_team)
      -- Everyone else sees only themselves.
      OR (caller_role NOT IN ('admin', 'manager')
        AND p.id = caller_id)
    )
  ORDER BY p.full_name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_reminder_tracking(date, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_reminder_tracking(date, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6. RLS on the tracking table (defense in depth for direct table access;
--    the RPC above is SECURITY DEFINER and is the intended read path).
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.attendance_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS attendance_reminders_read ON public.attendance_reminders;
CREATE POLICY attendance_reminders_read ON public.attendance_reminders
  FOR SELECT TO authenticated
  USING (
    -- self
    employee_id = auth.uid()
    -- admins
    OR EXISTS (SELECT 1 FROM public.profiles me
               WHERE me.id = auth.uid() AND me.role = 'admin')
    -- manager of the same team as the reminded employee
    OR EXISTS (
      SELECT 1
      FROM public.profiles me
      JOIN public.profiles emp ON emp.id = attendance_reminders.employee_id
      WHERE me.id = auth.uid() AND me.role = 'manager'
        AND me.team_id IS NOT NULL AND me.team_id = emp.team_id
    )
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 7. Summary cron — runs at minute 5; function self-gates to 12 PM Cairo,
--    so it effectively fires at 12:05 PM Cairo, just after reminders.
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM cron.unschedule('attendance-summary-hourly');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'attendance-summary-hourly',
  '5 * * * *',
  $q$SELECT public.send_attendance_summaries();$q$
);

-- ─────────────────────────────────────────────────────────────────────────
-- 8. Live updates for the in-app tracking screen.
-- ─────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_reminders;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
