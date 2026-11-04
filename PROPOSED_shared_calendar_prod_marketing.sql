-- ============================================================================
-- EDIT 3 — Connect the Video Production + Marketing calendars.
-- ============================================================================
-- Goal: an event owned by Video Production is SEEN by Marketing and vice versa,
-- and both teams get the SAME create + reminder notifications. Editing stays
-- OWNER-TEAM ONLY (a Marketing manager cannot edit a Video Production event):
-- that is why we add only a SELECT policy, not a manage policy.
--
-- Implementation is DB-only (no Flutter change): calendar visibility for
-- non-admins is driven by RLS, and every notification path
-- (notify_event_created, send_event_reminders, send_event_start_reminders)
-- already funnels through event_recipient_ids().
--
-- Apply in the Supabase SQL editor. Idempotent / safe to re-run.
-- ============================================================================

-- 1. A small group table (so more teams can be linked later without code) ------
CREATE TABLE IF NOT EXISTS public.calendar_team_groups (
  group_key text NOT NULL,
  team_id   uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  PRIMARY KEY (group_key, team_id)
);
ALTER TABLE public.calendar_team_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS calendar_team_groups_read ON public.calendar_team_groups;
CREATE POLICY calendar_team_groups_read ON public.calendar_team_groups
  FOR SELECT TO authenticated USING (true);

-- Seed: Video Production + Marketing share one calendar group.
INSERT INTO public.calendar_team_groups (group_key, team_id) VALUES
  ('prod_mktg', '794f294c-77cc-4845-b8ba-b5fa9198fd55'),  -- Video Production
  ('prod_mktg', 'f398bbb2-f5c2-4a1c-852e-745c911c1264')   -- Marketing
ON CONFLICT DO NOTHING;

-- 2. Helper: all teams that share a group with p_team (incl. p_team itself) ----
CREATE OR REPLACE FUNCTION public.calendar_group_team_ids(p_team uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT g2.team_id
  FROM public.calendar_team_groups g1
  JOIN public.calendar_team_groups g2 ON g2.group_key = g1.group_key
  WHERE g1.team_id = p_team
  UNION
  SELECT p_team WHERE p_team IS NOT NULL;
$function$;

-- 3. Notifications/reminders fan out to the WHOLE group ------------------------
-- (only the two team branches change: = p_team  ->  IN (group of p_team))
CREATE OR REPLACE FUNCTION public.event_recipient_ids(p_team uuid, p_creator uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT id FROM (
    SELECT p_creator AS id WHERE p_creator IS NOT NULL
    UNION
    SELECT id FROM public.profiles WHERE role = 'admin' OR is_super_admin = true
    UNION
    SELECT id FROM public.profiles
      WHERE role = 'manager'  AND p_team IS NOT NULL
        AND team_id IN (SELECT public.calendar_group_team_ids(p_team))
    UNION
    SELECT id FROM public.profiles
      WHERE role = 'employee' AND status = 'active' AND p_team IS NOT NULL
        AND team_id IN (SELECT public.calendar_group_team_ids(p_team))
  ) x;
$function$;

-- 4. Visibility: let a grouped team READ the other grouped team's events -------
-- Additive (OR) with the existing per-team read policies. Managers/employees of
-- either team now see both teams' events. Edit/delete stays owner-team only via
-- the untouched events_department_manage policy.
DROP POLICY IF EXISTS events_calendar_group_read ON public.events;
CREATE POLICY events_calendar_group_read ON public.events
  FOR SELECT TO authenticated
  USING (
    get_my_role() <> 'client'::user_role
    AND team_id IS NOT NULL
    AND team_id IN (SELECT public.calendar_group_team_ids(public.my_team_id()))
  );
