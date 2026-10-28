-- ============================================================================
-- Phase 1b — lock down EXECUTE on the two event start-reminder functions.
-- Privilege changes ONLY. No function bodies, tables, cron, or end-reminder
-- objects are touched. Both functions currently have PUBLIC EXECUTE, so anon
-- and authenticated inherit it — these REVOKEs remove that.
--
-- Signatures verified live:
--   public.send_event_start_reminders()
--   public.set_event_start_reminders(uuid, integer[])
-- ============================================================================

-- 1) Sender: server-only. The pg_cron job runs as postgres (the owner), which
--    always retains EXECUTE, so revoking everyone else does not break the job.
REVOKE EXECUTE ON FUNCTION public.send_event_start_reminders()
  FROM PUBLIC, anon, authenticated;

-- 2) Replace RPC: authenticated only. Internal authz (admin / event manager)
--    is unchanged and still enforced in the function body. Remove PUBLIC + anon
--    (anon only had access via PUBLIC). service_role is left as-is (not granted
--    here, not in scope).
REVOKE EXECUTE ON FUNCTION public.set_event_start_reminders(uuid, integer[])
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_event_start_reminders(uuid, integer[])
  TO authenticated;
