-- ============================================================================
-- PROPOSED (NOT APPLIED) — Central Company Cash Ledger. Needs explicit approval.
--
-- WHY A NEW TABLE (not `expenses`): the existing `public.expenses` table is
-- SHARED — Department Finance reads it (finance_repository.dart) and managers
-- write their team's rows via the manager_team_expenses RLS policy. The ticket
-- requires the central company cash balance to be fully isolated from
-- Department Finance and must not alter it. So the central ledger lives in its
-- own admin-only table. `expenses` and all department finance stay untouched.
-- Nothing is migrated into this ledger (no silent import of dept expenses).
--
-- WHAT IT ADDS:
--   * table company_ledger (deposits + expenses, admin-only RLS)
--   * RPC company_add_funds()       — record a deposit (idempotent)
--   * RPC company_record_expense()  — record an expense; atomic balance guard
--     (advisory lock) rejects overspend and invalid amounts; idempotent
--   * RPC company_cash_balance()    — all-time balance (deposits − expenses)
--
-- ROLLBACK: ROLLBACK_company_ledger.sql
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.company_ledger (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  txn_type     text NOT NULL CHECK (txn_type IN ('deposit','expense')),
  amount       numeric NOT NULL CHECK (amount > 0),
  txn_date     date NOT NULL,
  description  text,
  created_by   uuid NOT NULL REFERENCES public.profiles(id),
  client_token uuid,                 -- idempotency key for retried submissions
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.company_ledger IS
  'Central company cash ledger (deposits + expenses). Admin-only. Isolated from department finance and the shared expenses table.';

CREATE UNIQUE INDEX IF NOT EXISTS company_ledger_client_token_key
  ON public.company_ledger (client_token) WHERE client_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS company_ledger_txn_date_idx
  ON public.company_ledger (txn_date);

ALTER TABLE public.company_ledger ENABLE ROW LEVEL SECURITY;

-- Admin (and super admin) only — same gate used across the app.
DROP POLICY IF EXISTS company_ledger_admin_all ON public.company_ledger;
CREATE POLICY company_ledger_admin_all ON public.company_ledger
  FOR ALL TO public
  USING (public.is_global_admin())
  WITH CHECK (public.is_global_admin());

-- ── Balance (all-time, month-independent) ───────────────────────────────────
-- Admin-gated: non-admins get NULL (no leak of the company cash total). Called
-- internally by the two RPCs below (which run as owner, so the REVOKE further
-- down does not block them).
CREATE OR REPLACE FUNCTION public.company_cash_balance()
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE WHEN public.is_global_admin() THEN
    COALESCE(SUM(CASE WHEN txn_type='deposit' THEN amount ELSE -amount END), 0)
  ELSE NULL END
  FROM public.company_ledger;
$$;

-- ── Add funds (deposit). Idempotent on client_token. Returns new balance. ───
CREATE OR REPLACE FUNCTION public.company_add_funds(
  p_amount numeric,
  p_date date,
  p_description text DEFAULT NULL,
  p_client_token uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_global_admin() THEN
    RAISE EXCEPTION 'Only an admin can add funds.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero.' USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotency: a retried submission with the same token is a no-op.
  IF p_client_token IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.company_ledger WHERE client_token = p_client_token) THEN
    RETURN public.company_cash_balance();
  END IF;

  INSERT INTO public.company_ledger (txn_type, amount, txn_date, description, created_by, client_token)
  VALUES ('deposit', p_amount, COALESCE(p_date, CURRENT_DATE), NULLIF(btrim(p_description),''), auth.uid(), p_client_token)
  ON CONFLICT (client_token) WHERE client_token IS NOT NULL DO NOTHING;

  RETURN public.company_cash_balance();
END;
$$;

-- ── Record expense. Atomic balance guard rejects overspend. Idempotent. ─────
CREATE OR REPLACE FUNCTION public.company_record_expense(
  p_amount numeric,
  p_date date,
  p_description text,
  p_client_token uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_balance numeric;
BEGIN
  IF NOT public.is_global_admin() THEN
    RAISE EXCEPTION 'Only an admin can record a company expense.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero.' USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(btrim(p_description),'') = '' THEN
    RAISE EXCEPTION 'A description is required.' USING ERRCODE = 'check_violation';
  END IF;

  -- Serialize all company-cash writes so concurrent expenses cannot overspend
  -- or double-insert the same token.
  PERFORM pg_advisory_xact_lock(hashtext('company_ledger_cash'));

  -- Idempotency: a retried/concurrent submission with the same token is a
  -- no-op. Checked INSIDE the lock so two racing first submits cannot both pass.
  IF p_client_token IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.company_ledger WHERE client_token = p_client_token) THEN
    RETURN public.company_cash_balance();
  END IF;

  v_balance := public.company_cash_balance();
  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'Expense (%) exceeds available balance (%).', p_amount, v_balance
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.company_ledger (txn_type, amount, txn_date, description, created_by, client_token)
  VALUES ('expense', p_amount, COALESCE(p_date, CURRENT_DATE), btrim(p_description), auth.uid(), p_client_token)
  ON CONFLICT (client_token) WHERE client_token IS NOT NULL DO NOTHING;

  RETURN public.company_cash_balance();
END;
$$;

REVOKE ALL ON FUNCTION public.company_add_funds(numeric,date,text,uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.company_record_expense(numeric,date,text,uuid) FROM public, anon;
-- Balance fn is internal-only (the two RPCs call it as owner). Not exposed.
REVOKE ALL ON FUNCTION public.company_cash_balance() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.company_add_funds(numeric,date,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_record_expense(numeric,date,text,uuid) TO authenticated;

-- ── VALIDATION (after apply) ────────────────────────────────────────────────
-- as admin:  SELECT company_add_funds(1000, CURRENT_DATE, 'seed', gen_random_uuid());  -- 1000
--            SELECT company_record_expense(300, CURRENT_DATE, 'rent', gen_random_uuid()); -- 700
--            SELECT company_record_expense(99999, CURRENT_DATE, 'x', gen_random_uuid());  -- ERROR exceeds balance
-- idempotent: call add_funds twice with the SAME token → balance rises once.
-- as non-admin: any RPC → ERROR insufficient_privilege.
