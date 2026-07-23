// lib/features/calendar/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/client_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/providers/team_filter_notifier.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_time.dart';
import '../../core/widgets/team_filter_chip.dart';

// ── Model ──────────────────────────────────────────────────────────────────────
class CalEvent {
  const CalEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    this.isAllDay = false,
    this.assigneeInitials,
    this.clientName,
    this.clientId,
    this.cost,
    this.attendeeNames = const [],
    this.roomName,
  });
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final Color color;
  final bool isAllDay;
  final String? assigneeInitials;
  final String? clientName;
  final String? clientId;
  final double? cost;
  final List<String> attendeeNames;
  final String? roomName;
}

// ── Helpers ────────────────────────────────────────────────────────────────────
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _weekStart(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

// ── View enum ──────────────────────────────────────────────────────────────────
enum _CalView { month, week, day }

// ── Screen ─────────────────────────────────────────────────────────────────────
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  _CalView _view = _CalView.month;
  DateTime _focusedDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final _today = DateTime.now();
  List<CalEvent> _events = [];

  TeamFilterNotifier? _teamFilter;
  List<String> _teamMemberNames = []; // empty = no team filter active

  @override
  void initState() {
    super.initState();
    _loadEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = context.read<AuthNotifier>().profile;
      if (profile?.isAdmin == true) {
        _teamFilter = context.read<TeamFilterNotifier>()
          ..loadTeams()
          ..addListener(_onTeamChange);
      }
    });
  }

  @override
  void dispose() {
    _teamFilter?.removeListener(_onTeamChange);
    super.dispose();
  }

  void _onTeamChange() => _updateTeamFilter();

  Future<void> _updateTeamFilter() async {
    final teamId = _teamFilter?.selectedTeamId;
    if (teamId == null) {
      if (mounted) setState(() => _teamMemberNames = []);
      return;
    }
    final members = await TeamRepository.fetchMembersAdmin(teamId);
    if (mounted)
      setState(
        () => _teamMemberNames = members.map((m) => m.fullName).toList(),
      );
  }

  /// Events visible for the current team filter (all events when no filter set).
  List<CalEvent> get _displayEvents {
    if (_teamMemberNames.isEmpty) return _events;
    return _events
        .where((e) => e.attendeeNames.any((n) => _teamMemberNames.contains(n)))
        .toList();
  }

  Future<void> _loadEvents() async {
    final data = await ClientRepository.fetchAllEvents();
    if (!mounted) return;
    setState(() {
      _events = data
          .map(
            (e) => CalEvent(
              id: e.id,
              title: e.title,
              start: e.start,
              end: e.end,
              color: e.clientId != null
                  ? const Color(0xFFBA1A1A)
                  : AppColors.primary,
              clientId: e.clientId,
              clientName: e.clientName,
              cost: e.cost,
              roomName: e.roomName,
              attendeeNames: e.attendeeNames,
              assigneeInitials: e.attendeeNames.isNotEmpty
                  ? e.attendeeNames.first.substring(0, 1).toUpperCase()
                  : null,
            ),
          )
          .toList();
    });
  }

  List<CalEvent> _eventsForDay(DateTime day) => _displayEvents.where((e) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(e.start.year, e.start.month, e.start.day);
    return s == d;
  }).toList()..sort((a, b) => a.start.compareTo(b.start));

  void _navigate(int delta) => setState(() {
    if (_view == _CalView.month) {
      _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + delta);
    } else if (_view == _CalView.week) {
      _focusedDate = _focusedDate.add(Duration(days: delta * 7));
    } else {
      _focusedDate = _focusedDate.add(Duration(days: delta));
    }
  });

  String get _headerLabel {
    switch (_view) {
      case _CalView.month:
        return '${_monthNames[_focusedDate.month - 1]} ${_focusedDate.year}';
      case _CalView.week:
        final ws = _weekStart(_focusedDate);
        final we = ws.add(const Duration(days: 6));
        if (ws.month == we.month) {
          return '${_monthShort[ws.month - 1]} ${ws.day}–${we.day}, ${ws.year}';
        }
        return '${_monthShort[ws.month - 1]} ${ws.day} – ${_monthShort[we.month - 1]} ${we.day}, ${we.year}';
      case _CalView.day:
        return '${_dayShort[_focusedDate.weekday - 1]}, ${_monthShort[_focusedDate.month - 1]} ${_focusedDate.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final canAddEvent =
        profile == null ||
        profile.isAdmin ||
        profile.isManager ||
        profile.isClient;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _navigate(-1),
        ),
        title: GestureDetector(
          onTap: () => setState(() {
            _focusedDate = _today;
            _selectedDate = _today;
          }),
          child: Text(_headerLabel, style: AppTextStyles.headlineSm),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _navigate(1),
          ),
          TextButton(
            onPressed: () => setState(() {
              _focusedDate = _today;
              _selectedDate = _today;
            }),
            child: Text(
              'Today',
              style: AppTextStyles.labelMd.copyWith(color: AppColors.goldDark),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh events',
            onPressed: _loadEvents,
          ),
          if (profile?.isAdmin == true)
            IconButton(
              icon: const Icon(Icons.meeting_room_outlined),
              tooltip: 'Manage rooms',
              onPressed: () => _showManageRoomsSheet(context),
            ),
          _ViewSwitcherPill(
            current: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.outlineVariant),
        ),
      ),
      floatingActionButton: canAddEvent
          ? FloatingActionButton(
              onPressed: () => _showAddEventSheet(context),
              backgroundColor: AppColors.primary,
              tooltip: 'Add event',
              child: const Icon(Icons.add, color: AppColors.gold),
            )
          : null,
      body: Column(
        children: [
          const TeamFilterChip(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey(
                  '${_view}_${_focusedDate.year}_${_focusedDate.month}_${_focusedDate.day}',
                ),
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_view) {
      case _CalView.month:
        return _MonthBody(
          focusedDate: _focusedDate,
          selectedDate: _selectedDate,
          today: _today,
          eventsForDay: _eventsForDay,
          onDayTap: (d) => setState(() => _selectedDate = d),
          onEventTap: _showEventDetail,
        );
      case _CalView.week:
        return _WeekBody(
          weekStart: _weekStart(_focusedDate),
          selectedDate: _selectedDate,
          today: _today,
          eventsForDay: _eventsForDay,
          onDayTap: (d) => setState(() {
            _selectedDate = d;
            _focusedDate = d;
          }),
          onEventTap: _showEventDetail,
        );
      case _CalView.day:
        return _DayBody(
          day: _focusedDate,
          today: _today,
          eventsForDay: _eventsForDay,
          onEventTap: _showEventDetail,
        );
    }
  }

  void _showEventDetail(CalEvent event) {
    final profile = context.read<AuthNotifier>().profile;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EventDetailSheet(
        event: event,
        profile: profile,
        onEdit: () => _showEditEventSheet(event),
        onEdited: (updated) => setState(() {
          final idx = _events.indexWhere((e) => e.id == updated.id);
          if (idx != -1) _events[idx] = updated;
        }),
      ),
    );
  }

  void _showEditEventSheet(CalEvent event) {
    final profile = context.read<AuthNotifier>().profile;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditEventSheet(
        event: event,
        createdBy: profile?.id ?? '',
        onUpdated: (updated) => setState(() {
          final idx = _events.indexWhere((e) => e.id == updated.id);
          if (idx != -1) _events[idx] = updated;
        }),
      ),
    );
  }

  void _showManageRoomsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ManageRoomsSheet(),
    );
  }

  void _showAddEventSheet(BuildContext context) {
    final profile = context.read<AuthNotifier>().profile;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddEventSheet(
        initialDate: _selectedDate,
        createdBy: profile?.id ?? '',
        onCreated: (event) => setState(() => _events.add(event)),
      ),
    );
  }
}

// ── View switcher pill ─────────────────────────────────────────────────────────
class _ViewSwitcherPill extends StatelessWidget {
  const _ViewSwitcherPill({required this.current, required this.onChanged});
  final _CalView current;
  final ValueChanged<_CalView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _CalView.values.map((v) {
          final active = v == current;
          final label = v.name[0].toUpperCase() + v.name.substring(1);
          return GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: AppTextStyles.labelMd.copyWith(
                  color: active
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Month body ─────────────────────────────────────────────────────────────────
class _MonthBody extends StatelessWidget {
  const _MonthBody({
    required this.focusedDate,
    required this.selectedDate,
    required this.today,
    required this.eventsForDay,
    required this.onDayTap,
    required this.onEventTap,
  });
  final DateTime focusedDate;
  final DateTime selectedDate;
  final DateTime today;
  final List<CalEvent> Function(DateTime) eventsForDay;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<CalEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Day-of-week headers
        Container(
          color: AppColors.surfaceContainerLowest,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: _dayLetters
                .map(
                  (l) => Expanded(
                    child: Center(
                      child: Text(l, style: AppTextStyles.labelCaps),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Container(height: 1, color: AppColors.outlineVariant),
        // Month grid
        _MonthGrid(
          focusedDate: focusedDate,
          selectedDate: selectedDate,
          today: today,
          eventsForDay: eventsForDay,
          onDayTap: onDayTap,
        ),
        Container(height: 1, color: AppColors.outlineVariant),
        // Agenda for selected day
        Expanded(
          child: _AgendaForDay(
            day: selectedDate,
            events: eventsForDay(selectedDate),
            onEventTap: onEventTap,
          ),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.focusedDate,
    required this.selectedDate,
    required this.today,
    required this.eventsForDay,
    required this.onDayTap,
  });
  final DateTime focusedDate;
  final DateTime selectedDate;
  final DateTime today;
  final List<CalEvent> Function(DateTime) eventsForDay;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedDate.year, focusedDate.month, 1);
    final daysInMonth = DateTime(
      focusedDate.year,
      focusedDate.month + 1,
      0,
    ).day;
    // weekday: 1=Mon, 7=Sun; offset = leading empty cells
    final startOffset = firstOfMonth.weekday - 1;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Container(
      color: AppColors.surfaceContainerLowest,
      child: Column(
        children: List.generate(rows, (week) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(7, (dow) {
                final cellIndex = week * 7 + dow;
                final dayNum = cellIndex - startOffset + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: AppColors.outlineVariant,
                            width: 0.5,
                          ),
                          bottom: BorderSide(
                            color: AppColors.outlineVariant,
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final cellDate = DateTime(
                  focusedDate.year,
                  focusedDate.month,
                  dayNum,
                );
                final isToday = _isSameDay(cellDate, today);
                final isSelected = _isSameDay(cellDate, selectedDate);
                final dayEvents = eventsForDay(cellDate);
                final isWeekend = dow >= 5;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onDayTap(cellDate),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      decoration: BoxDecoration(
                        color: isSelected && !isToday
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : isWeekend
                            ? AppColors.surface.withValues(alpha: 0.5)
                            : Colors.transparent,
                        border: Border(
                          right: BorderSide(
                            color: AppColors.outlineVariant,
                            width: 0.5,
                          ),
                          bottom: BorderSide(
                            color: AppColors.outlineVariant,
                            width: 0.5,
                          ),
                          top: isSelected
                              ? BorderSide(color: AppColors.primary, width: 2)
                              : BorderSide.none,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(4, 4, 2, 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Day number
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? AppColors.goldDark
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$dayNum',
                                style: AppTextStyles.bodyMd.copyWith(
                                  fontSize: 13,
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isToday
                                      ? AppColors.onPrimary
                                      : isWeekend
                                      ? AppColors.onSurfaceVariant
                                      : AppColors.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Event chips (max 2 visible)
                          ...dayEvents
                              .take(2)
                              .map(
                                (e) => Container(
                                  margin: const EdgeInsets.only(bottom: 1),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: e.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border(
                                      left: BorderSide(
                                        color: e.color,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    e.title,
                                    style: AppTextStyles.bodySm.copyWith(
                                      fontSize: 9,
                                      color: e.color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          if (dayEvents.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Text(
                                '+${dayEvents.length - 2} more',
                                style: AppTextStyles.bodySm.copyWith(
                                  fontSize: 9,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

// ── Agenda list ────────────────────────────────────────────────────────────────
class _AgendaForDay extends StatelessWidget {
  const _AgendaForDay({
    required this.day,
    required this.events,
    required this.onEventTap,
  });
  final DateTime day;
  final List<CalEvent> events;
  final ValueChanged<CalEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    final label =
        '${_dayShort[day.weekday - 1]}, ${_monthShort[day.month - 1]} ${day.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(label, style: AppTextStyles.headlineSm),
        ),
        if (events.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 40,
                    color: AppColors.outlineVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No events',
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _AgendaEventTile(
                event: events[i],
                onTap: () => onEventTap(events[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _AgendaEventTile extends StatelessWidget {
  const _AgendaEventTile({required this.event, required this.onTap});
  final CalEvent event;
  final VoidCallback onTap;

  String _timeLabel() {
    if (event.isAllDay) return 'All day';
    final s = event.start;
    final e = event.end;
    String fmt(DateTime d) => AppTime.hm(d);
    return '${fmt(s)} – ${fmt(e)}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: event.color, width: 3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: AppTextStyles.labelMd),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(_timeLabel(), style: AppTextStyles.dataSm),
                    ],
                  ),
                ],
              ),
            ),
            if (event.assigneeInitials != null)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  event.assigneeInitials!,
                  style: AppTextStyles.labelMd.copyWith(
                    fontSize: 10,
                    color: event.color,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: AppColors.outlineVariant,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Week body ──────────────────────────────────────────────────────────────────
class _WeekBody extends StatefulWidget {
  const _WeekBody({
    required this.weekStart,
    required this.selectedDate,
    required this.today,
    required this.eventsForDay,
    required this.onDayTap,
    required this.onEventTap,
  });
  final DateTime weekStart;
  final DateTime selectedDate;
  final DateTime today;
  final List<CalEvent> Function(DateTime) eventsForDay;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<CalEvent> onEventTap;

  @override
  State<_WeekBody> createState() => _WeekBodyState();
}

class _WeekBodyState extends State<_WeekBody> {
  static const _startHour = 7;
  static const _endHour = 22;
  static const _rowH = 56.0;
  static const _timeColW = 52.0;

  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    final nowH = DateTime.now().hour.clamp(_startHour, _endHour);
    final initialOffset = ((nowH - _startHour) * _rowH - 100).clamp(
      0.0,
      double.infinity,
    );
    _scrollCtrl = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      7,
      (i) => widget.weekStart.add(Duration(days: i)),
    );
    final hours = List.generate(
      _endHour - _startHour + 1,
      (i) => _startHour + i,
    );
    final gridH = hours.length * _rowH;

    return Column(
      children: [
        // Day headers row
        Container(
          color: AppColors.surfaceContainerLowest,
          child: Row(
            children: [
              SizedBox(width: _timeColW),
              ...days.map((d) {
                final isToday = _isSameDay(d, widget.today);
                final isSelected = _isSameDay(d, widget.selectedDate);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onDayTap(d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.outlineVariant,
                            width: isSelected ? 2 : 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _dayShort[d.weekday - 1].toUpperCase(),
                            style: AppTextStyles.labelCaps.copyWith(
                              color: isToday
                                  ? AppColors.goldDark
                                  : AppColors.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppColors.goldDark
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${d.day}',
                              style: AppTextStyles.bodyMd.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isToday
                                    ? AppColors.onPrimary
                                    : AppColors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // Time grid
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: SizedBox(
              height: gridH + 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time labels
                  SizedBox(
                    width: _timeColW,
                    child: Stack(
                      children: hours.map((h) {
                        final top = (h - _startHour) * _rowH;
                        return Positioned(
                          top: top - 8,
                          left: 0,
                          right: 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: AppTextStyles.dataSm.copyWith(
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Columns per day
                  ...List.generate(days.length, (colIdx) {
                    final day = days[colIdx];
                    final dayEvents = widget.eventsForDay(day);
                    final isWeekend = day.weekday >= 6;
                    return Expanded(
                      child: Stack(
                        children: [
                          // Grid lines
                          Column(
                            children: hours
                                .map(
                                  (_) => Container(
                                    height: _rowH,
                                    decoration: BoxDecoration(
                                      color: isWeekend
                                          ? AppColors.surface.withValues(
                                              alpha: 0.4,
                                            )
                                          : Colors.transparent,
                                      border: Border(
                                        right: BorderSide(
                                          color: AppColors.outlineVariant,
                                          width: 0.5,
                                        ),
                                        bottom: BorderSide(
                                          color: AppColors.outlineVariant,
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          // Current time line
                          if (_isSameDay(day, widget.today))
                            _CurrentTimeLine(
                              startHour: _startHour,
                              rowH: _rowH,
                            ),
                          // Events
                          ...dayEvents.where((e) => !e.isAllDay).map((e) {
                            final topFrac =
                                (e.start.hour + e.start.minute / 60.0) -
                                _startHour;
                            final durH =
                                (e.end.difference(e.start).inMinutes / 60.0)
                                    .clamp(0.5, 24.0);
                            final top = topFrac * _rowH;
                            final height = durH * _rowH - 3;
                            return Positioned(
                              top: top,
                              left: 2,
                              right: 2,
                              height: height,
                              child: GestureDetector(
                                onTap: () => widget.onEventTap(e),
                                child: _TimeGridEvent(event: e),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Day body ───────────────────────────────────────────────────────────────────
class _DayBody extends StatefulWidget {
  const _DayBody({
    required this.day,
    required this.today,
    required this.eventsForDay,
    required this.onEventTap,
  });
  final DateTime day;
  final DateTime today;
  final List<CalEvent> Function(DateTime) eventsForDay;
  final ValueChanged<CalEvent> onEventTap;

  @override
  State<_DayBody> createState() => _DayBodyState();
}

class _DayBodyState extends State<_DayBody> {
  static const _startHour = 7;
  static const _endHour = 22;
  static const _rowH = 64.0;
  static const _timeColW = 56.0;

  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    final nowH = DateTime.now().hour.clamp(_startHour, _endHour);
    final initialOffset = ((nowH - _startHour) * _rowH - 120).clamp(
      0.0,
      double.infinity,
    );
    _scrollCtrl = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(
      _endHour - _startHour + 1,
      (i) => _startHour + i,
    );
    final dayEvents = widget
        .eventsForDay(widget.day)
        .where((e) => !e.isAllDay)
        .toList();
    final allDayEvents = widget
        .eventsForDay(widget.day)
        .where((e) => e.isAllDay)
        .toList();
    final gridH = hours.length * _rowH;
    final isToday = _isSameDay(widget.day, widget.today);

    return Column(
      children: [
        // All-day strip
        if (allDayEvents.isNotEmpty)
          Container(
            color: AppColors.surfaceContainerLowest,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: _timeColW,
                  child: Text('All day', style: AppTextStyles.dataSm),
                ),
                ...allDayEvents.map(
                  (e) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: e.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border(
                          left: BorderSide(color: e.color, width: 3),
                        ),
                      ),
                      child: Text(
                        e.title,
                        style: AppTextStyles.bodySm.copyWith(
                          color: e.color,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Time grid
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: SizedBox(
              height: gridH.toDouble(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time labels
                  SizedBox(
                    width: _timeColW,
                    child: Stack(
                      children: hours.map((h) {
                        final top = (h - _startHour) * _rowH;
                        return Positioned(
                          top: top - 8,
                          left: 0,
                          right: 4,
                          child: Text(
                            '${h.toString().padLeft(2, '0')}:00',
                            style: AppTextStyles.dataSm.copyWith(fontSize: 11),
                            textAlign: TextAlign.right,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Day column
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: hours
                              .map(
                                (_) => Container(
                                  height: _rowH,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: AppColors.outlineVariant,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        if (isToday)
                          _CurrentTimeLine(startHour: _startHour, rowH: _rowH),
                        ...dayEvents.map((e) {
                          final topFrac =
                              (e.start.hour + e.start.minute / 60.0) -
                              _startHour;
                          final durH =
                              (e.end.difference(e.start).inMinutes / 60.0)
                                  .clamp(0.5, 24.0);
                          return Positioned(
                            top: topFrac * _rowH,
                            left: 4,
                            right: 4,
                            height: durH * _rowH - 3,
                            child: GestureDetector(
                              onTap: () => widget.onEventTap(e),
                              child: _TimeGridEvent(
                                event: e,
                                showAssignee: true,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Time grid event block ──────────────────────────────────────────────────────
class _TimeGridEvent extends StatelessWidget {
  const _TimeGridEvent({required this.event, this.showAssignee = false});
  final CalEvent event;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final s = event.start;
    final e = event.end;
    String fmt(DateTime d) => AppTime.hm(d);

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: event.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: event.color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AppTextStyles.labelMd.copyWith(
                    color: event.color,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${fmt(s)} – ${fmt(e)}',
                  style: AppTextStyles.dataSm.copyWith(
                    fontSize: 9,
                    color: event.color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          if (showAssignee && event.assigneeInitials != null)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                event.assigneeInitials!,
                style: AppTextStyles.labelMd.copyWith(
                  fontSize: 8,
                  color: event.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Current time indicator ─────────────────────────────────────────────────────
class _CurrentTimeLine extends StatelessWidget {
  const _CurrentTimeLine({required this.startHour, required this.rowH});
  final int startHour;
  final double rowH;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final top = (now.hour + now.minute / 60.0 - startHour) * rowH;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Container(height: 1.5, color: AppColors.error)),
        ],
      ),
    );
  }
}

// ── Event detail bottom sheet ──────────────────────────────────────────────────
class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({
    required this.event,
    this.profile,
    this.onEdit,
    this.onEdited,
  });
  final CalEvent event;
  final ProfileModel? profile;
  final VoidCallback? onEdit;
  final ValueChanged<CalEvent>? onEdited;

  String _timeLabel() {
    if (event.isAllDay) return 'All day';
    String fmt(DateTime d) => AppTime.hm(d);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[event.start.month - 1]} ${event.start.day}  •  ${fmt(event.start)} – ${fmt(event.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        profile != null &&
        (profile!.isAdmin || profile!.isManager || profile!.isClient);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(event.title, style: AppTextStyles.headlineSm),
                ),
                if (event.assigneeInitials != null)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: event.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      event.assigneeInitials!,
                      style: AppTextStyles.labelMd.copyWith(color: event.color),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.access_time_outlined, text: _timeLabel()),
            if (event.roomName != null)
              _DetailRow(
                icon: Icons.meeting_room_outlined,
                text: 'Room: ${event.roomName}',
              ),
            if (event.clientName != null)
              _DetailRow(
                icon: Icons.business_outlined,
                text: event.clientName!,
              ),
            if (event.cost != null && event.cost! > 0)
              _DetailRow(
                icon: Icons.attach_money_outlined,
                text: 'Cost: \$${event.cost!.toStringAsFixed(2)}',
              ),
            if (event.attendeeNames.isNotEmpty)
              _DetailRow(
                icon: Icons.group_outlined,
                text: event.attendeeNames.join(', '),
              ),
            if (event.assigneeInitials != null && event.attendeeNames.isEmpty)
              _DetailRow(
                icon: Icons.person_outline,
                text: 'Assigned to ${event.assigneeInitials}',
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (canEdit) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onEdit?.call();
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Close'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.bodyMd)),
        ],
      ),
    );
  }
}

// ── Add event bottom sheet ─────────────────────────────────────────────────────
class _AddEventSheet extends StatefulWidget {
  const _AddEventSheet({
    required this.initialDate,
    required this.createdBy,
    required this.onCreated,
  });
  final DateTime initialDate;
  final String createdBy;
  final ValueChanged<CalEvent> onCreated;

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _titleCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  List<ClientModel> _clients = [];
  ClientModel? _selectedClient;

  List<Map<String, String>> _employees = [];
  final Set<String> _selectedEmployeeIds = {};

  List<String> _rooms = [];
  String? _selectedRoom;
  bool _loadingRooms = true;

  bool _loadingClients = true;
  bool _saving = false;

  late DateTime _startTime;
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    _startTime = DateTime(d.year, d.month, d.day, 10);
    _endTime = DateTime(d.year, d.month, d.day, 11);
    _fetchClients();
    _fetchEmployees();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    try {
      final data = await SupabaseService.adminClient
          .from('rooms')
          .select('name')
          .order('name');
      final names = (data as List)
          .map((r) => r['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (mounted)
        setState(() {
          _rooms = names;
          _loadingRooms = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchClients() async {
    final list = await ClientRepository.fetchClients();
    if (mounted)
      setState(() {
        _clients = list;
        _loadingClients = false;
      });
  }

  Future<void> _fetchEmployees() async {
    try {
      // adminClient: bypass RLS so every staff member (all teams) is listed.
      final data = await SupabaseService.adminClient
          .from('profiles')
          .select('id, full_name')
          .neq('role', 'client')
          .eq('status', 'active')
          .order('full_name');
      if (mounted) {
        setState(() {
          _employees = (data as List)
              .map(
                (m) => {
                  'id': m['id'] as String,
                  'name': m['full_name'] as String? ?? '',
                },
              )
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = TimeOfDay.fromDateTime(isStart ? _startTime : _endTime);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          picked.hour,
          picked.minute,
        );
      } else {
        _endTime = DateTime(
          _endTime.year,
          _endTime.month,
          _endTime.day,
          picked.hour,
          picked.minute,
        );
      }
    });
  }

  String _fmt(DateTime d) => AppTime.hm(d);

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final cost = double.tryParse(_costCtrl.text.trim());
    final attendeeIds = _selectedEmployeeIds.toList();

    await ClientRepository.createEvent(
      title: _titleCtrl.text.trim(),
      start: _startTime,
      end: _endTime,
      clientId: _selectedClient?.id,
      cost: cost,
      createdBy: widget.createdBy,
      attendeeIds: attendeeIds,
      roomName: _selectedRoom,
    );

    final selectedNames = _employees
        .where((e) => _selectedEmployeeIds.contains(e['id']))
        .map((e) => e['name']!)
        .toList();

    final newEvent = CalEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleCtrl.text.trim(),
      start: _startTime,
      end: _endTime,
      color: _selectedClient != null
          ? const Color(0xFFBA1A1A)
          : AppColors.primary,
      clientId: _selectedClient?.id,
      clientName: _selectedClient?.companyName,
      cost: cost,
      roomName: _selectedRoom,
      attendeeNames: selectedNames,
      assigneeInitials: selectedNames.isNotEmpty
          ? selectedNames.first.substring(0, 1).toUpperCase()
          : null,
    );

    if (mounted) {
      Navigator.pop(context);
      widget.onCreated(newEvent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('New Meeting / Event', style: AppTextStyles.headlineSm),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Event title *',
                prefixIcon: const Icon(Icons.title, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Time row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Start time',
                        prefixIcon: const Icon(Icons.access_time, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        _fmt(_startTime),
                        style: AppTextStyles.bodyMd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'End time',
                        prefixIcon: const Icon(
                          Icons.access_time_filled,
                          size: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(_fmt(_endTime), style: AppTextStyles.bodyMd),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Client picker
            if (_loadingClients)
              const LinearProgressIndicator()
            else if (_clients.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No clients — an admin must create clients first.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<ClientModel>(
                value: _selectedClient,
                decoration: InputDecoration(
                  labelText: 'Client (optional)',
                  prefixIcon: const Icon(Icons.business_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('— No client —'),
                  ),
                  ..._clients.map(
                    (c) =>
                        DropdownMenuItem(value: c, child: Text(c.companyName)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedClient = v),
              ),
            const SizedBox(height: 12),

            // Room picker
            if (_loadingRooms)
              const LinearProgressIndicator()
            else if (_rooms.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No rooms available — ask an admin to add rooms.',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedRoom,
                decoration: InputDecoration(
                  labelText: 'Meeting room (optional)',
                  prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('— No room —'),
                  ),
                  ..._rooms.map(
                    (r) => DropdownMenuItem(value: r, child: Text(r)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedRoom = v),
              ),
            const SizedBox(height: 12),

            // Cost
            TextField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Meeting cost (optional)',
                prefixIcon: const Icon(Icons.attach_money_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Employee multi-select
            if (_employees.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Attendees', style: AppTextStyles.labelMd),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _employees.map((e) {
                  final selected = _selectedEmployeeIds.contains(e['id']);
                  return FilterChip(
                    label: Text(e['name']!, style: AppTextStyles.bodySm),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedEmployeeIds.add(e['id']!);
                      } else {
                        _selectedEmployeeIds.remove(e['id']!);
                      }
                    }),
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    : const Text(
                        'Create event',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit event bottom sheet (manager & client only) ────────────────────────────
class _EditEventSheet extends StatefulWidget {
  const _EditEventSheet({
    required this.event,
    required this.createdBy,
    required this.onUpdated,
  });
  final CalEvent event;
  final String createdBy;
  final ValueChanged<CalEvent> onUpdated;

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _costCtrl;

  List<ClientModel> _clients = [];
  ClientModel? _selectedClient;

  List<Map<String, String>> _employees = [];
  final Set<String> _selectedEmployeeIds = {};

  List<String> _rooms = [];
  String? _selectedRoom;
  bool _loadingRooms = true;

  bool _loadingClients = true;
  bool _saving = false;

  late DateTime _startTime;
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleCtrl = TextEditingController(text: e.title);
    _costCtrl = TextEditingController(
      text: e.cost != null ? e.cost!.toStringAsFixed(2) : '',
    );
    _startTime = e.start;
    _endTime = e.end;
    _selectedRoom = e.roomName;
    _fetchClients();
    _fetchEmployees();
    _fetchRooms();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchClients() async {
    final list = await ClientRepository.fetchClients();
    if (!mounted) return;
    setState(() {
      _clients = list;
      _loadingClients = false;
      if (widget.event.clientId != null) {
        try {
          _selectedClient = list.firstWhere(
            (c) => c.id == widget.event.clientId,
          );
        } catch (_) {
          _selectedClient = null;
        }
      }
    });
  }

  Future<void> _fetchEmployees() async {
    try {
      // adminClient: bypass RLS so every staff member (all teams) is listed.
      final data = await SupabaseService.adminClient
          .from('profiles')
          .select('id, full_name')
          .neq('role', 'client')
          .eq('status', 'active')
          .order('full_name');
      if (mounted) {
        setState(() {
          _employees = (data as List)
              .map(
                (m) => {
                  'id': m['id'] as String,
                  'name': m['full_name'] as String? ?? '',
                },
              )
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchRooms() async {
    try {
      final data = await SupabaseService.adminClient
          .from('rooms')
          .select('name')
          .order('name');
      final names = (data as List)
          .map((r) => r['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (mounted)
        setState(() {
          _rooms = names;
          _loadingRooms = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = TimeOfDay.fromDateTime(isStart ? _startTime : _endTime);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          picked.hour,
          picked.minute,
        );
      } else {
        _endTime = DateTime(
          _endTime.year,
          _endTime.month,
          _endTime.day,
          picked.hour,
          picked.minute,
        );
      }
    });
  }

  String _fmt(DateTime d) => AppTime.hm(d);

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final cost = double.tryParse(_costCtrl.text.trim());
    final attendeeIds = _selectedEmployeeIds.toList();

    await ClientRepository.updateEvent(
      eventId: widget.event.id,
      title: _titleCtrl.text.trim(),
      start: _startTime,
      end: _endTime,
      clientId: _selectedClient?.id,
      cost: cost,
      roomName: _selectedRoom,
      attendeeIds: attendeeIds,
    );

    final selectedNames = _employees
        .where((e) => _selectedEmployeeIds.contains(e['id']))
        .map((e) => e['name']!)
        .toList();

    final updated = CalEvent(
      id: widget.event.id,
      title: _titleCtrl.text.trim(),
      start: _startTime,
      end: _endTime,
      color: _selectedClient != null
          ? const Color(0xFFBA1A1A)
          : AppColors.primary,
      clientId: _selectedClient?.id,
      clientName: _selectedClient?.companyName,
      cost: cost,
      roomName: _selectedRoom,
      attendeeNames: selectedNames.isNotEmpty
          ? selectedNames
          : widget.event.attendeeNames,
      assigneeInitials: selectedNames.isNotEmpty
          ? selectedNames.first.substring(0, 1).toUpperCase()
          : widget.event.assigneeInitials,
    );

    if (mounted) {
      Navigator.pop(context);
      widget.onUpdated(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Edit Meeting / Event', style: AppTextStyles.headlineSm),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Event title *',
                prefixIcon: const Icon(Icons.title, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Time row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Start time',
                        prefixIcon: const Icon(Icons.access_time, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        _fmt(_startTime),
                        style: AppTextStyles.bodyMd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'End time',
                        prefixIcon: const Icon(
                          Icons.access_time_filled,
                          size: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(_fmt(_endTime), style: AppTextStyles.bodyMd),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Client picker
            if (_loadingClients)
              const LinearProgressIndicator()
            else if (_clients.isNotEmpty)
              DropdownButtonFormField<ClientModel>(
                initialValue: _selectedClient,
                decoration: InputDecoration(
                  labelText: 'Client (optional)',
                  prefixIcon: const Icon(Icons.business_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('— No client —'),
                  ),
                  ..._clients.map(
                    (c) =>
                        DropdownMenuItem(value: c, child: Text(c.companyName)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedClient = v),
              ),
            const SizedBox(height: 12),

            // Room picker
            if (_loadingRooms)
              const LinearProgressIndicator()
            else if (_rooms.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 18,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No rooms available — ask an admin to add rooms.',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedRoom,
                decoration: InputDecoration(
                  labelText: 'Meeting room (optional)',
                  prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('— No room —'),
                  ),
                  ..._rooms.map(
                    (r) => DropdownMenuItem(value: r, child: Text(r)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedRoom = v),
              ),
            const SizedBox(height: 12),

            // Cost
            TextField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Meeting cost (optional)',
                prefixIcon: const Icon(Icons.attach_money_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Attendee multi-select
            if (_employees.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Attendees', style: AppTextStyles.labelMd),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _employees.map((e) {
                  final selected = _selectedEmployeeIds.contains(e['id']);
                  return FilterChip(
                    label: Text(e['name']!, style: AppTextStyles.bodySm),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedEmployeeIds.add(e['id']!);
                      } else {
                        _selectedEmployeeIds.remove(e['id']!);
                      }
                    }),
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manage Rooms sheet (admin only) ───────────────────────────────────────────
class _ManageRoomsSheet extends StatefulWidget {
  const _ManageRoomsSheet();

  @override
  State<_ManageRoomsSheet> createState() => _ManageRoomsSheetState();
}

class _ManageRoomsSheetState extends State<_ManageRoomsSheet> {
  final _nameCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  List<Map<String, String>> _rooms = []; // [{id, name}]
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseService.adminClient
          .from('rooms')
          .select('id, name')
          .order('name');
      if (mounted) {
        setState(() {
          _rooms = (data as List)
              .map(
                (r) => {
                  'id': r['id'].toString(),
                  'name': r['name'] as String? ?? '',
                },
              )
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Could not load rooms.';
        });
    }
  }

  Future<void> _addRoom() async {
    final name = _nameCtrl.text.trim();
    final capacity = int.tryParse(_capacityCtrl.text.trim());
    if (name.isEmpty || capacity == null || capacity <= 0) {
      setState(() => _error = 'Enter a valid room name and capacity (> 0).');
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.adminClient.from('rooms').insert({
        'name': name,
        'capacity': capacity,
      });
      _nameCtrl.clear();
      _capacityCtrl.clear();
      await _fetchRooms();
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Failed to add room.';
        });
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteRoom(String id) async {
    try {
      await SupabaseService.adminClient.from('rooms').delete().eq('id', id);
      await _fetchRooms();
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to delete room.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined, size: 20),
              const SizedBox(width: 10),
              Text('Manage Meeting Rooms', style: AppTextStyles.headlineSm),
            ],
          ),
          const SizedBox(height: 16),

          // Add room row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Room name',
                    hintText: 'e.g. Board Room',
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _addRoom(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _capacityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Capacity',
                    hintText: '10',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _addRoom(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _addRoom,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      )
                    : const Text(
                        'Add',
                        style: TextStyle(color: AppColors.gold),
                      ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
            ),
          ],

          const SizedBox(height: 16),

          // Room list
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            )
          else if (_rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No rooms yet. Add one above.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rooms.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppColors.outlineVariant),
                itemBuilder: (_, i) {
                  final room = _rooms[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.meeting_room_outlined,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    title: Text(room['name']!, style: AppTextStyles.bodyMd),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.error,
                      ),
                      tooltip: 'Delete room',
                      onPressed: () => _deleteRoom(room['id']!),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
