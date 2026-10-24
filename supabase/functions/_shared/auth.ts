// supabase/functions/_shared/auth.ts
// Shared server-side auth guard for privileged Edge Functions.
// The service-role key lives ONLY in the function runtime env
// (SUPABASE_SERVICE_ROLE_KEY), never in the Flutter client.
//
// Pattern: the caller sends their normal user JWT (Authorization: Bearer ...).
// We resolve that user with the ANON client, then read their profile with the
// SERVICE client to get role + is_super_admin, and authorize server-side.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // runtime secret

export interface Caller {
  id: string;
  role: string;
  isSuperAdmin: boolean;
}

export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Resolve + verify the caller from the request's user JWT. Throws 401 if none. */
export async function getCaller(req: Request): Promise<Caller> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) throw httpError(401, "Missing bearer token");

  // Verify the JWT by asking the Auth server who it belongs to.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userRes, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userRes?.user) throw httpError(401, "Invalid session");

  const uid = userRes.user.id;
  const svc = serviceClient();
  const { data: profile, error: pErr } = await svc
    .from("profiles")
    .select("role, is_super_admin")
    .eq("id", uid)
    .maybeSingle();
  if (pErr || !profile) throw httpError(403, "No profile");

  return {
    id: uid,
    role: profile.role as string,
    isSuperAdmin: profile.is_super_admin === true,
  };
}

export function requireGlobalAdmin(c: Caller) {
  if (!(c.role === "admin" || c.isSuperAdmin)) throw httpError(403, "Admin only");
}

export function requireSuperAdmin(c: Caller) {
  if (!c.isSuperAdmin) throw httpError(403, "Super admin only");
}

export function httpError(status: number, msg: string): Response & { __thrown: true } {
  const r = new Response(JSON.stringify({ error: msg }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
  // deno-lint-ignore no-explicit-any
  (r as any).__thrown = true;
  return r as Response & { __thrown: true };
}

export function ok(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
