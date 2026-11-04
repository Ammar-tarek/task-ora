-- PROPOSED (run in Supabase SQL Editor) — wipe the company cash ledger.
-- Approved: "Wipe whole ledger, start expenses fresh" (2026-11-03).
--
-- WHY: the company available balance now comes from collected DEPARTMENT REVENUE
-- (manual crm_entries.paid_amount, non-cancelled), computed by the already-applied
-- company_cash_balance(). The old company_ledger held 3 manual "Add Funds" deposits
-- (20,500) and 3 "Balance reset" expenses (18,150) from the retired manual-deposit
-- model, plus 5 real expenses. Per your choice we clear ALL rows so expenses start
-- from zero; the ledger is expenses-only going forward.
--
-- BACKUP: a full JSON snapshot of these 11 rows was saved before this wipe at
--   <scratchpad>/company_ledger_backup_2026-11-03.json
-- (ask Claude to restore from it if ever needed).
--
-- AFTER THIS: available balance = collected revenue (currently 15,300 EGP) minus
-- any new expenses you record. The MCP execute_sql path declined this DELETE
-- (destructive-DML guard), which is why it is delivered here to run manually.

DELETE FROM public.company_ledger;

-- Verify (optional): should return 0 rows and the revenue-based balance.
-- SELECT count(*) AS ledger_rows FROM public.company_ledger;
-- SELECT public.company_cash_balance() AS available_balance;  -- run as an admin
