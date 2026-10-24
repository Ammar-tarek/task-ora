-- ============================================================================
-- PROPOSED (NOT APPLIED) — enforce attendee/department match at the DATABASE.
-- Today event_attendees RLS checks the EVENT belongs to the writer, but NOT
-- that the attendee (profile_id) is in the event's department. The Flutter form
-- now scopes the picker, but a direct Supabase call could still attach a
-- cross-department attendee. This trigger closes that gap for ALL write paths.
--
-- Rule: an attendee's profiles.team_id must equal the event's team_id.
--   * Blocks cross-department attendees (incl. via direct API).
--   * An event with team_id = NULL (legacy/unassigned) accepts NO new
--     attendees — it has no department to validate against.
-- Additive + reversible. No change to existing policies or data.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_event_attendee_department()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_event_team uuid;
  v_member_team uuid;
BEGIN
  SELECT team_id INTO v_event_team FROM public.events WHERE id = NEW.event_id;
  SELECT team_id INTO v_member_team FROM public.profiles WHERE id = NEW.profile_id;

  IF v_event_team IS NULL THEN
    RAISE EXCEPTION 'Event has no department; cannot add attendees.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_member_team IS DISTINCT FROM v_event_team THEN
    RAISE EXCEPTION 'Attendee is not a member of the event''s department.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_guard_event_attendee_department
  BEFORE INSERT ON public.event_attendees
  FOR EACH ROW EXECUTE FUNCTION public.guard_event_attendee_department();

-- Rollback:
--   DROP TRIGGER IF EXISTS trg_guard_event_attendee_department ON public.event_attendees;
--   DROP FUNCTION IF EXISTS public.guard_event_attendee_department();
