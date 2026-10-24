-- ============================================================================
-- ROLLBACK for PROPOSED_task_assignment_response.sql
-- Drops the field guard + RPC. Columns are kept by default (harmless, hold
-- historical responses). Uncomment the ALTER to remove them (loses that data).
-- ============================================================================

DROP TRIGGER IF EXISTS trg_guard_task_employee_fields ON public.tasks;
DROP FUNCTION IF EXISTS public.guard_task_employee_fields();
DROP FUNCTION IF EXISTS public.respond_to_assignment(uuid,text,text);

-- ALTER TABLE public.task_assignees
--   DROP COLUMN IF EXISTS response,
--   DROP COLUMN IF EXISTS responded_at,
--   DROP COLUMN IF EXISTS response_reason;
