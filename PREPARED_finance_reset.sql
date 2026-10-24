-- ============================================================================
-- PREPARED_finance_reset.sql  —  NOT EXECUTED. Needs explicit approval to run.
--
-- APPROVED SCOPE (wipe ALL rows from these 5 tables only):
--   crm_payment_audit, crm_entry_corrections, crm_payments, crm_entries, expenses
-- KEEP (untouched): penalties, expense_categories, penalty_types, and every
--   other table/object. No DROP, no TRUNCATE, no schema change.
--
-- `expenses` is shared with Department Finance; this reset intentionally clears
-- its rows too (approved). Department Finance CODE/config is NOT changed.
--
-- SAFETY NOTES (verified against live schema 2026-10-24):
--   * All inbound FKs to these tables come only from within this set
--     (crm_payments/crm_payment_audit/crm_entry_corrections → crm_entries;
--      crm_payment_audit → crm_payments). No table OUTSIDE the set references
--      them, so no external RESTRICT blocks and no cascade escapes the scope.
--   * Delete order is CHILD → PARENT to satisfy ON DELETE RESTRICT.
--   * Deleting crm_payments fires sync_crm_payment_status, which UPDATEs the
--     parent crm_entries row's paid_amount/status only (NOT amount), so
--     guard_crm_entry_amount (fires only when amount changes) does not block.
--   * expenses deletes fire no triggers (notify is UPDATE-only).
--
-- ROLLBACK LIMITATION: this is a hard DELETE. The ONLY way back is
--   RESTORE_finance_backup.sql (built from BACKUP_finance_2026-10-24.sql).
--   Confirm that backup is present and verified BEFORE running this.
-- ============================================================================

BEGIN;

-- ── PRECONDITIONS: abort if the live data drifted from the reviewed snapshot ──
DO $$
DECLARE
  c_audit   int := (SELECT count(*) FROM public.crm_payment_audit);
  c_corr    int := (SELECT count(*) FROM public.crm_entry_corrections);
  c_pay     int := (SELECT count(*) FROM public.crm_payments);
  c_entries int := (SELECT count(*) FROM public.crm_entries);
  c_exp     int := (SELECT count(*) FROM public.expenses);
  c_ext_pay int := (SELECT count(*) FROM public.crm_payments p
                      WHERE NOT EXISTS (SELECT 1 FROM public.crm_entries e WHERE e.id = p.crm_entry_id));
BEGIN
  -- Expected counts captured 2026-10-24. If different, data changed since
  -- review → STOP so a human re-reviews instead of deleting blindly.
  IF c_audit <> 2 OR c_corr <> 0 OR c_pay <> 2 OR c_entries <> 3 OR c_exp <> 5 THEN
    RAISE EXCEPTION 'Row counts drifted from reviewed snapshot '
      '(audit=% corr=% pay=% entries=% exp=%; expected 2/0/2/3/5). Aborting.',
      c_audit, c_corr, c_pay, c_entries, c_exp;
  END IF;
  -- A payment pointing at a missing entry would mean a new, unreviewed shape.
  IF c_ext_pay <> 0 THEN
    RAISE EXCEPTION 'Found % crm_payments with no parent crm_entries row — unreviewed state. Aborting.', c_ext_pay;
  END IF;
END $$;

-- ── DELETES (child → parent) ─────────────────────────────────────────────────
DELETE FROM public.crm_payment_audit;      -- child of payments + entries
DELETE FROM public.crm_entry_corrections;  -- child of entries (0 rows)
DELETE FROM public.crm_payments;           -- child of entries
DELETE FROM public.crm_entries;            -- parent
DELETE FROM public.expenses;               -- independent

-- ── POSTCONDITIONS: all five must be empty; everything else must be intact ───
DO $$
DECLARE
  c_audit   int := (SELECT count(*) FROM public.crm_payment_audit);
  c_corr    int := (SELECT count(*) FROM public.crm_entry_corrections);
  c_pay     int := (SELECT count(*) FROM public.crm_payments);
  c_entries int := (SELECT count(*) FROM public.crm_entries);
  c_exp     int := (SELECT count(*) FROM public.expenses);
  c_pentyp  int := (SELECT count(*) FROM public.penalty_types);
  c_excat   int := (SELECT count(*) FROM public.expense_categories);
  c_pen     int := (SELECT count(*) FROM public.penalties);
BEGIN
  IF c_audit <> 0 OR c_corr <> 0 OR c_pay <> 0 OR c_entries <> 0 OR c_exp <> 0 THEN
    RAISE EXCEPTION 'Target tables not fully cleared (audit=% corr=% pay=% entries=% exp=%). Rolling back.',
      c_audit, c_corr, c_pay, c_entries, c_exp;
  END IF;
  -- Excluded tables must be untouched (penalties/config preserved).
  IF c_pen <> 2 OR c_excat <> 10 OR c_pentyp <> 4 THEN
    RAISE EXCEPTION 'Excluded table changed unexpectedly (penalties=% expense_categories=% penalty_types=%; expected 2/10/4). Rolling back.',
      c_pen, c_excat, c_pentyp;
  END IF;
  RAISE NOTICE 'Finance reset OK: 5 target tables cleared; penalties/config preserved.';
END $$;

-- Review the NOTICE above, then COMMIT. Use ROLLBACK to abort with no changes.
COMMIT;
