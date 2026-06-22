// lib/core/services/n8n_service.dart
// Sends task-update notifications to the n8n webhook.
// n8n receives the client's phone number and sends them a Telegram message.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class N8nService {
  N8nService._();

  static const _prefKey = 'n8n_webhook_url';

  // ── URL storage (admin sets this once in Settings) ────────────────────────

  static Future<String> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? '';
  }

  static Future<void> saveWebhookUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url.trim());
  }

  // ── Notification ──────────────────────────────────────────────────────────

  /// Called after admin/manager saves a task that has a client attached.
  /// Sends a POST to the n8n webhook with the client phone + task details.
  /// Fire-and-forget — never throws, never blocks the UI.
  static Future<void> notifyTaskUpdate({
    required String clientPhone,
    required String clientName,
    required String taskTitle,
    required String newStatus,
    required String priority,
    String? dueDate,
    int completionPercentage = 0,
    String? description,
    String updatedBy = '',
  }) async {
    try {
      final url = await getWebhookUrl();
      if (url.isEmpty) return;

      await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone':                 clientPhone,
              'client_name':           clientName,
              'task_title':            taskTitle,
              'task_status':           _statusLabel(newStatus),
              'task_priority':         priority,
              'due_date':              dueDate ?? '',
              'completion_percentage': completionPercentage,
              'description':           description ?? '',
              'updated_by':            updatedBy,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silently swallow — webhook failure must never block the task save
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'not_started':     return 'Not Started';
      case 'in_progress':     return 'In Progress';
      case 'employee_done':   return 'Employee Done';
      case 'client_approve':  return 'Client Approved';
      case 'client_rejected': return 'Client Rejected';
      case 'completed':       return 'Completed';
      case 'on_hold':         return 'On Hold';
      default:                return status;
    }
  }
}
