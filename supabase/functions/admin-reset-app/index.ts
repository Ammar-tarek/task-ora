// supabase/functions/admin-reset-app/index.ts
// Super-admin-only destructive reset. Replaces ResetAppRepository (which runs
// via the client service-role key). NOT DEPLOYED. NEVER run against prod to test.
//
// Deletes app data in FK order, then deletes non-super-admin Auth users,
// preserving the calling super admin. Authorization is server-side: the caller
// must be a verified super admin (is_super_admin), not a client-supplied flag.

import { getCaller, requireSuperAdmin, serviceClient, ok, httpError } from "../_shared/auth.ts";

// Exact FK-safe order from ResetAppRepository.
const DELETE_ORDER = [
  "task_comments", "task_assignees", "task_mentions", "task_approvals",
  "task_attachments", "task_audit_log", "client_task_visibility",
  "client_task_column_visibility", "tasks", "task_board_columns", "task_boards",
  "attendance", "expenses", "expense_categories", "penalties", "penalty_types",
  "crm_payments", "crm_entries", "event_attendees", "event_attachments",
  "room_bookings", "events", "rooms", "note_audit_log", "note_links",
  "note_attachments", "note_shares", "note_tags", "notes", "cell_audit_log",
  "custom_cell_values", "custom_rows", "column_status_options", "custom_columns",
  "table_permissions", "table_views", "custom_tables", "notifications",
  "ai_interactions", "client_profiles", "user_privileges", "team_privileges",
];

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return httpError(405, "POST only");
    const caller = await getCaller(req);
    requireSuperAdmin(caller); // <-- the real gate

    const svc = serviceClient();
    const ZERO = "00000000-0000-0000-0000-000000000000";

    for (const table of DELETE_ORDER) {
      const { error } = await svc.from(table).delete().neq("id", ZERO);
      if (error) {
        // Preserve the error; do not improvise. Stop the sequence.
        return httpError(500, `Failed clearing ${table}: ${error.message}`);
      }
    }

    // Detach team_id, then delete teams.
    await svc.from("profiles").update({ team_id: null }).neq("id", ZERO);
    await svc.from("teams").delete().neq("id", ZERO);

    // Delete non-super-admin Auth users + profiles, keep the caller.
    const { data: others } = await svc
      .from("profiles").select("id").neq("id", caller.id);
    for (const p of others ?? []) {
      const uid = (p as { id: string }).id;
      if (uid && uid !== caller.id) {
        try { await svc.auth.admin.deleteUser(uid); } catch (_) { /* best effort */ }
      }
    }
    await svc.from("profiles").delete().neq("id", caller.id);

    return ok({ reset: true });
  } catch (e) {
    // deno-lint-ignore no-explicit-any
    if (e && (e as any).__thrown) return e as Response;
    return httpError(500, "Internal error");
  }
});
