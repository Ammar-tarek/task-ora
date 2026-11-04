-- ============================================================================
-- FIX — Task notifications were silent: the trigger was DISABLED.
-- ============================================================================
-- public.tasks has trigger trg_notify_task_status (AFTER UPDATE → notify_task_status),
-- which creates the in-app + push notifications on submit / approve / request-changes
-- / start. It was found DISABLED (pg_trigger.tgenabled = 'D'), so NO task notification
-- fired at all (verified: zero task_done / task_approved / task_rejected rows). The
-- function body is correct — only the trigger was off. Re-enable it:
ALTER TABLE public.tasks ENABLE TRIGGER trg_notify_task_status;

-- Verify (expect tgenabled = 'O'):
-- select tgname, tgenabled from pg_trigger
--   where tgrelid='public.tasks'::regclass and tgname='trg_notify_task_status';

-- ----------------------------------------------------------------------------
-- NOTE: these other IN-APP notify triggers are ALSO disabled. They are NOT
-- needed for the task-notification fix. Re-enable ONLY if you also want these
-- alerts back (they were likely turned off on purpose). Uncomment what you want:
--
-- ALTER TABLE public.attendance ENABLE TRIGGER trg_notify_att_checkinout;
-- ALTER TABLE public.attendance ENABLE TRIGGER trg_notify_attendance_approved;
-- ALTER TABLE public.expenses   ENABLE TRIGGER trg_notify_expense_approved;
-- ALTER TABLE public.penalties  ENABLE TRIGGER trg_notify_penalty;
-- ALTER TABLE public.profiles   ENABLE TRIGGER trg_notify_profile_team_upd;
--
-- The two n8n/Telegram triggers (notify_n8n_task_assignees on task_assignees)
-- push to external Telegram — leave disabled unless you specifically want that.
