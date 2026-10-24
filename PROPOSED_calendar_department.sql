-- ============================================================================
-- PROPOSED (NOT APPLIED) — Department-based shared calendar. REVISED after review.
-- Additive + reversible (see ROLLBACK_calendar_department.sql).
-- Five departments only: Marketing, Montage, Production, Sales, Studio.
-- Expenses has NO calendar and is never referenced here.
--
-- Review corrections in this revision:
--   * event_type enum has NO 'booking' value → Studio bookings use 'room_booking'.
--   * Booking-overlap exclusion is scoped to the STUDIO team only (fixed id),
--     not every department.
--   * The 22 events with cross-department attendees keep their access via a
--     participant read policy, so replacing the old policies does not strip
--     existing per-participant visibility.
-- ============================================================================

BEGIN;

-- 1) Studio department team — idempotent, with a FIXED id so the Studio-only
--    booking constraint below can reference it deterministically. ------------
INSERT INTO public.teams (id, name, department, is_active)
SELECT 'd5705700-0000-4000-8000-000000000001', 'Studio', 'Studio', true
WHERE NOT EXISTS (
  SELECT 1 FROM public.teams
  WHERE name = 'Studio' OR department = 'Studio'
     OR id = 'd5705700-0000-4000-8000-000000000001'
);

-- 2) events.team_id = the department that OWNS the event. ---------------------
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS team_id uuid REFERENCES public.teams(id);
CREATE INDEX IF NOT EXISTS events_team_id_idx ON public.events(team_id);

-- 3) SAFE backfill — only when the department is determinable RELIABLY.
--    Rule: the creator belongs to a real DEPARTMENT team (not Admins, not NULL).
--    Ambiguous events (admin/no-dept creator) are LEFT NULL for manual review
--    and are NOT browsable in any department calendar (NULL != my_team_id()).
--    Measured on current data: 22 of 29 backfilled, 7 left NULL.
UPDATE public.events e
SET team_id = p.team_id
FROM public.profiles p, public.teams t
WHERE e.created_by = p.id
  AND p.team_id = t.id
  AND e.team_id IS NULL
  AND t.is_active
  AND t.name <> 'Admins'
  AND (t.department IS NOT NULL OR t.name IN ('Sales', 'Studio'));

-- 4) Validate Studio booking ranges. NOT VALID → legacy rows never rejected. --
ALTER TABLE public.events
  ADD CONSTRAINT events_room_booking_time_valid
  CHECK (
    event_type <> 'room_booking'
    OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
  ) NOT VALID;

-- 5) STUDIO-ONLY booking conflict prevention (DB-level, concurrency-safe).
--    Two overlapping Studio room_booking events cannot both commit. Scoped to
--    the Studio team id only — other departments' bookings are unaffected.
--    Surfaced to the app as SQLSTATE 23P01 → "time slot already booked".
--    (0 existing room_booking rows, so this applies cleanly.)
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE public.events
  ADD CONSTRAINT events_studio_booking_no_overlap
  EXCLUDE USING gist (tstzrange(start_time, end_time) WITH &&)
  WHERE (
    event_type = 'room_booking'
    -- A booking in any cancelled state RELEASES its slot (verified enum values:
    -- cancelled, cancelled_by_client, cancelled_by_us).
    AND status NOT IN ('cancelled', 'cancelled_by_client', 'cancelled_by_us')
    AND team_id = 'd5705700-0000-4000-8000-000000000001'
  );

-- 6) RLS — department isolation, preserving per-participant visibility. -------
-- Keep "Admin full on events" and "Client sees own visible events" unchanged.
-- Replace the client/creator-centric employee + manager policies.
DROP POLICY IF EXISTS "Employee sees attendee or own events" ON public.events;
DROP POLICY IF EXISTS "manager_team_events" ON public.events;

-- (a) Manager: full control of THEIR department's events only. WITH CHECK
--     blocks creating OR moving an event into another department.
CREATE POLICY "events_department_manage" ON public.events
  FOR ALL
  USING (public.is_manager() AND team_id = public.my_team_id())
  WITH CHECK (public.is_manager() AND team_id = public.my_team_id());

-- (b) Employee: read-only shared view of THEIR department's calendar.
--     NULL-team (unassigned) events never match → hidden from department browse.
CREATE POLICY "events_department_read" ON public.events
  FOR SELECT
  USING (public.get_my_role() = 'employee' AND team_id = public.my_team_id());

-- (c) Participant read (preserves the ORIGINAL per-user visibility for the 22
--     cross-department attendee events). SELECT only — grants no writes, and is
--     personal access (creator/attendee), independent of department browsing.
--     Hardening: excludes clients, so a client added as an attendee cannot
--     bypass "Client sees own visible events" (is_client_visible). Clients keep
--     their access solely through that policy; staff keep cross-department
--     access to events they created or are attendees of.
CREATE POLICY "events_participant_read" ON public.events
  FOR SELECT
  USING (
    public.get_my_role() <> 'client'
    AND (
      created_by = auth.uid()
      OR id IN (SELECT ea.event_id FROM public.event_attendees ea
                WHERE ea.profile_id = auth.uid())
    )
  );

-- 7) event_reminders — reminder delivery tracking + dedup. --------------------
CREATE TABLE IF NOT EXISTS public.event_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  offset_minutes int NOT NULL CHECK (offset_minutes IN (15, 60)),
  sent_at timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE (event_id, profile_id, offset_minutes) -- dedup: one row per reminder
);
CREATE INDEX IF NOT EXISTS event_reminders_pending_idx
  ON public.event_reminders(event_id) WHERE sent_at IS NULL;

ALTER TABLE public.event_reminders ENABLE ROW LEVEL SECURITY;

-- Ordinary users may READ only their own reminder rows and may NOT insert or
-- mark them sent — writes are server-side only (cron / SECURITY DEFINER RPC,
-- implemented separately). No insert/update/delete policy is defined, and the
-- table-level grants are revoked, so the client cannot forge reminders.
CREATE POLICY "event_reminders_read_own" ON public.event_reminders
  FOR SELECT USING (profile_id = auth.uid());

REVOKE INSERT, UPDATE, DELETE ON public.event_reminders FROM anon, authenticated;

COMMIT;
