-- ============================================================================
-- ROLLBACK for PROPOSED_company_ledger.sql
-- Drops the RPCs and the table. NOTE: dropping the table deletes all central
-- cash deposits/expenses recorded in it. Export first if you need the data.
-- Department finance and the shared `expenses` table are not involved here.
-- ============================================================================

DROP FUNCTION IF EXISTS public.company_add_funds(numeric,date,text,uuid);
DROP FUNCTION IF EXISTS public.company_record_expense(numeric,date,text,uuid);
DROP FUNCTION IF EXISTS public.company_cash_balance();
DROP TABLE IF EXISTS public.company_ledger;
