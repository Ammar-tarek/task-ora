// lib/core/repositories/client_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/calendar/start_reminder_offsets.dart';
import '../services/privileged_ops.dart';
import '../services/supabase_service.dart';
import '../models/client_model.dart';
import '../models/task_model.dart';
import 'finance_repository.dart';

/// Thrown when a Studio room booking cannot be saved because its time range
/// overlaps an existing (non-cancelled) Studio booking. Surfaced from the DB
/// exclusion constraint `events_studio_booking_no_overlap` (SQLSTATE 23P01) so
/// the UI can show a clear "already booked" message instead of failing silently.
class BookingConflictException implements Exception {
  const BookingConflictException([
    this.message = 'That time slot is already booked.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class CalEventData {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? clientId;
  final String? clientName;
  final String? description;
  final String? link;
  final double? cost;
  final List<String> attendeeNames;
  final List<String> attendeeIds;
  final String? roomName;
  final String status;
  final double? shootingHours;
  final double? finalVideoDuration;

  /// Owning department team (events.team_id). Null for legacy/unassigned events.
  final String? teamId;

  const CalEventData({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.clientId,
    this.clientName,
    this.description,
    this.link,
    this.cost,
    this.attendeeNames = const [],
    this.attendeeIds = const [],
    this.roomName,
    this.status = 'pending',
    this.shootingHours,
    this.finalVideoDuration,
    this.teamId,
  });

  factory CalEventData.fromMap(Map<String, dynamic> m) {
    final client = m['client'] as Map<String, dynamic>?;
    final attendees = (m['event_attendees'] as List<dynamic>? ?? []);
    return CalEventData(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      start:
          DateTime.tryParse(m['start_time'] as String? ?? '') ?? DateTime.now(),
      end: DateTime.tryParse(m['end_time'] as String? ?? '') ?? DateTime.now(),
      clientId: m['client_id'] as String?,
      clientName: client?['company_name'] as String?,
      description: m['description'] as String?,
      link: m['link'] as String?,
      cost: (m['cost'] as num?)?.toDouble(),
      roomName: m['location'] as String?,
      status: m['status'] as String? ?? 'pending',
      teamId: m['team_id'] as String?,
      shootingHours: (m['shooting_hours'] as num?)?.toDouble(),
      finalVideoDuration: (m['final_video_duration'] as num?)?.toDouble(),
      attendeeNames: attendees
          .map((a) {
            final p = a['profile'] as Map<String, dynamic>?;
            return p?['full_name'] as String? ?? '';
          })
          .where((n) => n.isNotEmpty)
          .toList(),
      attendeeIds: attendees
          .map(
            (a) => (a as Map<String, dynamic>)['profile_id'] as String? ?? '',
          )
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

class ClientRepository {
  static final _db = SupabaseService.client;

  /// Kept for call-site compatibility. Returns the authenticated RLS client
  /// (no longer a service-role client); callers run under their own policies.
  static SupabaseClient get adminDb => _db;

  static Future<List<ClientModel>> fetchClients({String? clientType}) async {
    try {
      // B2: RLS-enforced client list — admin: all; manager: own team's clients;
      // client: self. (Was service-role, which returned every client to a
      // manager — a cross-department client-list exposure.)
      var query = _db.from('client_profiles').select();
      if (clientType != null && clientType.isNotEmpty && clientType != 'both') {
        // Client belongs to this department OR to both departments.
        query = query.or('client_type.eq.$clientType,client_type.eq.both');
      }
      final data = await query.order('company_name');
      return (data as List).map((m) => ClientModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<ClientModel?> fetchClientById(String id) async {
    try {
      // RLS client: client self, manager's team clients, or admin. Blocks
      // loading another department's client by id.
      final data = await _db
          .from('client_profiles')
          .select()
          .eq('id', id)
          .single();
      return ClientModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// [profileId] must be an existing profiles.id with role=client (FK constraint).
  static Future<ClientModel?> createClient({
    required String profileId,
    required String companyName,
    required String contactPerson,
    required String email,
    String? phone,
    String? whatsappNumber,
    String? address,
    String? notes,
  }) async {
    try {
      final data = await _db
          .from('client_profiles')
          .insert({
            'id': profileId,
            'company_name': companyName,
            'contact_person': contactPerson,
            'email': email,
            'phone': phone,
            'whatsapp_number': whatsappNumber,
            'address': address,
            'notes': notes,
          })
          .select()
          .single();
      return ClientModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Creates auth user + profile + client_profile in one call.
  /// Returns the new [ClientModel] or null on failure.
  /// [error] is set to a human-readable message when it fails.
  static Future<({ClientModel? client, String? error})>
  createClientWithAccount({
    required String fullName,
    required String email,
    required String password,
    required String companyName,
    required String contactPerson,
    String? phone,
    String? whatsappNumber,
    String? address,
    String? notes,
    String? clientType,
  }) async {
    try {
      // 1. Create the auth user + profile server-side (admin-gated Edge Fn).
      final userId = await PrivilegedOps.createUser(
        email: email,
        password: password,
        fullName: fullName,
        role: 'client',
      );
      if (userId == null) {
        return (client: null, error: 'Failed to create user account');
      }

      // 2. Insert/Upsert client_profiles row (RLS: admin/manager write).
      final data = await _db
          .from('client_profiles')
          .upsert({
            'id': userId,
            'company_name': companyName,
            'contact_person': contactPerson,
            'email': email,
            'phone': phone,
            'whatsapp_number': whatsappNumber,
            'address': address,
            'notes': notes,
            if (clientType != null && clientType.isNotEmpty)
              'client_type': clientType,
          })
          .select()
          .single();

      return (client: ClientModel.fromMap(data), error: null);
    } on AuthException catch (e) {
      return (client: null, error: e.message);
    } catch (e) {
      return (client: null, error: e.toString());
    }
  }

  /// Updates company details + optionally changes email / password via admin API.
  /// Pass [newPassword] only when the admin wants to reset the password.
  /// Pass [newEmail] only when the email should change.
  static Future<({ClientModel? client, String? error})>
  updateClientWithAccount({
    required String clientId,
    required String fullName,
    required String email,
    required String companyName,
    required String contactPerson,
    String? phone,
    String? whatsappNumber,
    String? address,
    String? notes,
    String? newEmail,
    String? newPassword,
    String? clientType,
  }) async {
    try {
      // 1. Auth change (email/password) + profile full_name via the admin-gated
      //    Edge Function (no service-role key on the client).
      final changeEmail =
          (newEmail != null && newEmail.isNotEmpty && newEmail != email)
          ? newEmail
          : null;
      final changePassword = (newPassword != null && newPassword.isNotEmpty)
          ? newPassword
          : null;
      await PrivilegedOps.updateUser(
        userId: clientId,
        email: changeEmail,
        password: changePassword,
        fullName: fullName,
      );

      // 3. Update client_profiles
      final effectiveEmail = (newEmail != null && newEmail.isNotEmpty)
          ? newEmail
          : email;
      final data = await _db
          .from('client_profiles')
          .update({
            'company_name': companyName,
            'contact_person': contactPerson,
            'email': effectiveEmail,
            'phone': phone,
            'whatsapp_number': whatsappNumber,
            'address': address,
            'notes': notes,
            if (clientType != null && clientType.isNotEmpty)
              'client_type': clientType,
          })
          .eq('id', clientId)
          .select()
          .single();

      return (client: ClientModel.fromMap(data), error: null);
    } on AuthException catch (e) {
      return (client: null, error: e.message);
    } catch (e) {
      return (client: null, error: e.toString());
    }
  }

  /// Returns profiles with role=client that don't have a client_profiles row yet.
  static Future<List<Map<String, String>>> fetchUnlinkedClientProfiles() async {
    try {
      final linked = await _db.from('client_profiles').select('id');
      final linkedIds = (linked as List).map((r) => r['id'] as String).toList();

      final all = await _db
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'client');

      return (all as List)
          .where((r) => !linkedIds.contains(r['id'] as String))
          .map(
            (r) => {
              'id': r['id'] as String,
              'full_name': r['full_name'] as String? ?? '',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch a client's tasks.
  ///
  /// When [asClient] is true (the client viewing their own portal), tasks
  /// flagged `hidden_from_client` are excluded. Staff/admin pass false and
  /// see every task, including hidden ones.
  static Future<List<TaskModel>> fetchClientTasks(
    String clientId, {
    bool asClient = false,
  }) async {
    try {
      var q = _db
          .from('tasks')
          .select(
            '*, client:client_profiles(company_name), task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name)), task_comments(id, content, is_internal, created_at, author:profiles!task_comments_author_id_fkey(full_name))',
          )
          .eq('client_id', clientId);
      if (asClient) q = q.eq('hidden_from_client', false);
      final data = await q.order('created_at', ascending: false);
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        var q = _db
            .from('tasks')
            .select(
              '*, client:client_profiles(company_name), task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name))',
            )
            .eq('client_id', clientId);
        if (asClient) q = q.eq('hidden_from_client', false);
        final data = await q.order('created_at', ascending: false);
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<List<CalEventData>> fetchAllEvents() async {
    try {
      final data = await _db
          .from('events')
          .select(
            '*, client:client_profiles(company_name), event_attendees(profile_id, profile:profiles(full_name))',
          )
          .order('start_time', ascending: true);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Events the given profile is an attendee of, with the FULL attendee list
  /// for each event preserved. Used to restrict the calendar for employees and
  /// managers to only the events assigned to them.
  static Future<List<CalEventData>> fetchMyEvents(String profileId) async {
    try {
      final links = await _db
          .from('event_attendees')
          .select('event_id')
          .eq('profile_id', profileId);
      final ids = (links as List)
          .map((r) => (r as Map<String, dynamic>)['event_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (ids.isEmpty) return [];

      final data = await _db
          .from('events')
          .select(
            '*, client:client_profiles(company_name), event_attendees(profile_id, profile:profiles(full_name))',
          )
          .inFilter('id', ids)
          .order('start_time', ascending: true);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Department-aware calendar fetch. Row visibility is enforced ENTIRELY by
  /// the database RLS policies on `events` (the UI is never the security
  /// boundary):
  ///   • admin        → every event (optionally narrowed to [scopedTeamId]);
  ///   • manager      → their department's events + events they own/attend;
  ///   • employee     → their department's shared events + events they attend;
  ///   • client       → only their own client-visible events.
  ///
  /// [scopedTeamId] is an ADMIN-only department filter (the active workspace):
  ///   • null                 → no extra filter (All Departments for an admin;
  ///                             RLS-scoped set for everyone else);
  ///   • a real team id       → only that department's events;
  ///   • noTeamSentinel id    → matches nothing (a department with no backing
  ///                             team), so a department view never leaks others.
  /// Unassigned legacy events (team_id IS NULL) are therefore only ever
  /// returned to an admin viewing "All Departments" — never to a scoped filter
  /// and never to ordinary department users (NULL never equals my_team_id()).
  static Future<List<CalEventData>> fetchDepartmentEvents({
    String? scopedTeamId,
  }) async {
    try {
      final base = _db
          .from('events')
          .select(
            '*, client:client_profiles(company_name), event_attendees(profile_id, profile:profiles(full_name))',
          );
      final query = scopedTeamId != null
          ? base.eq('team_id', scopedTeamId)
          : base;
      final data = await query.order('start_time', ascending: true);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Events belonging to a specific client (RLS additionally restricts a client
  /// to their own `is_client_visible` rows). This is the client-specific
  /// calendar path — clients are never routed through the department-wide fetch.
  static Future<List<CalEventData>> fetchClientEvents(String clientId) async {
    try {
      final data = await _db
          .from('events')
          .select(
            '*, client:client_profiles(company_name), event_attendees(profile_id, profile:profiles(full_name))',
          )
          .eq('client_id', clientId)
          .order('start_time', ascending: false);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<CrmEntry>> fetchClientCrmEntries(String clientId) async {
    try {
      final data = await _db
          .from('crm_entries')
          .select('*, client:client_profiles(company_name)')
          .eq('client_id', clientId)
          .order('created_at', ascending: false);
      return (data as List).map((m) => CrmEntry.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save a new event (simplified form): title, department (team_id), optional
  /// client, start/end, description, and link. Department-created notifications
  /// are handled SERVER-SIDE by the `notify_event_created` trigger (fans out to
  /// the owning department via team_id and pushes via FCM) — no client-side
  /// notify here, which avoids double-sends. event_type is left to the column
  /// default; attendees/cost/room are no longer part of the form.
  /// Returns the new event id (or null on failure), so callers can attach
  /// start-reminder offsets to it. Behaviour is otherwise unchanged.
  static Future<String?> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    required String createdBy,
    String? clientId,
    String? description,
    String? link,
    String? teamId,
  }) async {
    try {
      final res = await _db.from('events').insert({
        'title': title,
        'start_time': start.toIso8601String(),
        'end_time': end.toIso8601String(),
        'client_id': clientId,
        'description': description,
        'link': link,
        'created_by': createdBy,
        'team_id': teamId,
      }).select('id').single();
      return res['id'] as String?;
    } on PostgrestException catch (e) {
      if (e.code == '23P01') throw const BookingConflictException();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Event start-reminder offsets (Phase 1) ──────────────────────────────────
  // Depends on PROPOSED_phase1_event_start_reminders.sql (not yet applied).
  // RLS lets the event's department manager/admin write; anyone may read.

  /// Load an event's start-reminder offsets. Returns a [ReminderLoadResult] so
  /// callers can tell a real empty list (loaded, no reminders) apart from a READ
  /// FAILURE. A missing table (migration not applied) counts as "no reminders
  /// yet" (ok, empty), not a failure.
  static Future<ReminderLoadResult> fetchStartReminderOffsets(
    String eventId,
  ) async {
    try {
      final data = await _db
          .from('event_start_reminder_offsets')
          .select('offset_minutes')
          .eq('event_id', eventId);
      return ReminderLoadResult.ok(
        StartReminderOffsets.parseRows(data as List),
      );
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        // Table does not exist yet (migration pending) → no reminders, not a fail.
        return const ReminderLoadResult.ok(<int>[]);
      }
      return ReminderLoadResult.failed('Could not load reminders: ${e.message}');
    } catch (e) {
      return ReminderLoadResult.failed('Could not load reminders: $e');
    }
  }

  /// Atomically replace the event's start-reminder offsets with [offsets]
  /// (an empty list clears all reminders). Runs server-side in ONE transaction
  /// via the `set_event_start_reminders` RPC, so a failed insert can never wipe
  /// the user's existing settings. Authorization (admin / event's manager) is
  /// enforced in the function — no service-role client.
  ///
  /// Returns null on success, or a user-readable error message on failure. The
  /// caller MUST surface a non-null result instead of reporting success.
  static Future<String?> setStartReminderOffsets(
    String eventId,
    List<int> offsets,
  ) async {
    try {
      await _db.rpc('set_event_start_reminders', params: {
        'p_event_id': eventId,
        'p_offsets': offsets,
      });
      return null;
    } on PostgrestException catch (e) {
      // 42883 = function missing (migration not applied); surface a clear hint.
      if (e.code == '42883') {
        return 'Reminders are not available yet (pending database update).';
      }
      return 'Could not save reminders: ${e.message}';
    } catch (e) {
      return 'Could not save reminders: $e';
    }
  }

  /// Update an existing event's supported fields only (simplified form):
  /// title, start/end, client, description, link. Legacy columns (cost, room,
  /// shooting/final, event_type, team_id) and the event's attendees are left
  /// UNTOUCHED, so editing never wipes historical data the new form no longer
  /// shows. An event keeps its owning department; RLS blocks cross-department
  /// moves.
  static Future<void> updateEvent({
    required String eventId,
    required String title,
    required DateTime start,
    required DateTime end,
    String? clientId,
    String? description,
    String? link,
  }) async {
    // Editing a legacy Studio booking's time can still collide with another
    // booking; the exclusion constraint raises 23P01, surfaced as a conflict.
    try {
      await _db
          .from('events')
          .update({
            'title': title,
            'start_time': start.toIso8601String(),
            'end_time': end.toIso8601String(),
            'client_id': clientId,
            'description': description,
            'link': link,
          })
          .eq('id', eventId);
    } on PostgrestException catch (e) {
      if (e.code == '23P01') throw const BookingConflictException();
      return;
    } catch (_) {
      return;
    }
  }

  /// Update only an event's status (done / cancelled_by_client / cancelled_by_us
  /// / pending). Notifies the assigned attendees of the change (push via the
  /// notifications insert trigger); [changedBy] is excluded from that alert.
  static Future<void> updateEventStatus({
    required String eventId,
    required String status,
    String? changedBy,
  }) async {
    try {
      await _db
          .from('events')
          .update({
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId);

      // Status-change notifications (incl. cancellations) are handled
      // SERVER-SIDE by the trigger notify_event_status_changed, which notifies a
      // single deduplicated recipient set (attendees + owning-department
      // managers + admins, excluding the actor) — see
      // PROPOSED_calendar_reminders.sql §5. This replaces the old client-side
      // notifyAction call, which double-sent to attendees and admins. NOTE: this
      // change MUST ship together with that SQL, or status changes will not
      // notify anyone.
    } catch (_) {}
  }

  /// Permanently remove an event and its attendee links.
  static Future<void> deleteEvent(String eventId) async {
    try {
      // Remove attendee links first (in case no FK cascade is configured).
      await _db.from('event_attendees').delete().eq('event_id', eventId);
      await _db.from('events').delete().eq('id', eventId);
    } catch (_) {}
  }

  /// Deletes client profile, user profile, unlinks references, and deletes auth user.
  static Future<({bool success, String? error})> deleteClient(
    String clientId,
  ) async {
    try {
      // 1. Unlink client_id from tables that retain history
      final tablesToUnlink = [
        ('tasks', 'client_id'),
        ('events', 'client_id'),
        ('room_bookings', 'client_id'),
        ('custom_rows', 'linked_client_id'),
        ('custom_tables', 'client_id'),
      ];
      for (final pair in tablesToUnlink) {
        try {
          await _db.from(pair.$1).update({pair.$2: null}).eq(pair.$2, clientId);
        } catch (_) {}
      }

      // 2. Delete client-specific child records
      final tablesToDeleteByClient = [
        'ai_interactions',
        'crm_payments',
        'crm_entries',
        'client_invoices',
        'client_task_visibility',
        'client_task_column_visibility',
      ];
      for (final table in tablesToDeleteByClient) {
        try {
          await _db.from(table).delete().eq('client_id', clientId);
        } catch (_) {}
      }

      // 3. Delete profile-specific child records
      final tablesToDeleteByProfile = [
        'event_attendees',
        'task_assignees',
        'notifications',
      ];
      for (final table in tablesToDeleteByProfile) {
        try {
          await _db.from(table).delete().eq('profile_id', clientId);
        } catch (_) {}
      }

      // 4. Delete from client_profiles
      try {
        await _db.from('client_profiles').delete().eq('id', clientId);
      } on PostgrestException catch (e) {
        return (
          success: false,
          error: 'Could not remove client profile: ${e.message}',
        );
      } catch (e) {
        return (success: false, error: 'Could not remove client profile: $e');
      }

      // 5. Delete profile row
      try {
        await _db.from('profiles').delete().eq('id', clientId);
      } on PostgrestException catch (e) {
        return (
          success: false,
          error: 'Could not remove profile: ${e.message}',
        );
      } catch (_) {}

      // 6. Delete auth user (server-side, admin-gated).
      try {
        await PrivilegedOps.deleteUser(clientId);
      } catch (_) {}

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }
}
