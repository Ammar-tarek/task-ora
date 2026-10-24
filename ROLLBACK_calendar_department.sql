-- ============================================================================
-- ROLLBACK for PROPOSED_calendar_department.sql (REVISED). Reverses every change
-- and restores the two original event policies verbatim.
--
-- DATA-LOSS NOTES (rollback is NOT fully lossless):
--   * Dropping events.team_id discards ALL department assignments — both the
--     22 backfilled values and any team_id set on events created AFTER the
--     migration. The calendar's department grouping is lost on rollback.
--   * Dropping event_reminders discards ALL reminder rows created after the
--     migration (delivery history). There is no way to preserve them once the
--     table is gone.
--   If you need to keep that data, export events.team_id and event_reminders
--   BEFORE running this rollback. The steps below are otherwise reversible and
--   do not touch pre-existing event rows, attendees, or other objects.
-- ============================================================================

BEGIN;

-- 7) reminders (drops post-migration reminder rows — see note above)
DROP TABLE IF EXISTS public.event_reminders;

-- 6) restore the original event policies, drop the three new ones
DROP POLICY IF EXISTS "events_department_manage" ON public.events;
DROP POLICY IF EXISTS "events_department_read" ON public.events;
DROP POLICY IF EXISTS "events_participant_read" ON public.events;

CREATE POLICY "Employee sees attendee or own events" ON public.events
  FOR SELECT
  USING (
    (public.get_my_role() = 'employee'::public.user_role)
    AND (
      (created_by = auth.uid())
      OR (id IN (SELECT event_attendees.event_id FROM public.event_attendees
                 WHERE event_attendees.profile_id = auth.uid()))
    )
  );

CREATE POLICY "manager_team_events" ON public.events
  FOR ALL
  USING (
    public.is_manager() AND (
      (client_id IN (SELECT id FROM public.manager_client_ids()))
      OR (created_by IN (SELECT id FROM public.manager_member_ids()))
    )
  )
  WITH CHECK (
    public.is_manager() AND (
      (client_id IN (SELECT id FROM public.manager_client_ids()))
      OR (created_by IN (SELECT id FROM public.manager_member_ids()))
    )
  );

-- 5) + 4) constraints
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_studio_booking_no_overlap;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_room_booking_time_valid;

-- 2) column + index (drops all department assignments — see note above)
DROP INDEX IF EXISTS public.events_team_id_idx;
ALTER TABLE public.events DROP COLUMN IF EXISTS team_id;

-- 1) Studio team — removed only if nothing references it
DELETE FROM public.teams t
WHERE t.id = 'd5705700-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.team_id = t.id)
  AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.team_id = t.id);

COMMIT;
