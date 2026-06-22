import { useState } from "react";

const MODULES = [
  {
    id: "auth",
    label: "Users & Auth",
    color: "#3B82F6",
    bg: "#EFF6FF",
    icon: "👤",
    summary: "Who is in the system and what role they have.",
    tables: [
      {
        name: "auth.users",
        managed: true,
        plain: "Managed by Supabase automatically. Stores email, password hash, and login tokens. You never touch this table directly — Supabase handles it.",
        fields: ["id (UUID)", "email", "password (hashed)", "raw_user_meta_data"],
        relations: [{ to: "profiles", type: "1:1", label: "Every login account gets one profile row" }],
      },
      {
        name: "profiles",
        plain: "The main user record for everyone in the app — admins, employees, and clients. Holds the user's name, role, and which team they belong to. The role column (admin / employee / client) controls every single permission in the entire app.",
        fields: ["id → auth.users", "role (admin/employee/client)", "full_name", "phone", "team_id", "status", "preferred_language"],
        relations: [
          { to: "auth.users", type: "1:1", label: "One profile per login account" },
          { to: "teams", type: "N:1", label: "Each employee belongs to one team" },
          { to: "client_profiles", type: "1:1", label: "If role=client, has one extra client record" },
        ],
      },
      {
        name: "teams",
        plain: "A group of employees working together (like 'Design Team' or 'Dev Team'). Has a team lead who is also an employee. Tasks and custom tables can be scoped to a specific team.",
        fields: ["id", "name", "department", "team_lead_id → profiles", "is_active"],
        relations: [
          { to: "profiles", type: "1:N", label: "A team has many members" },
          { to: "profiles", type: "N:1", label: "Team lead is one of the profiles" },
        ],
      },
      {
        name: "client_profiles",
        plain: "Extra details about a client — company name, WhatsApp number, contract dates. Only exists for users whose role is 'client'. The WhatsApp number here is what the AI bot uses to match incoming messages to the right client account.",
        fields: ["id → profiles", "company_name", "contact_person", "whatsapp_number", "contract_start/end_date", "is_archived"],
        relations: [
          { to: "profiles", type: "1:1", label: "One client_profile per client user" },
          { to: "tasks", type: "1:N", label: "Client owns many tasks" },
          { to: "crm_entries", type: "1:N", label: "Client has many invoices" },
        ],
      },
    ],
  },
  {
    id: "calendar",
    label: "Calendar",
    color: "#10B981",
    bg: "#ECFDF5",
    icon: "📅",
    summary: "Events, meetings, room bookings, and file attachments.",
    tables: [
      {
        name: "events",
        plain: "Any entry on the calendar — a meeting, a deadline, a holiday, or a room booking. Can be linked to a client and can repeat on a schedule. The is_client_visible flag controls whether the client can see this event in their portal.",
        fields: ["id", "title", "event_type", "start_time / end_time", "client_id", "is_recurring", "recurrence_pattern (JSONB)", "is_client_visible", "status"],
        relations: [
          { to: "event_attendees", type: "1:N", label: "Event has many attendees" },
          { to: "event_attachments", type: "1:N", label: "Event can have file attachments" },
          { to: "client_profiles", type: "N:1", label: "Event may be linked to a client" },
          { to: "room_bookings", type: "1:1", label: "Room booking events link to a booking record" },
        ],
      },
      {
        name: "event_attendees",
        plain: "The bridge table connecting events to people. One row per person per event. Tracks whether they confirmed attendance and whether a notification was sent to them.",
        fields: ["id", "event_id → events", "profile_id → profiles", "is_confirmed", "notification_sent"],
        relations: [
          { to: "events", type: "N:1", label: "Many attendees belong to one event" },
          { to: "profiles", type: "N:1", label: "Each attendee is one profile" },
        ],
      },
      {
        name: "event_attachments",
        plain: "Files uploaded and linked to a calendar event — like a meeting agenda PDF or a presentation. The actual file sits in Supabase Storage; only the URL is saved here.",
        fields: ["id", "event_id → events", "file_name", "file_url (Storage path)", "file_type", "uploaded_by → profiles"],
        relations: [{ to: "events", type: "N:1", label: "Many files can attach to one event" }],
      },
      {
        name: "rooms",
        plain: "Physical meeting rooms or shared spaces that can be booked. Each room has a name, capacity, list of facilities (projector, whiteboard), and an hourly cost. When booked for a client, the cost is automatically sent to the Finance CRM.",
        fields: ["id", "name", "capacity", "facilities (text array)", "hourly_cost", "is_active"],
        relations: [{ to: "room_bookings", type: "1:N", label: "A room can have many bookings" }],
      },
      {
        name: "room_bookings",
        plain: "A specific reservation of a room. The UNIQUE constraint on (room_id + date + start_time) makes double-booking physically impossible at the database level. When a booking is made for a client, a trigger automatically creates a billable entry in the Finance CRM.",
        fields: ["id", "room_id → rooms", "booked_by → profiles", "client_id → client_profiles", "booking_date", "start_time / end_time", "total_cost", "crm_entry_created (flag)"],
        relations: [
          { to: "rooms", type: "N:1", label: "Many bookings for one room (different dates)" },
          { to: "client_profiles", type: "N:1", label: "Booking may be billed to a client" },
          { to: "crm_entries", type: "1:1", label: "Auto-creates one CRM billing entry via trigger" },
        ],
      },
    ],
  },
  {
    id: "tasks",
    label: "Tasks",
    color: "#8B5CF6",
    bg: "#F5F3FF",
    icon: "✅",
    summary: "Task boards, sub-tasks, dual-approval, comments, files, and the full audit trail.",
    tables: [
      {
        name: "task_boards",
        plain: "A workspace for a team's tasks — like a project folder. Each team can have multiple boards (e.g. 'Sprint Board', 'Bug Tracker', 'Client Projects'). Boards show tasks in a Kanban or list view.",
        fields: ["id", "team_id → teams", "name", "color", "icon", "created_by → profiles", "is_archived"],
        relations: [
          { to: "teams", type: "N:1", label: "Many boards belong to one team" },
          { to: "task_board_columns", type: "1:N", label: "Board has many status lanes" },
          { to: "tasks", type: "1:N", label: "Board holds many tasks" },
        ],
      },
      {
        name: "task_board_columns",
        plain: "The status lanes on a Kanban board — like 'To Do', 'In Progress', 'Review', 'Done'. Each board can have its own custom columns with custom names and colors. Tasks are dragged between these lanes.",
        fields: ["id", "board_id → task_boards", "name", "color", "position (display order)", "maps_to_status", "is_done_column"],
        relations: [{ to: "task_boards", type: "N:1", label: "Many columns belong to one board" }],
      },
      {
        name: "tasks",
        plain: "The core of the whole system. Every piece of work tracked in the app. A task can be a sub-task of another task (parent_task_id points to itself — this is called a self-referential relation). The cost field is admin-only — employees and clients physically cannot read it because of database-level security. When a task is approved by the client, a trigger automatically creates a billing entry in the Finance CRM.",
        fields: ["id", "title", "client_id → client_profiles", "team_id → teams", "parent_task_id → tasks (self)", "board_id → task_boards", "status", "priority", "due_date", "cost (admin only)", "completion_percentage"],
        relations: [
          { to: "tasks", type: "1:N", label: "Self-referential: a task can have many sub-tasks" },
          { to: "task_assignees", type: "1:N", label: "Task has many assigned employees" },
          { to: "task_mentions", type: "1:N", label: "Task can @mention many employees" },
          { to: "task_approvals", type: "1:1", label: "Each task has one approval record" },
          { to: "task_comments", type: "1:N", label: "Task has many comments" },
          { to: "task_attachments", type: "1:N", label: "Task has many file attachments" },
          { to: "task_audit_log", type: "1:N", label: "Every change to a task is logged" },
          { to: "crm_entries", type: "1:1", label: "On client approval → auto-creates CRM billing entry" },
        ],
      },
      {
        name: "task_assignees",
        plain: "The bridge table between tasks and the employees working on them. Multiple employees can be assigned to one task. One of them can be flagged as the lead. This is how the app knows whose task list to show to each employee.",
        fields: ["id", "task_id → tasks", "profile_id → profiles", "assigned_by → profiles", "is_lead"],
        relations: [
          { to: "tasks", type: "N:1", label: "Many assignees per task" },
          { to: "profiles", type: "N:1", label: "Each assignee is one employee profile" },
        ],
      },
      {
        name: "task_mentions",
        plain: "When someone types @name inside a task, a row is created here. The mentioned employee gets a notification and the task appears in their feed — even if they are not formally assigned to it.",
        fields: ["id", "task_id → tasks", "mentioned_profile_id → profiles", "mentioned_by → profiles", "notification_sent"],
        relations: [
          { to: "tasks", type: "N:1", label: "Many mentions per task" },
          { to: "profiles", type: "N:1", label: "Each mention points to one employee" },
        ],
      },
      {
        name: "task_approvals",
        plain: "The two-step completion record for every task. Step 1: the employee marks their work as done (employee_done_at is filled). Step 2: the client reviews and either approves or rejects. Both timestamps and who did each step are recorded. An admin can override the whole process with a reason note. There is exactly one approval record per task — the UNIQUE constraint guarantees this.",
        fields: ["id", "task_id → tasks (UNIQUE)", "employee_done_at", "employee_done_by", "client_reviewed_at", "client_decision (approved/rejected)", "client_rejection_reason", "admin_override_at", "admin_override_reason"],
        relations: [{ to: "tasks", type: "1:1", label: "One approval record per task" }],
      },
      {
        name: "task_comments",
        plain: "Messages left on a task by the team. is_internal = true means only employees and admin can see it. is_internal = false means the client can also see it in their portal. Comments can reply to other comments (parent_comment_id), creating threads.",
        fields: ["id", "task_id → tasks", "author_id → profiles", "content", "is_internal (true=team only, false=client can see)", "parent_comment_id → task_comments (self)"],
        relations: [
          { to: "tasks", type: "N:1", label: "Many comments per task" },
          { to: "task_comments", type: "1:N", label: "Self-referential: threaded replies" },
        ],
      },
      {
        name: "task_attachments",
        plain: "Files attached to a task. is_client_visible controls whether the client can download this file from their portal. The file itself is stored in Supabase Storage — only the URL is saved in this table.",
        fields: ["id", "task_id → tasks", "file_name", "file_url (Storage path)", "file_type", "file_size_bytes", "uploaded_by → profiles", "is_client_visible"],
        relations: [{ to: "tasks", type: "N:1", label: "Many files per task" }],
      },
      {
        name: "task_audit_log",
        plain: "A permanent, unchangeable history of everything that ever happened to a task. Every status change, assignment, comment, file upload, and cost edit creates a new row here. Nobody can delete or edit these rows — not even admin. This table is append-only by design.",
        fields: ["id", "task_id → tasks", "actor_id → profiles", "action (text label)", "old_value (JSONB)", "new_value (JSONB)", "created_at"],
        relations: [{ to: "tasks", type: "N:1", label: "Many log entries per task" }],
      },
    ],
  },
  {
    id: "finance",
    label: "Finance CRM",
    color: "#F59E0B",
    bg: "#FFFBEB",
    icon: "💰",
    summary: "Client invoices, payments, daily expenses, and employee deductions.",
    tables: [
      {
        name: "crm_entries",
        plain: "Every billable item for every client — whether it came from a completed task, a room booking, a meeting, or was added manually by admin. This table is the heart of the Finance CRM. Two triggers automatically insert rows here: one when a task is client-approved, another when a room is booked for a client — so admin never needs to enter this data manually.",
        fields: ["id", "client_id → client_profiles", "source_type (task/room_booking/meeting/manual)", "source_id (points to the task or booking)", "title", "amount", "status (unpaid/partial/paid/overdue)", "due_date", "paid_amount", "invoice_number"],
        relations: [
          { to: "client_profiles", type: "N:1", label: "Many invoices belong to one client" },
          { to: "crm_payments", type: "1:N", label: "One invoice can have many payment transactions" },
          { to: "tasks", type: "N:1", label: "Auto-created from completed tasks" },
          { to: "room_bookings", type: "N:1", label: "Auto-created from room bookings" },
        ],
      },
      {
        name: "crm_payments",
        plain: "Each time a client pays — even a partial payment — a row is added here. A trigger on this table automatically recalculates the total paid amount and updates the status of the parent crm_entry (unpaid → partial → paid).",
        fields: ["id", "crm_entry_id → crm_entries", "client_id → client_profiles", "amount_paid", "payment_date", "payment_method", "reference_number", "recorded_by → profiles"],
        relations: [{ to: "crm_entries", type: "N:1", label: "Many payments can apply to one invoice" }],
      },
      {
        name: "expenses",
        plain: "Daily company costs — rent, utilities, salaries, supplies, anything the company spends money on. Only admin can see and add these. Receipts are stored as files in Supabase Storage. The category links to expense_categories where monthly budget limits are configured.",
        fields: ["id", "expense_date", "category_id → expense_categories", "amount", "description", "receipt_url (Storage)", "payment_method", "paid_to", "recorded_by → profiles"],
        relations: [{ to: "expense_categories", type: "N:1", label: "Each expense belongs to one category" }],
      },
      {
        name: "expense_categories",
        plain: "The list of spending categories: Rent, Utilities, Salaries, Software, etc. Admin can add or rename categories. Each category can have a monthly budget limit — if spending approaches or passes that limit, an alert is triggered.",
        fields: ["id", "name (UNIQUE)", "description", "monthly_budget_limit", "is_active"],
        relations: [{ to: "expenses", type: "1:N", label: "Category groups many expenses" }],
      },
      {
        name: "penalties",
        plain: "Deduction records for employees — when an employee is late, absent, or violates a policy, admin creates a row here. The employee has absolutely no access to this table. The is_applied flag tracks whether the deduction has been processed. Linked to penalty_types which defines the category and default amount.",
        fields: ["id", "employee_id → profiles", "penalty_type_id → penalty_types", "penalty_date", "amount", "reason", "approved_by → profiles", "is_applied"],
        relations: [
          { to: "profiles", type: "N:1", label: "Many penalties can apply to one employee" },
          { to: "penalty_types", type: "N:1", label: "Each penalty has a type category" },
        ],
      },
      {
        name: "penalty_types",
        plain: "Predefined categories of violations — like 'Late Attendance', 'Unauthorized Absence', 'Policy Violation'. Each type has a default deduction amount that admin can override per case. Admin configures these in the Settings module.",
        fields: ["id", "name (UNIQUE)", "description", "default_amount", "is_active"],
        relations: [{ to: "penalties", type: "1:N", label: "One type applies to many penalty records" }],
      },
    ],
  },
  {
    id: "attendance",
    label: "Attendance",
    color: "#14B8A6",
    bg: "#F0FDFA",
    icon: "🕐",
    summary: "Daily check-in and check-out for every employee.",
    tables: [
      {
        name: "attendance",
        plain: "One row per employee per day. The UNIQUE constraint on (employee_id + attendance_date) makes it impossible to have two records for the same employee on the same day. When the employee taps Check Out, a trigger automatically calculates total_hours. Admin can override any record and leave a note explaining why.",
        fields: ["id", "employee_id → profiles", "attendance_date (UNIQUE per employee)", "check_in_time", "check_out_time", "check_in_location (JSONB with lat/lng)", "status (present/absent/late/half_day)", "total_hours (auto-calculated)", "is_overridden", "override_reason", "overridden_by → profiles"],
        relations: [{ to: "profiles", type: "N:1", label: "Many attendance records per employee (one per day)" }],
      },
    ],
  },
  {
    id: "dynamic",
    label: "Custom Tables",
    color: "#EC4899",
    bg: "#FDF2F8",
    icon: "🗂️",
    summary: "Flexible user-defined tables that work like Notion/Airtable — fully customizable columns and rows.",
    tables: [
      {
        name: "custom_tables",
        plain: "A user-created table or board — like a spreadsheet that admin or team leads define themselves. Can be scoped to a specific team or linked to a client project. Think of it as the container that holds columns and rows.",
        fields: ["id", "name", "icon", "color", "team_id → teams", "client_id → client_profiles", "created_by → profiles", "is_archived"],
        relations: [
          { to: "custom_columns", type: "1:N", label: "Table has many columns (its structure)" },
          { to: "custom_rows", type: "1:N", label: "Table has many rows (its data)" },
          { to: "table_views", type: "1:N", label: "Table can have multiple saved views" },
          { to: "table_permissions", type: "1:N", label: "Table has permission grants per team/user" },
        ],
      },
      {
        name: "custom_columns",
        plain: "A column definition inside a custom table. The field_type determines what kind of data it holds (text, number, date, status, person, file, etc.). The config JSONB stores type-specific settings — for example, a currency column stores the currency symbol; a person column stores whether multiple people can be selected. Column-level visibility flags let admin mark certain columns as hidden from employees or clients.",
        fields: ["id", "table_id → custom_tables", "name", "field_type (text/number/date/status/person/file/...)", "position (display order)", "is_required", "is_admin_only", "is_hidden_from_client", "config (JSONB settings per type)"],
        relations: [
          { to: "custom_tables", type: "N:1", label: "Many columns belong to one table" },
          { to: "column_status_options", type: "1:N", label: "Status columns have their own choice options" },
          { to: "custom_cell_values", type: "1:N", label: "Column appears in many cells across rows" },
        ],
      },
      {
        name: "column_status_options",
        plain: "The dropdown choices for a status-type column. Each column has its own completely independent set of options with custom labels and colors. For example, one column might have 'Not Started / In Progress / Done', while another has 'Pending / Approved / Rejected / On Hold'. When a label or color is changed, a trigger automatically updates all cells that reference that option.",
        fields: ["id", "column_id → custom_columns", "label", "color (hex)", "position (display order)", "is_default"],
        relations: [{ to: "custom_columns", type: "N:1", label: "Many options per status column" }],
      },
      {
        name: "custom_rows",
        plain: "One record (row) in a custom table — like a row in a spreadsheet. Can optionally be linked to an existing task or a client, creating a connection between the custom table and the core system. Rows have a position for drag-and-drop reordering.",
        fields: ["id", "table_id → custom_tables", "created_by → profiles", "position (display order)", "linked_task_id → tasks", "linked_client_id → client_profiles", "is_archived"],
        relations: [
          { to: "custom_tables", type: "N:1", label: "Many rows belong to one table" },
          { to: "custom_cell_values", type: "1:N", label: "Row has one cell value per column" },
          { to: "tasks", type: "N:1", label: "Row can be linked to a task" },
        ],
      },
      {
        name: "custom_cell_values",
        plain: "The actual data inside each cell. One row per (table row × column) intersection — like a grid. The table has seven typed value columns (value_text, value_number, value_date, value_boolean, value_jsonb, etc.) but only the one matching the column's field_type is filled; the rest stay NULL. The UNIQUE(row_id, column_id) constraint means there can only ever be one cell per column per row. Every edit is logged to cell_audit_log by a trigger.",
        fields: ["id", "row_id → custom_rows", "column_id → custom_columns (UNIQUE together)", "value_text", "value_number", "value_date / value_date_end", "value_boolean", "value_jsonb (person/file/status/formula/link)", "last_edited_by → profiles"],
        relations: [
          { to: "custom_rows", type: "N:1", label: "Many cells per row (one per column)" },
          { to: "custom_columns", type: "N:1", label: "Cell belongs to one column definition" },
          { to: "cell_audit_log", type: "1:N", label: "Every edit creates an audit log entry" },
        ],
      },
      {
        name: "table_views",
        plain: "A saved view configuration for a table. One table can have multiple views — a List view, a Kanban view grouped by status column, a Calendar view grouped by date column. Each view stores its own sort order, active filters, hidden columns, and column widths independently.",
        fields: ["id", "table_id → custom_tables", "name", "view_type (list/kanban/calendar/gallery)", "is_default", "group_by_column_id → custom_columns", "sort_config (JSONB)", "filter_config (JSONB)", "hidden_column_ids (array)", "column_widths (JSONB)"],
        relations: [{ to: "custom_tables", type: "N:1", label: "Many views per table" }],
      },
      {
        name: "table_permissions",
        plain: "Controls who can do what in a custom table. A grant can apply to an entire team, a specific person, or a specific client. Each grant has individual toggles for: can view / can add rows / can edit rows / can delete rows / can manage columns (add, rename, delete). This lets team leads share a table with another team in read-only mode, or give a client view access without edit rights.",
        fields: ["id", "table_id → custom_tables", "grantee_type (team/profile/client)", "grantee_id (UUID of team, profile, or client)", "can_view", "can_add_rows", "can_edit_rows", "can_delete_rows", "can_manage_columns", "granted_by → profiles"],
        relations: [{ to: "custom_tables", type: "N:1", label: "Many permission grants per table" }],
      },
      {
        name: "cell_audit_log",
        plain: "A permanent record of every cell edit. Old value and new value are both stored as JSONB snapshots. Nobody can delete or update these records — they are append-only by design. A trigger on custom_cell_values creates a log entry automatically on every update.",
        fields: ["id", "cell_id → custom_cell_values", "row_id → custom_rows", "column_id → custom_columns", "actor_id → profiles", "old_value (JSONB)", "new_value (JSONB)", "created_at"],
        relations: [{ to: "custom_cell_values", type: "N:1", label: "Many log entries per cell" }],
      },
    ],
  },
  {
    id: "ai",
    label: "AI & Notifications",
    color: "#EF4444",
    bg: "#FEF2F2",
    icon: "🤖",
    summary: "WhatsApp AI interactions and in-app / push notifications.",
    tables: [
      {
        name: "ai_interactions",
        plain: "A complete log of every WhatsApp message the AI bot receives and responds to. Stores the incoming message, what intent the AI detected, what data was sent to Ollama as context, the AI's response, and any action it took (like approving a task). If the AI is not confident enough, it escalates the conversation to a human admin. Every interaction is logged and the escalated_to field shows which admin picked it up.",
        fields: ["id", "client_id → client_profiles", "whatsapp_number", "incoming_message", "detected_intent", "context_data (JSONB sent to Ollama)", "ai_response", "action_taken", "action_reference_id (task/event acted on)", "was_escalated", "escalated_to → profiles", "n8n_execution_id", "model_used"],
        relations: [{ to: "client_profiles", type: "N:1", label: "Many AI interactions per client" }],
      },
      {
        name: "notifications",
        plain: "Every notification sent to any user through any channel — in-app bell, push notification, WhatsApp, or email. The Flutter app subscribes to this table via Supabase Realtime, so new rows appear instantly in the app without needing to refresh. The reference_type and reference_id columns point to what the notification is about (a task, an event, or a CRM entry).",
        fields: ["id", "recipient_id → profiles", "type (task_assigned/payment_due/...)", "title", "body", "reference_type (task/event/crm_entry)", "reference_id (UUID of the thing)", "is_read", "channel (in_app/push/whatsapp/email)", "sent_at"],
        relations: [{ to: "profiles", type: "N:1", label: "Many notifications per user" }],
      },
    ],
  },
];

const REL_COLORS = { "1:1": "#8B5CF6", "1:N": "#3B82F6", "N:1": "#10B981", "N:M": "#F59E0B" };
const REL_LABELS = { "1:1": "One-to-One", "1:N": "One-to-Many", "N:1": "Many-to-One", "N:M": "Many-to-Many" };

export default function App() {
  const [activeModule, setActiveModule] = useState("auth");
  const [activeTable, setActiveTable] = useState(null);
  const [search, setSearch] = useState("");

  const mod = MODULES.find(m => m.id === activeModule);

  const allTables = MODULES.flatMap(m => m.tables.map(t => ({ ...t, module: m })));
  const searchResults = search.length > 1
    ? allTables.filter(t =>
        t.name.toLowerCase().includes(search.toLowerCase()) ||
        t.plain.toLowerCase().includes(search.toLowerCase())
      )
    : [];

  const selectedTable = activeTable
    ? mod?.tables.find(t => t.name === activeTable) || null
    : null;

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", background: "#F8FAFC", minHeight: "100vh", color: "#1E293B" }}>

      {/* Header */}
      <div style={{ background: "#0F172A", color: "#fff", padding: "20px 24px 16px" }}>
        <div style={{ fontSize: 20, fontWeight: 700, marginBottom: 4 }}>🗄️ Database Guide</div>
        <div style={{ fontSize: 13, color: "#94A3B8" }}>
          All tables explained in plain language · {allTables.length} tables · 7 modules
        </div>

        {/* Search */}
        <div style={{ marginTop: 14, position: "relative" }}>
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setActiveTable(null); }}
            placeholder="Search any table or description..."
            style={{
              width: "100%", padding: "9px 14px", borderRadius: 10,
              border: "1.5px solid #334155", background: "#1E293B",
              color: "#E2E8F0", fontSize: 13, outline: "none", boxSizing: "border-box"
            }}
          />
          {search && (
            <button onClick={() => setSearch("")}
              style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)",
                background: "none", border: "none", color: "#64748B", cursor: "pointer", fontSize: 16 }}>×</button>
          )}
        </div>

        {/* Search results */}
        {searchResults.length > 0 && (
          <div style={{ marginTop: 8, background: "#1E293B", borderRadius: 10, overflow: "hidden",
            border: "1px solid #334155", maxHeight: 220, overflowY: "auto" }}>
            {searchResults.map(t => (
              <div key={t.name}
                onClick={() => { setActiveModule(t.module.id); setActiveTable(t.name); setSearch(""); }}
                style={{ padding: "10px 14px", cursor: "pointer", borderBottom: "1px solid #334155",
                  display: "flex", alignItems: "center", gap: 10 }}>
                <span style={{ fontSize: 16 }}>{t.module.icon}</span>
                <div>
                  <div style={{ fontFamily: "monospace", fontSize: 13, color: "#7DD3FC", fontWeight: 600 }}>{t.name}</div>
                  <div style={{ fontSize: 11, color: "#64748B", marginTop: 2 }}>{t.module.label}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Module tabs */}
      <div style={{ background: "#fff", borderBottom: "1px solid #E2E8F0",
        display: "flex", overflowX: "auto", gap: 0 }}>
        {MODULES.map(m => (
          <button key={m.id}
            onClick={() => { setActiveModule(m.id); setActiveTable(null); }}
            style={{
              padding: "11px 16px", border: "none", background: "none", cursor: "pointer",
              fontSize: 12, fontWeight: 600, whiteSpace: "nowrap", flexShrink: 0,
              color: activeModule === m.id ? m.color : "#64748B",
              borderBottom: activeModule === m.id ? `2.5px solid ${m.color}` : "2.5px solid transparent",
              transition: "all 0.15s"
            }}>
            {m.icon} {m.label}
          </button>
        ))}
      </div>

      {/* Module summary */}
      {mod && (
        <div style={{ padding: "14px 20px 0", display: "flex", alignItems: "center", gap: 10 }}>
          <span style={{ fontSize: 24 }}>{mod.icon}</span>
          <div>
            <div style={{ fontWeight: 700, fontSize: 16, color: mod.color }}>{mod.label} Module</div>
            <div style={{ fontSize: 13, color: "#64748B" }}>{mod.summary}</div>
          </div>
        </div>
      )}

      {/* Legend */}
      <div style={{ padding: "12px 20px 8px", display: "flex", gap: 14, flexWrap: "wrap" }}>
        {Object.entries(REL_COLORS).map(([type, color]) => (
          <div key={type} style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11 }}>
            <div style={{ width: 28, height: 3, background: color, borderRadius: 2 }} />
            <span style={{ color: "#64748B" }}><strong style={{ color }}>{type}</strong> {REL_LABELS[type]}</span>
          </div>
        ))}
      </div>

      {/* Body */}
      <div style={{ padding: "0 16px 32px", display: "flex", gap: 16, alignItems: "flex-start" }}>

        {/* Table list */}
        <div style={{ width: 220, flexShrink: 0 }}>
          {mod?.tables.map(t => (
            <div key={t.name}
              onClick={() => setActiveTable(activeTable === t.name ? null : t.name)}
              style={{
                marginTop: 10, padding: "10px 12px", borderRadius: 10, cursor: "pointer",
                background: activeTable === t.name ? mod.color : "#fff",
                color: activeTable === t.name ? "#fff" : "#1E293B",
                border: `1.5px solid ${activeTable === t.name ? mod.color : "#E2E8F0"}`,
                boxShadow: activeTable === t.name ? `0 4px 14px ${mod.color}33` : "none",
                transition: "all 0.15s"
              }}>
              {t.managed && (
                <div style={{ fontSize: 9, fontWeight: 700, textTransform: "uppercase",
                  letterSpacing: "0.06em", marginBottom: 3,
                  color: activeTable === t.name ? "rgba(255,255,255,0.7)" : "#94A3B8" }}>
                  Managed by Supabase
                </div>
              )}
              <div style={{ fontFamily: "monospace", fontSize: 12, fontWeight: 700 }}>{t.name}</div>
              <div style={{ fontSize: 11, marginTop: 3, opacity: 0.75, lineHeight: 1.4 }}>
                {t.relations.length} relationship{t.relations.length !== 1 ? "s" : ""}
              </div>
            </div>
          ))}
        </div>

        {/* Detail panel */}
        <div style={{ flex: 1, minWidth: 0 }}>
          {!selectedTable ? (
            <div style={{ marginTop: 10, background: "#fff", borderRadius: 14,
              border: "1.5px solid #E2E8F0", padding: "28px 24px", textAlign: "center", color: "#94A3B8" }}>
              <div style={{ fontSize: 36, marginBottom: 10 }}>👈</div>
              <div style={{ fontSize: 15, fontWeight: 600, color: "#64748B" }}>Select a table to see its full description</div>
              <div style={{ fontSize: 13, marginTop: 6 }}>
                {mod?.tables.length} tables in the {mod?.label} module
              </div>
              {/* Mini overview cards */}
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(180px,1fr))", gap: 10, marginTop: 20, textAlign: "left" }}>
                {mod?.tables.map(t => (
                  <div key={t.name} onClick={() => setActiveTable(t.name)}
                    style={{ padding: "10px 12px", borderRadius: 10, background: mod.bg,
                      border: `1px solid ${mod.color}33`, cursor: "pointer" }}>
                    <div style={{ fontFamily: "monospace", fontSize: 11, fontWeight: 700, color: mod.color }}>{t.name}</div>
                    <div style={{ fontSize: 11, color: "#64748B", marginTop: 4, lineHeight: 1.4 }}>
                      {t.plain.slice(0, 70)}…
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div style={{ marginTop: 10, background: "#fff", borderRadius: 14,
              border: `1.5px solid ${mod.color}55`, padding: "22px 22px 28px" }}>

              {/* Table header */}
              <div style={{ display: "flex", alignItems: "flex-start", gap: 14, marginBottom: 18 }}>
                <div style={{ width: 48, height: 48, borderRadius: 12, background: mod.bg,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 22, flexShrink: 0 }}>{mod.icon}</div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontFamily: "monospace", fontSize: 18, fontWeight: 800, color: mod.color }}>
                    {selectedTable.name}
                  </div>
                  <div style={{ fontSize: 11, color: "#94A3B8", marginTop: 2 }}>
                    {mod.label} Module · {selectedTable.relations.length} relationships
                  </div>
                </div>
                <button onClick={() => setActiveTable(null)}
                  style={{ background: "#F1F5F9", border: "none", borderRadius: 8,
                    padding: "6px 12px", cursor: "pointer", fontSize: 12, color: "#64748B" }}>
                  Close ×
                </button>
              </div>

              {/* Plain description */}
              <div style={{ background: mod.bg, borderRadius: 12, padding: "14px 16px",
                borderLeft: `4px solid ${mod.color}`, marginBottom: 22 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: mod.color, textTransform: "uppercase",
                  letterSpacing: "0.06em", marginBottom: 7 }}>📖 What this table stores</div>
                <div style={{ fontSize: 13.5, lineHeight: 1.75, color: "#334155" }}>
                  {selectedTable.plain}
                </div>
              </div>

              {/* Fields */}
              <div style={{ marginBottom: 22 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: "#64748B", textTransform: "uppercase",
                  letterSpacing: "0.06em", marginBottom: 10 }}>🔧 Key Columns</div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 7 }}>
                  {selectedTable.fields.map(f => (
                    <div key={f} style={{ padding: "5px 10px", borderRadius: 7,
                      background: "#F8FAFC", border: "1px solid #E2E8F0",
                      fontFamily: "monospace", fontSize: 11, color: "#475569" }}>
                      {f}
                    </div>
                  ))}
                </div>
              </div>

              {/* Relationships */}
              <div>
                <div style={{ fontSize: 11, fontWeight: 700, color: "#64748B", textTransform: "uppercase",
                  letterSpacing: "0.06em", marginBottom: 10 }}>🔗 Relationships</div>
                <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
                  {selectedTable.relations.map((r, i) => (
                    <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 12,
                      padding: "11px 14px", borderRadius: 10, background: "#F8FAFC",
                      border: `1.5px solid ${REL_COLORS[r.type]}33` }}>
                      <div style={{ padding: "3px 9px", borderRadius: 6, background: REL_COLORS[r.type],
                        color: "#fff", fontWeight: 800, fontSize: 11, flexShrink: 0, letterSpacing: "0.02em" }}>
                        {r.type}
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                          <span style={{ fontFamily: "monospace", fontSize: 12, fontWeight: 700, color: mod.color }}>
                            {selectedTable.name}
                          </span>
                          <span style={{ fontSize: 16, color: REL_COLORS[r.type] }}>→</span>
                          <span style={{ fontFamily: "monospace", fontSize: 12, fontWeight: 700, color: "#1E293B" }}>
                            {r.to}
                          </span>
                        </div>
                        <div style={{ fontSize: 12.5, color: "#64748B", marginTop: 4, lineHeight: 1.5 }}>
                          {r.label}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Bottom stats bar */}
      <div style={{ position: "sticky", bottom: 0, background: "#0F172A", color: "#94A3B8",
        padding: "10px 20px", display: "flex", gap: 20, fontSize: 12, flexWrap: "wrap" }}>
        <span>📊 <strong style={{ color: "#fff" }}>{allTables.length}</strong> Total Tables</span>
        <span>🔗 <strong style={{ color: "#fff" }}>40+</strong> FK Relations</span>
        <span>🛡️ <strong style={{ color: "#fff" }}>30+</strong> RLS Policies</span>
        <span>⚡ <strong style={{ color: "#fff" }}>8</strong> Auto-Triggers</span>
        <span>👁️ <strong style={{ color: "#fff" }}>3</strong> Security Views</span>
        <span style={{ marginLeft: "auto" }}>Click any table in the list to explore →</span>
      </div>
    </div>
  );
}
