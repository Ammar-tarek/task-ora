-- ============================================================================
-- PROPOSED (NOT APPLIED) — Calendar event reminders + department-scoped
-- create/update/cancel notifications.  (Revised after review.)
--
-- Builds entirely on the EXISTING pipeline (verified against the live DB):
--   notifications INSERT
--     -> trigger notifications_fcm_push -> Edge Function send-fcm-notification
--        (looks up the recipient's profiles.fcm_token and pushes; recipient-
--         based, so no extra visibility logic is needed here)
--     -> Supabase Realtime -> in-app / local notification
-- The Flutter app renders every notification type, so NO app change is required
-- for reminders to appear. No service-role key touches the client.
--
-- Mirrors the proven attendance-reminder pattern
-- (supabase/migrations/20260909_attendance_reminder_cron.sql): SECURITY DEFINER
-- functions owned by postgres, scheduled with pg_cron, inserting into
-- notifications. Reuses the existing `event_reminders` table + its
-- UNIQUE (event_id, profile_id, offset_minutes) constraint for dedup and the
-- existing `meeting_reminder` / `calendar_event` enum values.
--
-- Departments: Marketing, Montage, Production (Video Production team), Sales,
-- Studio. Reminders/notifications are scoped to the event's owning department
-- (events.team_id) and the people actually involved — never company-wide,
-- never another department. The 7 unassigned legacy events (team_id IS NULL)
-- are skipped by the reminder sender and notify admins only on create.
--
-- ─ CO-DEPLOYMENT (IMPORTANT) ────────────────────────────────────────────────
-- §4 and §5 replace the client-side notifications that Flutter used to send.
-- The matching Flutter edits are ALREADY in this changeset
-- (lib/core/repositories/client_repository.dart — the notifyAction calls in
-- createEvent and updateEventStatus were removed). This SQL and that app build
-- MUST be deployed together: shipping the app without this SQL means managers
-- are not notified on create and nobody is notified on status change; applying
-- this SQL without removing the app calls causes double-sends.
--
-- ─ TIMING TOLERANCE ─────────────────────────────────────────────────────────
-- The cron runs every 5 minutes, so reminders can be delivered UP TO 5 MINUTES
-- EARLY: the 60-minute reminder fires in the (55, 60] window before start and
-- the 15-minute reminder in (10, 15]. Each offset is sent exactly once (unique
-- constraint). To avoid two reminders at once for a last-minute event, the
-- 60-minute reminder is suppressed when the event is already within 15 minutes.
-- ============================================================================

BEGIN;

-- 1) REMINDER SENDER -----------------------------------------------------------
-- For each upcoming department event, each attendee, and each offset (60, 15),
-- atomically RECORD the reminder (dedup via the unique constraint) and — only
-- for newly recorded rows — INSERT the notification. The record+notify is a
-- single statement (CTE), so it is atomic: a failed notify rolls back the
-- record and it retries next run. (The FCM push itself is best-effort async
-- pg_net, as for every other notification in this app.) Re-validates status and
-- time on every run, so a cancelled or rescheduled event never sends an
-- obsolete reminder (defence in depth alongside the reset trigger in §3).
CREATE OR REPLACE FUNCTION public.send_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  inserted integer;
BEGIN
  WITH due AS (
    SELECT e.id          AS event_id,
           ea.profile_id AS profile_id,
           o.offset_minutes,
           e.title,
           e.start_time
    FROM public.events e
    JOIN public.event_attendees ea ON ea.event_id = e.id
    CROSS JOIN (VALUES (60), (15)) AS o(offset_minutes)
    WHERE e.team_id IS NOT NULL                    -- department-owned only
      AND e.status NOT IN (
            'cancelled', 'cancelled_by_client', 'cancelled_by_us',
            'done', 'completed'
          )
      AND e.start_time > now()                     -- not already started
      AND e.start_time <= now() + make_interval(mins => o.offset_minutes)
      -- Suppress the 60-min reminder once the event is within 15 minutes, so a
      -- last-minute event does not fire both offsets at the same moment.
      AND (o.offset_minutes <> 60
           OR e.start_time > now() + interval '15 minutes')
  ),
  recorded AS (
    INSERT INTO public.event_reminders
      (event_id, profile_id, offset_minutes, sent_at)
    SELECT event_id, profile_id, offset_minutes, now()
    FROM due
    ON CONFLICT (event_id, profile_id, offset_minutes) DO NOTHING
    RETURNING event_id, profile_id, offset_minutes
  )
  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT r.profile_id,
         'meeting_reminder',
         'Event reminder',
         'Reminder: "' || COALESCE(d.title, 'an event')
           || '" starts in ' || r.offset_minutes || ' minutes.',
         'event',
         r.event_id,
         false,
         'in_app'
  FROM recorded r
  JOIN due d USING (event_id, profile_id, offset_minutes);

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RAISE NOTICE 'Event reminders sent: %', inserted;
END;
$$;

-- Least privilege: only the postgres owner (and the cron job, which runs as
-- postgres) may invoke the sender. Owners always retain EXECUTE, so revoking
-- PUBLIC/anon/authenticated does not break the scheduled call.
REVOKE EXECUTE ON FUNCTION public.send_event_reminders() FROM PUBLIC, anon, authenticated;

-- 2) SCHEDULE — every 5 minutes (see TIMING TOLERANCE above). timestamptz vs
--    now() is timezone-correct, so no DST gating is needed. Idempotent.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  PERFORM cron.unschedule('event-reminders-5min');
EXCEPTION WHEN OTHERS THEN
  NULL; -- not scheduled yet
END
$$;

SELECT cron.schedule(
  'event-reminders-5min',
  '*/5 * * * *',
  $$SELECT public.send_event_reminders();$$
);

-- 3) OBSOLETE-REMINDER RESET — when an event's start_time changes or it is
--    cancelled, drop its recorded reminders. A reschedule then re-reminds for
--    the new time; a cancellation leaves no rows and the sender's status filter
--    prevents any re-creation. (ON DELETE CASCADE already removes reminders when
--    the event itself is deleted.)
CREATE OR REPLACE FUNCTION public.tg_event_reset_reminders()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.start_time IS DISTINCT FROM OLD.start_time)
     OR (NEW.status IN ('cancelled', 'cancelled_by_client', 'cancelled_by_us')
         AND OLD.status NOT IN ('cancelled', 'cancelled_by_client', 'cancelled_by_us'))
  THEN
    DELETE FROM public.event_reminders WHERE event_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tg_event_reset_reminders() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_event_reset_reminders ON public.events;
CREATE TRIGGER trg_event_reset_reminders
  AFTER UPDATE OF start_time, status ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_event_reset_reminders();

-- 4) DEPARTMENT-SCOPED "event created" NOTIFICATION ---------------------------
-- Replaces the current admins-only notify_event_created. Now fans out to the
-- OWNING department (its managers) + all admins, excluding the creator, via the
-- existing notify_fanout RPC. Attendees continue to be notified by the existing
-- trg_notify_event_attendee trigger. Other departments are never notified.
-- Unassigned events (team_id IS NULL) notify admins only (no department).
--
-- DUPLICATE-RECIPIENT AUDIT (verified against the live function body):
-- notify_fanout emits exactly ONE row per recipient — it SELECTs DISTINCT over
-- (p_primary ∪ admins ∪ owning-dept managers) and excludes p_exclude. It does
-- NOT include attendees, so it cannot overlap with trg_notify_event_attendee.
-- A person who is both an admin/manager AND an attendee therefore receives one
-- "New event created" row here plus the distinct "You were added to an event"
-- row from the attendee trigger — two different messages, never a duplicate of
-- the same event-created notification. Each intended recipient gets exactly one
-- event-created notification.
CREATE OR REPLACE FUNCTION public.notify_event_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE creator_name text;
BEGIN
  SELECT full_name INTO creator_name FROM public.profiles WHERE id = NEW.created_by;
  PERFORM public.notify_fanout(
    NEW.team_id,                       -- owning department (its managers)
    'calendar_event',
    'New event created',
    COALESCE(creator_name, 'Someone') || ' created "' || NEW.title || '".',
    'event',
    NEW.id,
    NULL,                              -- no single primary recipient
    NEW.created_by                     -- exclude the creator
  );
  RETURN NEW;
END;
$$;
-- (notify_event_created keeps its existing EXECUTE grants: it is only invoked by
--  the existing trg_notify_event_created trigger, and it merely delegates to
--  notify_fanout, which is unchanged.)

-- 5) STATUS-CHANGE (UPDATE / CANCEL) NOTIFICATION -----------------------------
-- Notifies, with ONE deduplicated recipient set, the event's attendees + the
-- owning department's managers + all admins, excluding the actor. A user who is
-- both an attendee and a manager/admin therefore receives exactly one row for a
-- given status change. Scoped to the owning department; never company-wide.
CREATE OR REPLACE FUNCTION public.notify_event_status_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  label text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  label := CASE NEW.status
    WHEN 'cancelled'           THEN 'cancelled'
    WHEN 'cancelled_by_client' THEN 'cancelled by the client'
    WHEN 'cancelled_by_us'     THEN 'cancelled'
    WHEN 'done'                THEN 'marked done'
    WHEN 'completed'           THEN 'completed'
    ELSE NEW.status::text
  END;

  INSERT INTO public.notifications
    (recipient_id, type, title, body, reference_type, reference_id, is_read, channel)
  SELECT DISTINCT r.id,
         'calendar_event',
         'Event ' || label,
         'Event "' || NEW.title || '" was ' || label || '.',
         'event',
         NEW.id,
         false,
         'in_app'
  FROM (
    -- attendees
    SELECT profile_id AS id FROM public.event_attendees WHERE event_id = NEW.id
    UNION
    -- all admins / super admins (global oversight)
    SELECT id FROM public.profiles WHERE role = 'admin' OR is_super_admin = true
    UNION
    -- managers of the OWNING department only
    SELECT id FROM public.profiles
      WHERE NEW.team_id IS NOT NULL AND team_id = NEW.team_id AND role = 'manager'
  ) r
  WHERE r.id IS NOT NULL
    AND r.id IS DISTINCT FROM auth.uid();      -- exclude the actor

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notify_event_status_changed() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_event_status_changed ON public.events;
CREATE TRIGGER trg_notify_event_status_changed
  AFTER UPDATE OF status ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_event_status_changed();

-- 6) BOUNDED RETENTION — keep event_reminders small. Deletes ONLY calendar
--    reminder rows whose event already started more than 30 days ago. It joins
--    public.events and filters start_time < now() - 30 days, so it can never
--    touch a pending reminder for a current/future event, and it is scoped to
--    the event_reminders table alone.
CREATE OR REPLACE FUNCTION public.cleanup_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  removed integer;
BEGIN
  DELETE FROM public.event_reminders er
  USING public.events e
  WHERE er.event_id = e.id
    AND e.start_time < now() - interval '30 days';
  GET DIAGNOSTICS removed = ROW_COUNT;
  RAISE NOTICE 'Old event reminders removed: %', removed;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_event_reminders() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule('event-reminders-cleanup-daily');
EXCEPTION WHEN OTHERS THEN
  NULL;
END
$$;

SELECT cron.schedule(
  'event-reminders-cleanup-daily',
  '30 3 * * *',                        -- 03:30 daily, low-traffic window
  $$SELECT public.cleanup_event_reminders();$$
);

COMMIT;

-- ============================================================================
-- VERIFICATION (read-only; run AFTER apply). Expected results noted inline.
-- ============================================================================
-- a) Cron jobs registered:
--    SELECT jobname, schedule, active FROM cron.job
--     WHERE jobname IN ('event-reminders-5min','event-reminders-cleanup-daily');
--      -> two rows, '*/5 * * * *' and '30 3 * * *', active=true
--
-- b) EXECUTE is revoked from public/anon/authenticated (least privilege):
--    SELECT p.proname, p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--     WHERE n.nspname='public' AND p.proname IN
--       ('send_event_reminders','tg_event_reset_reminders',
--        'notify_event_status_changed','cleanup_event_reminders');
--      -> proacl must NOT contain a leading '=X/...' (PUBLIC) nor anon/authenticated=X
--
-- c) Recipient selection + timing DRY RUN (records/sends nothing) — proves
--    scoping to attendees of upcoming department events and the 60<15 rule:
--    SELECT e.id, ea.profile_id, o.offset_minutes
--    FROM public.events e
--    JOIN public.event_attendees ea ON ea.event_id=e.id
--    CROSS JOIN (VALUES (60),(15)) o(offset_minutes)
--    WHERE e.team_id IS NOT NULL
--      AND e.status NOT IN ('cancelled','cancelled_by_client','cancelled_by_us','done','completed')
--      AND e.start_time > now()
--      AND e.start_time <= now() + make_interval(mins => o.offset_minutes)
--      AND (o.offset_minutes <> 60 OR e.start_time > now() + interval '15 minutes');
--
-- d) Dedup: run SELECT public.send_event_reminders(); twice — the 2nd run
--    inserts 0 new notifications (unique constraint blocks re-recording).
--
-- e) Status dedup: a user who is BOTH an attendee AND a manager/admin of the
--    owning team gets exactly ONE row per status change (SELECT DISTINCT over
--    the unioned recipient set). The actor (auth.uid()) is excluded.
--
-- f) Cancellation: UPDATE an event to 'cancelled_by_us' -> §3 deletes its
--    event_reminders rows; a subsequent send_event_reminders() creates none;
--    §5 sends a single "Event cancelled" notification to the dept + attendees.
--
-- g) Reschedule: UPDATE start_time -> §3 clears rows; the sender re-reminds for
--    the new time as it approaches.
--
-- h) Permission boundary / RLS: event_reminders INSERT/UPDATE/DELETE remain
--    revoked from anon/authenticated (only the SECURITY DEFINER functions, owned
--    by postgres, write it); a normal user can SELECT only their own rows
--    (policy event_reminders_read_own). The definer functions bypass RLS only to
--    WRITE server-side rows — they expose nothing to clients.
-- ============================================================================
