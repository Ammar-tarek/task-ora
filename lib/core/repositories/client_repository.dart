// lib/core/repositories/client_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../models/client_model.dart';
import '../models/task_model.dart';
import '../utils/app_time.dart';
import 'finance_repository.dart';
import 'notification_repository.dart';

class CalEventData {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? clientId;
  final String? clientName;
  final double? cost;
  final List<String> attendeeNames;
  final String? roomName;

  const CalEventData({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.clientId,
    this.clientName,
    this.cost,
    this.attendeeNames = const [],
    this.roomName,
  });

  factory CalEventData.fromMap(Map<String, dynamic> m) {
    final client = m['client'] as Map<String, dynamic>?;
    final attendees = (m['event_attendees'] as List<dynamic>? ?? []);
    return CalEventData(
      id:            m['id'] as String,
      title:         m['title'] as String? ?? '',
      start:         DateTime.tryParse(m['start_time'] as String? ?? '') ?? DateTime.now(),
      end:           DateTime.tryParse(m['end_time'] as String? ?? '') ?? DateTime.now(),
      clientId:      m['client_id'] as String?,
      clientName:    client?['company_name'] as String?,
      cost:          (m['cost'] as num?)?.toDouble(),
      roomName:      m['location'] as String?,
      attendeeNames: attendees.map((a) {
        final p = a['profile'] as Map<String, dynamic>?;
        return p?['full_name'] as String? ?? '';
      }).where((n) => n.isNotEmpty).toList(),
    );
  }
}

class ClientRepository {
  static final _db      = SupabaseService.client;
  static final _adminDb = SupabaseService.adminClient;
  static SupabaseClient get adminDb => _adminDb;

  static Future<List<ClientModel>> fetchClients({String? clientType}) async {
    try {
      var query = _adminDb.from('client_profiles').select();
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
      final data = await _adminDb
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
      final data = await _db.from('client_profiles').insert({
        'id':             profileId,
        'company_name':   companyName,
        'contact_person': contactPerson,
        'email':          email,
        'phone':          phone,
        'whatsapp_number': whatsappNumber,
        'address':        address,
        'notes':          notes,
      }).select().single();
      return ClientModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Creates auth user + profile + client_profile in one call.
  /// Returns the new [ClientModel] or null on failure.
  /// [error] is set to a human-readable message when it fails.
  static Future<({ClientModel? client, String? error})> createClientWithAccount({
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
      // 1. Create the auth user via admin API
      final res = await _adminDb.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
          userMetadata: {'full_name': fullName},
        ),
      );
      final userId = res.user?.id;
      if (userId == null) {
        return (client: null, error: 'Failed to create user account');
      }

      // 2. Upsert profile row (trigger may have already created it)
      await _adminDb.from('profiles').upsert({
        'id':        userId,
        'full_name': fullName,
        'role':      'client',
      });

      // 3. Insert client_profiles row
      final data = await _adminDb.from('client_profiles').insert({
        'id':             userId,
        'company_name':   companyName,
        'contact_person': contactPerson,
        'email':          email,
        'phone':          phone,
        'whatsapp_number': whatsappNumber,
        'address':        address,
        'notes':          notes,
        if (clientType != null && clientType.isNotEmpty) 'client_type': clientType,
      }).select().single();

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
  static Future<({ClientModel? client, String? error})> updateClientWithAccount({
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
      // 1. Update auth user if email or password changed
      final authAttrs = <String, dynamic>{};
      if (newEmail != null && newEmail.isNotEmpty && newEmail != email) {
        authAttrs['email'] = newEmail;
      }
      if (newPassword != null && newPassword.isNotEmpty) {
        authAttrs['password'] = newPassword;
      }
      if (authAttrs.isNotEmpty) {
        await _adminDb.auth.admin.updateUserById(
          clientId,
          attributes: AdminUserAttributes(
            email:    authAttrs['email'] as String?,
            password: authAttrs['password'] as String?,
          ),
        );
      }

      // 2. Update profiles full_name
      await _adminDb.from('profiles').update({'full_name': fullName}).eq('id', clientId);

      // 3. Update client_profiles
      final effectiveEmail = (newEmail != null && newEmail.isNotEmpty) ? newEmail : email;
      final data = await _adminDb.from('client_profiles').update({
        'company_name':    companyName,
        'contact_person':  contactPerson,
        'email':           effectiveEmail,
        'phone':           phone,
        'whatsapp_number': whatsappNumber,
        'address':         address,
        'notes':           notes,
        if (clientType != null && clientType.isNotEmpty) 'client_type': clientType,
      }).eq('id', clientId).select().single();

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
      final linked = await _adminDb.from('client_profiles').select('id');
      final linkedIds = (linked as List).map((r) => r['id'] as String).toList();

      final all = await _adminDb
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'client');

      return (all as List)
          .where((r) => !linkedIds.contains(r['id'] as String))
          .map((r) => {
                'id':        r['id'] as String,
                'full_name': r['full_name'] as String? ?? '',
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<TaskModel>> fetchClientTasks(String clientId) async {
    try {
      final data = await _adminDb
          .from('tasks')
          .select('*, client:client_profiles(company_name), task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name)), task_comments(id, content, is_internal, created_at, author:profiles!task_comments_author_id_fkey(full_name))')
          .eq('client_id', clientId)
          .order('created_at', ascending: false);
      return (data as List).map((m) => TaskModel.fromMap(m)).toList();
    } catch (_) {
      try {
        final data = await _adminDb
            .from('tasks')
            .select('*, client:client_profiles(company_name), task_assignees(profile_id, is_lead, profile:profiles!task_assignees_profile_id_fkey(full_name))')
            .eq('client_id', clientId)
            .order('created_at', ascending: false);
        return (data as List).map((m) => TaskModel.fromMap(m)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<List<CalEventData>> fetchAllEvents() async {
    try {
      final data = await _adminDb
          .from('events')
          .select('*, client:client_profiles(company_name), event_attendees(profile_id, profile:profiles(full_name))')
          .order('start_time', ascending: true);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<CalEventData>> fetchClientEvents(String clientId) async {
    try {
      final data = await _adminDb
          .from('events')
          .select('*, client:client_profiles(company_name), event_attendees(profile_id, profiles(full_name))')
          .eq('client_id', clientId)
          .order('start_time', ascending: false);
      return (data as List).map((m) => CalEventData.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<CrmEntry>> fetchClientCrmEntries(String clientId) async {
    try {
      final data = await _adminDb
          .from('crm_entries')
          .select('*, client:client_profiles(company_name)')
          .eq('client_id', clientId)
          .order('created_at', ascending: false);
      return (data as List).map((m) => CrmEntry.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save a new event to Supabase with optional client, cost, room, and attendees.
  /// If a client and cost are provided, also creates a CRM entry so the meeting
  /// fee appears automatically on the client's finance page.
  static Future<void> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? clientId,
    double? cost,
    required String createdBy,
    List<String> attendeeIds = const [],
    String? roomName,
  }) async {
    try {
      final event = await _adminDb.from('events').insert({
        'title':      title,
        'start_time': start.toIso8601String(),
        'end_time':   end.toIso8601String(),
        'client_id':  clientId,
        'cost':       cost,
        'created_by': createdBy,
        'location':   roomName,
      }).select('id').single();

      final eventId = event['id'] as String;
      if (attendeeIds.isNotEmpty) {
        await _adminDb.from('event_attendees').insert(
          attendeeIds.map((pid) => {'event_id': eventId, 'profile_id': pid}).toList(),
        );

        // Notify assigned employees / managers about the calendar event!
        final dateStr = '${start.day}/${start.month}/${start.year}';
        final timeStr = '${AppTime.hm(start)} - ${AppTime.hm(end)}';
        for (final recipientId in attendeeIds) {
          if (recipientId != createdBy) {
            await NotificationRepository.createNotification(
              recipientId: recipientId,
              type: 'calendar_event',
              title: 'Calendar Event Assigned',
              body: 'You have been assigned to event "$title" on $dateStr ($timeStr).',
              referenceType: 'calendar',
              referenceId: eventId,
            );
          }
        }
      }

      // Auto-create CRM invoice so the cost appears on the client's finance page
      if (clientId != null && cost != null && cost > 0) {
        try {
          await _adminDb.from('crm_entries').insert({
            'client_id':   clientId,
            'title':       '$title – Meeting Booking',
            'amount':      cost,
            'paid_amount': 0,
            'status':      'unpaid',
            'source_type': 'room_booking',
            'currency':    'USD',
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Update an existing event. Replaces attendees with the new list.
  static Future<void> updateEvent({
    required String eventId,
    required String title,
    required DateTime start,
    required DateTime end,
    String? clientId,
    double? cost,
    String? roomName,
    List<String> attendeeIds = const [],
  }) async {
    try {
      await _adminDb.from('events').update({
        'title':      title,
        'start_time': start.toIso8601String(),
        'end_time':   end.toIso8601String(),
        'client_id':  clientId,
        'cost':       cost,
        'location':   roomName,
      }).eq('id', eventId);

      await _adminDb.from('event_attendees').delete().eq('event_id', eventId);
      if (attendeeIds.isNotEmpty) {
        await _adminDb.from('event_attendees').insert(
          attendeeIds.map((pid) => {'event_id': eventId, 'profile_id': pid}).toList(),
        );

        // Notify assigned attendees of updated event details!
        final dateStr = '${start.day}/${start.month}/${start.year}';
        final timeStr = '${AppTime.hm(start)} - ${AppTime.hm(end)}';
        for (final recipientId in attendeeIds) {
          await NotificationRepository.createNotification(
            recipientId: recipientId,
            type: 'calendar_event',
            title: 'Calendar Event Updated',
            body: 'Event "$title" on $dateStr ($timeStr) was updated.',
            referenceType: 'calendar',
            referenceId: eventId,
          );
        }
      }
    } catch (_) {}
  }
}
