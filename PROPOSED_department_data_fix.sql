-- ============================================================================
-- PROPOSED (NOT APPLIED) — Department membership data fixes. Review each block.
-- Prepared per audit. DO NOT run blindly — confirm each row with the business.
--
-- Audit snapshot (2026-10-24), teams.department:
--   Admins          = NULL   (intentional — admins are cross-department)
--   Marketing       = 'Marketing'        OK
--   Montage         = 'Montage'          OK
--   Sales           = NULL   ← BUG: Sales members resolve to no department
--   Studio          = 'Studio'           OK (but team has no lead, no members)
--   Video Production= 'Video Production' OK (only 1 member, inactive)
--
-- Users of note:
--   'test'      employee, INACTIVE, team_id = NULL   → no department
--   'sama'      employee, INACTIVE, team Sales
--   'ibram Samy' employee, INACTIVE, team Video Production
-- ============================================================================

-- ── FIX 1 (recommended): give Sales a department so isolation/reporting work.
-- Confirm the canonical label with the business ('Sales').
-- UPDATE public.teams SET department = 'Sales' WHERE name = 'Sales' AND department IS NULL;

-- ── REVIEW 2: 'Admins' department intentionally NULL. Only set if the business
-- wants admins filtered into a department (usually NO — leave NULL).
-- (no statement — left as documentation)

-- ── REVIEW 3: 'test' employee has no team and is inactive. Options:
--   (a) leave as-is (inactive, harmless), or
--   (b) deactivate/remove if it is a leftover test account.
-- Do NOT auto-assign a team. Decide manually.
-- SELECT id, full_name, role, status, team_id FROM public.profiles WHERE full_name = 'test';

-- ── REVIEW 4: Studio team has no team_lead_id and no members. If Studio is a
-- live department, assign a lead + members; if not, consider is_active=false.
-- SELECT * FROM public.teams WHERE name = 'Studio';

-- ── READ-ONLY AUDIT QUERY (safe to run anytime) — classify every user:
-- SELECT p.full_name, p.role, p.status,
--        t.name AS team, t.department,
--        CASE
--          WHEN p.role = 'client' THEN 'ok (client, no team expected)'
--          WHEN p.team_id IS NULL  THEN 'MISSING team'
--          WHEN p.role <> 'admin' AND t.department IS NULL THEN 'team has NULL department'
--          ELSE 'ok'
--        END AS verdict
-- FROM public.profiles p
-- LEFT JOIN public.teams t ON t.id = p.team_id
-- ORDER BY verdict, p.role, t.name NULLS FIRST, p.full_name;
