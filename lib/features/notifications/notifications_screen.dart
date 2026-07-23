// lib/features/notifications/notifications_screen.dart
// Role-aware notification list with deep-linking, deduplication,
// drag-to-ignore (per-user dismissal via SharedPreferences), and inline actions.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/notification_repository.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    RealtimeService.instance.listen(const ['notifications'], _onRealtime);
  }

  void _onRealtime() { if (mounted) _load(); }

  @override
  void dispose() {
    RealtimeService.instance.unlisten(_onRealtime);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;

    List<AppNotification> rawData;

    if (profile.isAdmin) {
      // Admin sees all notifications
      rawData = await NotificationRepository.fetchAll();
    } else if (profile.isManager && profile.teamId != null) {
      // Manager sees own + team employees' notifications
      rawData = await NotificationRepository.fetchForTeam(profile.teamId!);
    } else {
      // Employee / client sees only own
      rawData = await NotificationRepository.fetchForUser(profile.id);
    }

    // 1) Filter out notifications ignored / dismissed by this user
    final prefs = await SharedPreferences.getInstance();
    final ignoredKey = 'dismissed_notifs_${profile.id}';
    final ignoredIds = (prefs.getStringList(ignoredKey) ?? []).toSet();
    final filtered = rawData.where((n) => !ignoredIds.contains(n.id)).toList();

    // 2) Deduplicate identical notifications (same title, body, referenceType, referenceId)
    final seenKeys = <String>{};
    final uniqueData = <AppNotification>[];
    for (final n in filtered) {
      final key = '${n.title.trim()}|${n.body.trim()}|${n.referenceType}|${n.referenceId}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        uniqueData.add(n);
      }
    }

    if (mounted) setState(() { _notifications = uniqueData; _loading = false; });
  }

  Future<void> _ignoreNotification(String id) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'dismissed_notifs_${profile.id}';
    final current = prefs.getStringList(key) ?? [];
    if (!current.contains(id)) {
      current.add(id);
      await prefs.setStringList(key, current);
    }
    setState(() {
      _notifications.removeWhere((n) => n.id == id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification ignored for you.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;
    await NotificationRepository.markAllReadForProfile(profile);
    _load();
  }

  Future<void> _markRead(String id) async {
    await NotificationRepository.markRead(id);
    _load();
  }

  Future<void> _acceptHandoff(String taskId) async {
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) return;

    try {
      final task = await TaskRepository.fetchTaskDetail(taskId);
      if (task == null) return;
      final targetTeam = task['handoff_to_team_id'] as String? ?? profile.teamId;
      if (targetTeam != null) {
        await TaskRepository.acceptHandoff(taskId: taskId, teamId: targetTeam);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Task handoff accepted!'),
            backgroundColor: AppColors.statusDone,
          ));
        }
        _load();
      }
    } catch (_) {}
  }

  /// Mark the notification as read, then navigate to its referenced page.
  void _onNotificationTap(AppNotification n) {
    if (!n.isRead) _markRead(n.id);
    _navigateToReference(n);
  }

  /// Maps [referenceType] (or falls back to [type]) to an in-app route.
  void _navigateToReference(AppNotification n) {
    final refType = n.referenceType;
    final refId   = n.referenceId;

    String? route;

    // 1) Explicit routing via referenceType stored in DB
    if (refType != null) {
      switch (refType) {
        case 'task':
          route = refId != null ? '/tasks/detail/$refId' : '/tasks';
        case 'penalty':
          route = '/penalties';
        case 'expense':
          route = '/expenses';
        case 'attendance':
          route = '/attendance';
        case 'payment':
          route = '/finance';
      }
    }

    // 2) Fallback: derive route from the notification type
    if (route == null) {
      switch (n.type) {
        case 'task_assigned':
        case 'task_done':
        case 'task_handoff':
          route = refId != null ? '/tasks/detail/$refId' : '/tasks';
        case 'penalty_issued':
        case 'penalty_applied':
          route = '/penalties';
        case 'payment_due':
          route = '/finance';
        case 'attendance_alert':
          route = '/attendance';
      }
    }

    if (route != null && mounted) {
      context.go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Notifications${unread > 0 ? ' ($unread)' : ''}'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _notifications.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.notifications_none_outlined,
                      size: 64, color: AppColors.outlineVariant),
                    const SizedBox(height: 16),
                    Text('No notifications', style: AppTextStyles.labelMd),
                  ]),
                )
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      return Dismissible(
                        key: Key('notif_${n.id}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _ignoreNotification(n.id),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_off_outlined, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text('Ignore', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        child: _NotifCard(
                          notif: n,
                          onTap: () => _onNotificationTap(n),
                          onAcceptHandoff: (n.type == 'task_handoff' && n.referenceId != null)
                              ? () => _acceptHandoff(n.referenceId!)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({
    required this.notif,
    required this.onTap,
    this.onAcceptHandoff,
  });

  final AppNotification notif;
  final VoidCallback onTap;
  final VoidCallback? onAcceptHandoff;

  IconData get _icon {
    switch (notif.type) {
      case 'task_assigned':     return Icons.assignment_outlined;
      case 'task_done':         return Icons.check_circle_outline;
      case 'task_handoff':      return Icons.swap_horiz_outlined;
      case 'payment_due':       return Icons.account_balance_wallet_outlined;
      case 'penalty_issued':
      case 'penalty_applied':   return Icons.gavel_outlined;
      case 'attendance_alert':  return Icons.access_time_outlined;
      case 'system':            return Icons.settings_outlined;
      default:                  return Icons.notifications_outlined;
    }
  }

  /// Whether this notification links to another page.
  bool get _hasLink {
    if (notif.referenceType != null) return true;
    return const {
      'task_assigned', 'task_done', 'task_handoff', 'penalty_issued', 'penalty_applied',
      'payment_due', 'attendance_alert',
    }.contains(notif.type);
  }

  String get _timeAgo {
    try {
      final dtUtc = DateTime.parse(notif.createdAt).toUtc();
      final diff = DateTime.now().toUtc().difference(dtUtc);
      final minutes = diff.inMinutes;
      if (minutes <= 0) return 'Just now';
      if (minutes < 60) return '${minutes}m ago';
      final hours = diff.inHours;
      if (hours < 24)   return '${hours}h ago';
      final days = diff.inDays;
      if (days < 7)     return '${days}d ago';
      final dt = AppTime.cairo(dtUtc);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead
              ? AppColors.surfaceContainerLowest
              : AppColors.gold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: notif.isRead ? AppColors.outlineVariant : AppColors.gold.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, size: 18, color: AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(notif.title,
                    style: AppTextStyles.labelMd.copyWith(
                      fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                    ))),
                  if (!notif.isRead)
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.gold, shape: BoxShape.circle,
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(notif.body,
                  style: AppTextStyles.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(_timeAgo,
                  style: AppTextStyles.bodySm.copyWith(fontSize: 11)),
              ])),
              if (_hasLink)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right, size: 18, color: AppColors.outlineVariant),
                ),
            ]),
            if (onAcceptHandoff != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: onAcceptHandoff,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Accept Task Handoff'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusDone,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
