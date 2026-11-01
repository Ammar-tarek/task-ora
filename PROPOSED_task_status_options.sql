-- ============================================================================
-- PROPOSED (NOT APPLIED) — Stable task status options ("manage columns").
--
-- The status options used to live inside the generic custom_tables /
-- custom_columns system whose RLS is team-scoped. The backing system table was
-- created with NO team, so only a GLOBAL ADMIN could read/write it reliably —
-- managers/employees fell back to the 7 hard-coded built-ins and never saw
-- admin-added options, and writes silently failed. That is the "not stable".
--
-- This moves status options to a simple, GLOBAL table:
--   READ  = every authenticated user (statuses are shared across all tasks).
--   WRITE = global admin or manager.
-- Seeds the current options (incl. any custom ones) so nothing is lost.
-- Apply, then the app reads/writes this table (TaskStatusOptionsRepository).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.task_status_options (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label      text NOT NULL,
  color      text NOT NULL DEFAULT '#888888',
  position   int  NOT NULL DEFAULT 0,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS task_status_options_label_key
  ON public.task_status_options (lower(label));

ALTER TABLE public.task_status_options ENABLE ROW LEVEL SECURITY;

-- Shared list → readable by everyone signed in.
CREATE POLICY task_status_options_read ON public.task_status_options
  FOR SELECT TO authenticated USING (true);

-- Managed by admins and managers.
CREATE POLICY task_status_options_write ON public.task_status_options
  FOR ALL TO authenticated
  USING (public.is_global_admin() OR public.is_manager())
  WITH CHECK (public.is_global_admin() OR public.is_manager());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_status_options TO authenticated;

-- Seed the current options (only when the table is empty).
INSERT INTO public.task_status_options (label, color, position, is_default)
SELECT * FROM (VALUES
  ('not_started',     '#6D4C41', 0, true),
  ('in_progress',     '#1565C0', 1, true),
  ('employee_done',   '#755B00', 2, true),
  ('client_approved', '#2E7D32', 3, true),
  ('client_rejected', '#BA1A1A', 4, true),
  ('completed',       '#2E7D32', 5, true),
  ('on_hold',         '#747878', 6, true),
  ('Done',            '#888888', 7, false)
) v(label, color, position, is_default)
WHERE NOT EXISTS (SELECT 1 FROM public.task_status_options);

-- Rollback:
--   DROP TABLE IF EXISTS public.task_status_options;
