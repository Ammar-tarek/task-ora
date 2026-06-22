// lib/features/notifications/notifications_screen.dart
// Live notifications with Supabase Realtime stream.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/notification_repository.dart';
import '../../core/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = context.read<AuthNotifier>().profile?.id ?? '';
    final data   = await NotificationRepository.fetchForUser(userId);
    if (mounted) setState(() { _notifications = data; _loading = false; });
  }

  Future<void> _markAllRead() async {
    final userId = context.read<AuthNotifier>().profile?.id ?? '';
    await NotificationRepository.markAllRead(userId);
    _load();
  }

  Future<void> _markRead(String id) async {
    await NotificationRepository.markRead(id);
    _load();
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
                    const Icon(Icons.notifications_none_outlined,
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
                      return _NotifCard(notif: n, onTap: () => _markRead(n.id));
                    },
                  ),
                ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.notif, required this.onTap});
  final AppNotification notif;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notif.type) {
      case 'task_assigned':   return Icons.assignment_outlined;
      case 'task_done':       return Icons.check_circle_outline;
      case 'payment_due':     return Icons.account_balance_wallet_outlined;
      case 'penalty_issued':  return Icons.gavel_outlined;
      case 'system':          return Icons.settings_outlined;
      default:                return Icons.notifications_outlined;
    }
  }

  String get _timeAgo {
    try {
      final dt   = DateTime.parse(notif.createdAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      if (diff.inDays < 7)     return '${diff.inDays}d ago';
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        ]),
      ),
    );
  }
}
