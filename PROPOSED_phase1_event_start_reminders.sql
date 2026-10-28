-- ============================================================================
-- PROPOSED (NOT APPLIED) — Phase 1: configurable event START-time reminders.
-- Separate from the existing END-time reminder system (send_event_reminders +
-- event_reminders + cron event-reminders-5min), which is left UNCHANGED.
--
-- Offsets before start: 0 (at time), 5, 10, 15, 30, 60, 1440 (1 day).
-- Delivery reuses the existing notifications → FCM pipeline and department
-- recipient policy (event_recipient_ids). Timezone-safe: start_time is
-- timestamptz, offsets are intervals, comparisons use now() (UTC).
-- ============================================================================

-- 1) Per-event chosen offsets (the "Set reminders" config on an event). --------
CREATE TABLE IF NOT EXISTS public.event_start_reminder_offsets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  offset_minutes int NOT NULL CHECK (offset_minutes IN (0, 5, 10, 15, 30, 60, 1440)),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, offset_minutes)
);
CREATE INDEX IF NOT EXISTS event_start_reminder_offsets_event_idx
  ON public.event_start_reminder_offsets(event_id);

-- 2) Delivery log — one row per (event, recipient, offset) actually sent. ------
--    The UNIQUE key makes scheduler retries idempotent (no double send).
CREATE TABLE IF NOT EXISTS public.event_start_reminder_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  offset_minutes int NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, profile_id, offset_minutes)
);
CREATE INDEX IF NOT EXISTS event_start_reminder_log_event_idx
  ON public.event_start_reminder_log(event_id);

-- 3) Sender — runs every minute. Fires each configured offset once per
--    recipient when now() has reached (start_time - offset) and start is still
--    in the future. Recipients + authorization reuse event_recipient_ids, so no
--    event detail reaches anyone outside the department policy. ----------------
CREATE OR REPLACE FUNCTION public.send_event_start_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE inserted integer;
BEGIN
  WITH due AS (
    SELECT e.id AS event_id, r AS profile_id, o.offset_minutes,
           e.title, e.start_time
    FROM public.events e
    JOIN public.event_start_reminder_offsets o ON o.event_id = e.id
    CROSS JOIN LATERAL public.event_recipient_ids(e.team_id, e.created_by) AS r
    WHERE e.team_id IS NOT NULL
      AND e.status NOT IN ('cancelled','cancelled_by_client','cancelled_by_us','done','completed')
      -- Due once the lead time is reached, up to 1 minute past start (so the
      -- "at event time" offset of 0 fires in the minute of start). Dedup below
      -- guarantees a single send.
      AND (e.start_time - make_interval(mins => o.offset_minutes)) <= now()
      AND now() < e.start_time + interval '1 minute'
  ),
  recorded AS (
    INSERT INTO public.event_start_reminder_log (event_id, profile_id, offset_minutes, sent_at)
    SELECT event_id, profile_id, offset_minutes, now() FROM due
    ON CONFLICT (event_id, profile_id, offset_minutes) DO NOTHING
    RETURNING event_id, profile_id, offset_minutes
  )
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read)
  SELECT r.profile_id, 'meeting_reminder',
    CASE
      WHEN d.offset_minutes = 0    THEN 'Event Starting Now: '
      WHEN d.offset_minutes = 1440 THEN 'Event Tomorrow: '
      WHEN d.offset_minutes = 60   THEN 'Event in 1 Hour: '
      ELSE 'Event in ' || d.offset_minutes || ' Minutes: '
    END || COALESCE(d.title,'event'),
    'Starts ' || to_char(d.start_time AT TIME ZONE 'Africa/Cairo','YYYY-MM-DD HH24:MI'),
    'event', r.event_id, false
  FROM recorded r JOIN due d USING (event_id, profile_id, offset_minutes);
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Event start-time reminders sent: %', inserted;
END;
$$;

-- 4) Reschedule safety — if an event's start_time moves, drop its delivery log
--    so reminders re-evaluate against the NEW time (obsolete ones never fire).
--    Deletes are handled by ON DELETE CASCADE above.
CREATE OR REPLACE FUNCTION public.tg_event_start_reset_reminders()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.start_time IS DISTINCT FROM OLD.start_time THEN
    DELETE FROM public.event_start_reminder_log WHERE event_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_event_start_reset_reminders
  AFTER UPDATE OF start_time ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.tg_event_start_reset_reminders();

-- 5) Cron — reuse the minute cadence, separate job from the end-time one. ------
SELECT cron.schedule(
  'event-start-reminders-1min', '* * * * *',
  $cron$ SELECT public.send_event_start_reminders(); $cron$
);

-- 6) RLS ----------------------------------------------------------------------
ALTER TABLE public.event_start_reminder_offsets ENABLE ROW LEVEL SECURITY;

-- Admin: full. Manager: manage offsets for events in their department. Anyone
-- authenticated may READ offsets (they are just minute values, no event detail).
CREATE POLICY "start_offsets_admin" ON public.event_start_reminder_offsets
  FOR ALL USING (public.is_global_admin()) WITH CHECK (public.is_global_admin());

CREATE POLICY "start_offsets_manager" ON public.event_start_reminder_offsets
  FOR ALL
  USING (public.is_manager() AND event_id IN (SELECT id FROM public.manager_event_ids()))
  WITH CHECK (public.is_manager() AND event_id IN (SELECT id FROM public.manager_event_ids()));

CREATE POLICY "start_offsets_read" ON public.event_start_reminder_offsets
  FOR SELECT USING (auth.uid() IS NOT NULL);

ALTER TABLE public.event_start_reminder_log ENABLE ROW LEVEL SECURITY;

-- Delivery log is written only by the SECURITY DEFINER sender. Users may read
-- their own rows; admins read all. No client writes.
CREATE POLICY "start_log_read_own" ON public.event_start_reminder_log
  FOR SELECT USING (profile_id = auth.uid() OR public.is_global_admin());

REVOKE INSERT, UPDATE, DELETE ON public.event_start_reminder_offsets FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.event_start_reminder_log FROM anon, authenticated;

-- 7) ATOMIC replace RPC. The app calls THIS instead of a client-side
--    delete-then-insert, so the two writes commit (or roll back) together — a
--    failed insert can never leave the user with their reminders wiped.
--    Authorization is enforced IN the function (admin, or manager of the
--    event's department); SECURITY DEFINER does not bypass user authz here, and
--    no service-role client is involved. An empty [] intentionally clears all.
CREATE OR REPLACE FUNCTION public.set_event_start_reminders(
  p_event_id uuid,
  p_offsets  int[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Only an admin, or the manager of the event's department, may set reminders.
  IF NOT (
    public.is_global_admin()
    OR (public.is_manager()
        AND p_event_id IN (SELECT id FROM public.manager_event_ids()))
  ) THEN
    RAISE EXCEPTION 'Not authorized to set reminders for this event.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Reject unsupported offsets (defends the direct-API path too).
  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_offsets, ARRAY[]::int[])) o
    WHERE o NOT IN (0, 5, 10, 15, 30, 60, 1440)
  ) THEN
    RAISE EXCEPTION 'Invalid reminder offset.' USING ERRCODE = 'check_violation';
  END IF;

  -- Atomic replace: both statements are in this one function transaction.
  DELETE FROM public.event_start_reminder_offsets WHERE event_id = p_event_id;

  INSERT INTO public.event_start_reminder_offsets (event_id, offset_minutes)
  SELECT DISTINCT p_event_id, o
  FROM unnest(COALESCE(p_offsets, ARRAY[]::int[])) o;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_event_start_reminders(uuid, int[]) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_event_start_reminders(uuid, int[]) TO authenticated;

-- ── Rollback ────────────────────────────────────────────────────────────────
--   DROP FUNCTION IF EXISTS public.set_event_start_reminders(uuid, int[]);
--   SELECT cron.unschedule('event-start-reminders-1min');
--   DROP TRIGGER IF EXISTS trg_event_start_reset_reminders ON public.events;
--   DROP FUNCTION IF EXISTS public.tg_event_start_reset_reminders();
--   DROP FUNCTION IF EXISTS public.send_event_start_reminders();
--   DROP TABLE IF EXISTS public.event_start_reminder_log;
--   DROP TABLE IF EXISTS public.event_start_reminder_offsets;
