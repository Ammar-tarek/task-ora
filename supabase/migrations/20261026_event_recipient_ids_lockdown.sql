-- 20261026_event_recipient_ids_lockdown.sql
-- Applied to prod 2026-10-26 (MCP apply_migration), SEPARATELY and AFTER
-- 20261026_event_end_time_reminders_v2.sql.
--
-- Why separate: v2 created event_recipient_ids and did REVOKE ... FROM PUBLIC,
-- but Supabase default-grants EXECUTE to the `anon` and `authenticated` roles
-- explicitly on new functions, so REVOKE FROM PUBLIC left those two grants in
-- place. This migration removes them, matching the locked-down ACL of the other
-- reminder helpers (postgres + service_role only). The SECURITY DEFINER caller
-- paths (notify_event_created trigger, send_event_reminders cron) run as the
-- owner `postgres` and are unaffected.

REVOKE EXECUTE ON FUNCTION public.event_recipient_ids(uuid, uuid) FROM anon, authenticated;
