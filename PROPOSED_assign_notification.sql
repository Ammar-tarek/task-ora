-- ============================================================================
-- PROPOSED (NOT APPLIED) — Single, detailed assign notification.
--
-- The Flutter app now sends ONE rich "New task assigned to you" notification
-- (title + description + due + priority) to each assignee from
-- TaskRepository.assignEmployees (via create_notification). The old DB trigger
-- trg_notify_task_assigned fired a SECOND, title-only notification to the same
-- assignee on every task_assignees insert — a duplicate. Drop it so assignees
-- get a single, detailed ping.
--
-- Accept/reject notifications to admins + the team's managers are unchanged
-- (respond_to_assignment -> notify_fanout). This only removes the duplicate.
-- Safe because every assignment goes through the app (assignEmployees).
-- ============================================================================
DROP TRIGGER IF EXISTS trg_notify_task_assigned ON public.task_assignees;
DROP FUNCTION IF EXISTS public.notify_task_assigned();

-- Rollback (restores the old title-only assignee ping):
--   see the original migration that created notify_task_assigned() +
--   trg_notify_task_assigned AFTER INSERT ON public.task_assignees.
