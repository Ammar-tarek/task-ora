-- ============================================================================
-- PROPOSED (NOT APPLIED) — Finance M4: editable revenue date + free-text payer.
-- Needed for the required 7-column revenue table (Date must be editable, not
-- created_at; Payer Name must be free text, not the CRM client's name).
-- Additive + safe. No RLS change, no change to payment/void/correction guards,
-- no change to auto-CRM triggers. EGP currency untouched.
-- ============================================================================

-- 1) New columns (nullable, additive).
ALTER TABLE public.crm_entries
  ADD COLUMN IF NOT EXISTS entry_date date,
  ADD COLUMN IF NOT EXISTS payer_name text;

-- 2) Backfill legacy rows so the Date column is never empty. Uses each row's
--    own creation date as the starting EDITABLE date (one-time seed, not a
--    silent runtime substitution). New rows default to today (step 3).
UPDATE public.crm_entries
SET entry_date = created_at::date
WHERE entry_date IS NULL;

-- 3) New manual entries default to today's date when the app doesn't send one.
ALTER TABLE public.crm_entries
  ALTER COLUMN entry_date SET DEFAULT CURRENT_DATE;

-- Rollback:
--   ALTER TABLE public.crm_entries ALTER COLUMN entry_date DROP DEFAULT;
--   ALTER TABLE public.crm_entries DROP COLUMN IF EXISTS entry_date;
--   ALTER TABLE public.crm_entries DROP COLUMN IF EXISTS payer_name;
