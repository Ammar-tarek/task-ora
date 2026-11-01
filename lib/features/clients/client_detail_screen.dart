// lib/features/clients/client_detail_screen.dart
// Client Details view (Phase B): overview + calendar history + activity.
// All data comes from existing RLS-safe repository reads (no service-role):
//   • ClientRepository.fetchClientById        — overview
//   • ClientRepository.fetchClientEvents       — events by events.client_id
//   • ClientRepository.fetchClientCrmEntries    — client finance records (dates only here)
// Month grouping/navigation is the pure ClientHistory logic.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/client_model.dart';
import '../../core/models/team_model.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/finance_repository.dart' show CrmEntry;
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';
import 'client_history.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    this.initialClient,
  });

  final String clientId;
  final ClientModel? initialClient;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  bool _loading = true;
  bool _error = false;
  ClientModel? _client;
  List<CalEventData> _events = const [];
  List<CrmEntry> _crm = const [];
  final Map<String, String> _teamNames = {};
  late YearMonth _month = YearMonth.of(DateTime.now());

  @override
  void initState() {
    super.initState();
    _client = widget.initialClient;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        if (_client == null)
          ClientRepository.fetchClientById(widget.clientId)
        else
          Future.value(_client),
        ClientRepository.fetchClientEvents(widget.clientId),
        ClientRepository.fetchClientCrmEntries(widget.clientId),
        TeamRepository.fetchAll(),
      ]);
      final client = results[0] as ClientModel?;
      final events = results[1] as List<CalEventData>;
      final crm = results[2] as List<CrmEntry>;
      final teams = results[3] as List<TeamModel>;

      _teamNames
        ..clear()
        ..addEntries(teams.map((t) => MapEntry(t.id, t.name)));

      if (!mounted) return;
      setState(() {
        _client = client;
        _events = events;
        _crm = crm;
        _month = ClientHistory.initialMonth(events);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  String _deptName(String? teamId) =>
      teamId == null ? '—' : (_teamNames[teamId] ?? 'Department');

  @override
  Widget build(BuildContext context) {
    final title = _client?.companyName ?? 'Client';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Finance',
              onPressed: () => context.push('/clients/${widget.clientId}/finance'),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Calendar'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error
            ? _ErrorState(onRetry: _load)
            : TabBarView(
                children: [
                  _buildOverview(),
                  _buildCalendar(),
                  _buildActivity(),
                ],
              ),
      ),
    );
  }

  // ── Overview ───────────────────────────────────────────────────────────────
  Widget _buildOverview() {
    final c = _client;
    if (c == null) {
      return const _MessageState(
        icon: Icons.person_off_outlined,
        title: 'Client not found',
        message: 'This client may have been removed, or is outside your access.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          children: [
            _kv('Name', c.companyName),
            if (c.contactPerson.isNotEmpty) _kv('Contact', c.contactPerson),
            if (c.email.isNotEmpty) _kv('Email', c.email),
            if ((c.phone ?? '').isNotEmpty) _kv('Phone', c.phone!),
            if ((c.whatsappNumber ?? '').isNotEmpty) _kv('WhatsApp', c.whatsappNumber!),
            if ((c.address ?? '').isNotEmpty) _kv('Address', c.address!),
            _kv('Status', c.isArchived ? 'Archived' : 'Active'),
            if ((c.contractStartDate ?? '').isNotEmpty)
              _kv('Contract start', c.contractStartDate!),
            if ((c.contractEndDate ?? '').isNotEmpty)
              _kv('Contract end', c.contractEndDate!),
            if ((c.notes ?? '').isNotEmpty) _kv('Notes', c.notes!),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.push('/clients/${widget.clientId}/finance'),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Open Finance'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
      ],
    );
  }

  // ── Calendar history ─────────────────────────────────────────────────────
  Widget _buildCalendar() {
    final monthEvents = ClientHistory.eventsInMonth(_events, _month);
    return Column(
      children: [
        _MonthBar(
          label: '${_months[_month.month - 1]} ${_month.year}',
          onPrev: () => setState(() => _month = _month.previous),
          onNext: () => setState(() => _month = _month.next),
        ),
        Expanded(
          child: monthEvents.isEmpty
              ? _MessageState(
                  icon: Icons.event_busy_outlined,
                  title: 'No events this month',
                  message: _events.isEmpty
                      ? 'This client has no calendar events you can see.'
                      : 'Use the arrows to find months with events.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: monthEvents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final e = monthEvents[i];
                    return _EventCard(
                      event: e,
                      deptName: _deptName(e.teamId),
                      onTap: () => _showEventDetail(e),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Activity (events + finance records, by date) ───────────────────────────
  Widget _buildActivity() {
    final items = <_Activity>[
      for (final e in _events)
        _Activity(
          date: e.start,
          icon: Icons.event_outlined,
          title: e.title,
          subtitle: 'Event · ${_statusLabel(e.status)} · ${_deptName(e.teamId)}',
          onTap: () => _showEventDetail(e),
        ),
      for (final r in _crm)
        _Activity(
          date: _crmDate(r),
          icon: Icons.receipt_long_outlined,
          title: r.title,
          subtitle: 'Finance record · ${_statusLabel(r.status)}',
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) {
      return const _MessageState(
        icon: Icons.history,
        title: 'No activity yet',
        message: 'Events and finance records for this client appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = items[i];
        return _InfoCard(
          onTap: a.onTap,
          children: [
            Row(
              children: [
                Icon(a.icon, size: 20, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          style: AppTextStyles.bodyMd
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(a.subtitle,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(_dateLabel(a.date),
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showEventDetail(CalEventData e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(e.title, style: AppTextStyles.headlineSm),
            const SizedBox(height: 12),
            _kv('When', '${_dateLabel(e.start)} · ${_timeLabel(e.start)}–${_timeLabel(e.end)}'),
            _kv('Status', _statusLabel(e.status)),
            _kv('Department', _deptName(e.teamId)),
            if ((e.description ?? '').isNotEmpty) _kv('Details', e.description!),
            if ((e.link ?? '').isNotEmpty) _kv('Link', e.link!),
            if (e.attendeeNames.isNotEmpty)
              _kv('Attendees', e.attendeeNames.join(', ')),
          ],
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ),
            Expanded(child: Text(v, style: AppTextStyles.bodyMd)),
          ],
        ),
      );

  static DateTime _crmDate(CrmEntry r) =>
      DateTime.tryParse(r.entryDate ?? r.createdAt ?? '') ?? DateTime.now();

  static String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _statusLabel(String s) {
    switch (s) {
      case 'done':
      case 'completed':
        return 'Done';
      case 'cancelled':
      case 'cancelled_by_client':
      case 'cancelled_by_us':
        return 'Cancelled';
      case 'pending':
        return 'Pending';
      default:
        return s.isEmpty ? '—' : s;
    }
  }
}

class _Activity {
  _Activity({
    required this.date,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final DateTime date;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.label, required this.onPrev, required this.onNext});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: onPrev,
          ),
          Text(label, style: AppTextStyles.headlineSm.copyWith(fontSize: 18)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.deptName,
    required this.onTap,
  });
  final CalEventData event;
  final String deptName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = event.start;
    final day = start.day.toString().padLeft(2, '0');
    final time =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Column(
              children: [
                Text(day, style: AppTextStyles.headlineSm),
                Text(time,
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: AppTextStyles.bodyMd
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(deptName,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            _StatusChip(status: event.status),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'done':
      case 'completed':
        color = Colors.green;
        break;
      case 'cancelled':
      case 'cancelled_by_client':
      case 'cancelled_by_us':
        color = AppColors.error;
        break;
      default:
        color = AppColors.gold;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _ClientDetailScreenState._statusLabel(status),
        style: AppTextStyles.bodySm.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children, this.onTap});
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: card);
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.outlineVariant),
            const SizedBox(height: 16),
            Text(title,
                style: AppTextStyles.headlineSm
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Could not load this client',
                style: AppTextStyles.headlineSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
