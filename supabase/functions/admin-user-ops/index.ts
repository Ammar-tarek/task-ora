// supabase/functions/admin-user-ops/index.ts
// Privileged user management behind server-side authorization. Replaces the
// Flutter adminClient paths: ProfileRepository.createUser / updateEmployee /
// updateRole / setStatus / fetchEmail and ClientRepository.createClientWithAccount.
//
// NOT DEPLOYED. Deploy: `supabase functions deploy admin-user-ops`.
// Caller sends their user JWT; only a global admin may act. A plain admin may
// NOT grant super_admin (only a super admin can). Never trusts a client role.

import { getCaller, requireGlobalAdmin, serviceClient, ok, httpError } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  try {
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
  } catch (e) {
    // Thrown Response from the auth guard
    // deno-lint-ignore no-explicit-any
    if (e && (e as any).__thrown) return e as Response;
    return httpError(500, "Internal error");
  }
});
