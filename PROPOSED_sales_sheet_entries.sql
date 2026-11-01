-- ============================================================================
-- PROPOSED (NOT APPLIED) — Sales Sheet pipeline table. Needs explicit approval.
-- A Sales-department CRM pipeline sheet, editable in-app. All columns are free
-- text (mirrors the source Google Sheet). sort_order drives manual ordering.
--
-- RLS:
--   READ  = global admin, OR any staff whose team is the Sales department.
--   WRITE = global admin, OR a MANAGER of the Sales team (employees read-only).
--
-- Apply this file FIRST, then PROPOSED_sales_sheet_seed.sql to load the PDF rows.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sales_sheet_entries (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sort_order     double precision NOT NULL DEFAULT 0,
  client         text NOT NULL DEFAULT '',
  link           text NOT NULL DEFAULT '',
  owner_name     text NOT NULL DEFAULT '',
  owner_number   text NOT NULL DEFAULT '',
  status         text NOT NULL DEFAULT '',
  probability    text NOT NULL DEFAULT '',
  est_value      text NOT NULL DEFAULT '',
  last_contact   text NOT NULL DEFAULT '',
  expected_close text NOT NULL DEFAULT '',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sales_sheet_entries_sort_idx
  ON public.sales_sheet_entries (sort_order, created_at);

CREATE OR REPLACE FUNCTION public.tg_sales_sheet_touch()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_sheet_touch ON public.sales_sheet_entries;
CREATE TRIGGER trg_sales_sheet_touch
  BEFORE UPDATE ON public.sales_sheet_entries
  FOR EACH ROW EXECUTE FUNCTION public.tg_sales_sheet_touch();

ALTER TABLE public.sales_sheet_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY sales_sheet_read ON public.sales_sheet_entries
  FOR SELECT TO authenticated
  USING (
    public.is_global_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.team_id = (SELECT id FROM public.teams WHERE department = 'Sales' LIMIT 1)
    )
  );

CREATE POLICY sales_sheet_write ON public.sales_sheet_entries
  FOR ALL TO authenticated
  USING (
    public.is_global_admin()
    OR (
      public.is_manager()
      AND (SELECT team_id FROM public.profiles WHERE id = auth.uid())
          = (SELECT id FROM public.teams WHERE department = 'Sales' LIMIT 1)
    )
  )
  WITH CHECK (
    public.is_global_admin()
    OR (
      public.is_manager()
      AND (SELECT team_id FROM public.profiles WHERE id = auth.uid())
          = (SELECT id FROM public.teams WHERE department = 'Sales' LIMIT 1)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.sales_sheet_entries TO authenticated;

-- Rollback:
--   DROP TABLE IF EXISTS public.sales_sheet_entries;
--   DROP FUNCTION IF EXISTS public.tg_sales_sheet_touch();
