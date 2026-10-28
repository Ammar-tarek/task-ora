// supabase/functions/admin-user-ops/index.ts
// Privileged user management behind server-side authorization. Replaces the
// Flutter adminClient paths: ProfileRepository.createUser / updateEmployee /
// updateRole / setStatus / fetchEmail and ClientRepository.createClientWithAccount.
//
// Deploy / redeploy: `supabase functions deploy admin-user-ops`.
// Caller sends their user JWT; only a global admin may act. A plain admin may
// NOT grant super_admin (only a super admin can). Never trusts a client role.
//
// CORS: the browser (Flutter Web) sends an OPTIONS preflight before the POST
// because the request carries custom headers (authorization/apikey/x-client-info).
// That preflight is answered here BEFORE any auth, and CORS headers are attached
// to every response so the browser can read the actual POST result.

import { getCaller, requireGlobalAdmin, serviceClient, ok, httpError } from "../_shared/auth.ts";

// Optional strict allowlist via env (comma-separated). When unset we echo the
// caller's Origin — never a literal "*" — which supports the local dev server
// and the production web origin without hardcoding either. The endpoint stays
// JWT-protected regardless of Origin.
const ALLOWED_ORIGINS = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowOrigin = ALLOWED_ORIGINS.length === 0
    ? (origin || "*")
    : (ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]);
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function withCors(res: Response, req: Request): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(corsHeaders(req))) headers.set(k, v);
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}

Deno.serve(async (req) => {
  // Preflight: succeed immediately, before any auth or body parsing.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  let res: Response;
  try {
    res = await handle(req);
  } catch (e) {
    // Thrown Response from the auth guard (httpError marks it with __thrown).
    // deno-lint-ignore no-explicit-any
    res = e && (e as any).__thrown ? (e as Response) : httpError(500, "Internal error");
  }
  // Every response (ok, httpError, thrown) carries CORS so the browser can read it.
  return withCors(res, req);
});

// Actual privileged work. Auth + payload validation happen here, exactly as
// before — the only change is that CORS is layered on by the wrapper above.
async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return httpError(405, "POST only");
  const caller = await getCaller(req);
  requireGlobalAdmin(caller);

  const body = await req.json();
  const action = String(body.action ?? "");
  const svc = serviceClient();

  switch (action) {
    case "create_user": {
      const { email, password, fullName, role, teamId } = body;
      if (!email || !password || !fullName) return httpError(400, "Missing fields");
      if (role === "super_admin" && !caller.isSuperAdmin) {
        return httpError(403, "Only a super admin can create a super admin");
      }
      const { data: created, error: cErr } = await svc.auth.admin.createUser({
        email: String(email).trim(),
        password: String(password),
        email_confirm: true,
        user_metadata: { full_name: String(fullName).trim() },
      });
      if (cErr || !created.user) return httpError(400, cErr?.message ?? "Create failed");
      const uid = created.user.id;
      await svc.from("profiles").upsert({
        id: uid,
        full_name: String(fullName).trim(),
        role: role ?? "employee",
        status: "active",
        ...(teamId ? { team_id: teamId } : {}),
      });
      return ok({ id: uid });
    }

    case "delete_user": {
      const { userId } = body;
      if (!userId) return httpError(400, "Missing userId");
      // Guard: do not allow deleting the last super admin / self-delete here.
      if (userId === caller.id) return httpError(400, "Cannot delete self");
      await svc.auth.admin.deleteUser(String(userId));
      return ok({ deleted: userId });
    }

    case "update_user": {
      const { userId, email, password, fullName, role, status, phone } = body;
      if (!userId) return httpError(400, "Missing userId");
      if (role === "super_admin" && !caller.isSuperAdmin) {
        return httpError(403, "Only a super admin can grant super admin");
      }
      if ((email || password)) {
        await svc.auth.admin.updateUserById(String(userId), {
          ...(email ? { email: String(email) } : {}),
          ...(password ? { password: String(password) } : {}),
        });
      }
      const upd: Record<string, unknown> = { updated_at: new Date().toISOString() };
      if (fullName != null) upd.full_name = fullName;
      if (role != null) upd.role = role;
      if (status != null) upd.status = status;
      if (phone !== undefined) upd.phone = phone; // null clears it
      await svc.from("profiles").update(upd).eq("id", String(userId));
      return ok({ updated: userId });
    }

    case "set_active": {
      // Activate / deactivate an employee without deleting any data.
      //   active === false → ban the Auth user + profiles.status = 'inactive'
      //   active === true  → remove the ban + profiles.status = 'active'
      // Historical rows (tasks, revenue, attendance, audit) are never touched.
      const { userId, active } = body;
      if (!userId) return httpError(400, "Missing userId");
      if (typeof active !== "boolean") return httpError(400, "Missing 'active' boolean");
      const targetId = String(userId);

      // Reject self-deactivation/reactivation outright.
      if (targetId === caller.id) {
        return httpError(400, "You cannot change your own active status");
      }

      // Load the target to enforce the admin / super-admin rules server-side.
      const { data: target, error: tErr } = await svc
        .from("profiles")
        .select("role, is_super_admin, status")
        .eq("id", targetId)
        .maybeSingle();
      if (tErr) return httpError(400, tErr.message);
      if (!target) return httpError(404, "Target profile not found");

      const targetIsAdmin = target.role === "admin" || target.is_super_admin === true;
      // Only a super admin may change another admin's (or super admin's) status.
      if (targetIsAdmin && !caller.isSuperAdmin) {
        return httpError(403, "Only a super admin can change an admin's active status");
      }

      if (!active) {
        // ── DEACTIVATION ──────────────────────────────────────────────────
        // Protect the last active admin: never leave the org with zero active
        // admins. Count active admins other than the target.
        if (targetIsAdmin) {
          const { data: admins, error: aErr } = await svc
            .from("profiles")
            .select("id")
            .eq("status", "active")
            .or("role.eq.admin,is_super_admin.eq.true");
          if (aErr) return httpError(400, aErr.message);
          const others = (admins ?? []).filter((a) => a.id !== targetId);
          if (others.length === 0) {
            return httpError(409, "Cannot deactivate the last active admin");
          }
        }

        // Ban first (blocks token refresh → future sessions), then flip the
        // profile. Order matters for partial-failure safety: if the profile
        // update fails we roll the ban back so we never end up with an
        // "active" profile whose Auth user is banned.
        //
        // Revocation note: ban_duration is the supported Auth Admin ban API.
        // It invalidates FUTURE refresh-token exchanges for this user; any
        // already-issued access token stays valid until it expires (≈1h). There
        // is no supported supabase-js admin call to revoke a user's live access
        // tokens by id, so we deliberately rely on the ban + the client-side
        // profiles.status check rather than a cast to an unsupported method.
        const { error: banErr } = await svc.auth.admin.updateUserById(targetId, {
          ban_duration: "876000h", // ~100 years (Auth Admin "ban" API)
        });
        if (banErr) return httpError(400, `Auth ban failed: ${banErr.message}`);

        const { error: pErr } = await svc
          .from("profiles")
          .update({ status: "inactive", updated_at: new Date().toISOString() })
          .eq("id", targetId);
        if (pErr) {
          // Roll the ban back so we don't leave a banned Auth user with an
          // "active" profile. Check the rollback too — if IT fails, the two
          // sides are inconsistent and we must say so, not claim recovery.
          const { error: rbErr } = await svc.auth.admin.updateUserById(targetId, {
            ban_duration: "none",
          });
          if (rbErr) {
            return httpError(
              500,
              `Inconsistent state: profile update failed (${pErr.message}) AND ban rollback failed (${rbErr.message}). ` +
                `User ${targetId} is Auth-banned but profile is still active — retry deactivation or lift the ban manually.`,
            );
          }
          return httpError(500, `Profile update failed, ban rolled back: ${pErr.message}`);
        }
        return ok({ userId: targetId, status: "inactive" });
      } else {
        // ── REACTIVATION ──────────────────────────────────────────────────
        // Flip the profile active first, then lift the ban. If the unban fails
        // we roll the profile back so we never show "active" for a user whose
        // Auth account is still banned.
        const { error: pErr } = await svc
          .from("profiles")
          .update({ status: "active", updated_at: new Date().toISOString() })
          .eq("id", targetId);
        if (pErr) return httpError(500, `Profile update failed: ${pErr.message}`);

        const { error: unbanErr } = await svc.auth.admin.updateUserById(targetId, {
          ban_duration: "none",
        });
        if (unbanErr) {
          // Roll the profile back to inactive so we don't show "active" for a
          // user whose Auth account is still banned. Check the rollback too.
          const { error: rbErr } = await svc
            .from("profiles")
            .update({ status: "inactive", updated_at: new Date().toISOString() })
            .eq("id", targetId);
          if (rbErr) {
            return httpError(
              500,
              `Inconsistent state: unban failed (${unbanErr.message}) AND profile rollback failed (${rbErr.message}). ` +
                `User ${targetId} shows active but is still Auth-banned — retry reactivation.`,
            );
          }
          return httpError(500, `Auth unban failed, profile rolled back: ${unbanErr.message}`);
        }
        return ok({ userId: targetId, status: "active" });
      }
    }

    case "get_email": {
      const { userId } = body;
      if (!userId) return httpError(400, "Missing userId");
      const { data: u, error: gErr } = await svc.auth.admin.getUserById(String(userId));
      if (gErr) return httpError(400, gErr.message);
      return ok({ email: u.user?.email ?? null });
    }

    default:
      return httpError(400, `Unknown action: ${action}`);
  }
}
