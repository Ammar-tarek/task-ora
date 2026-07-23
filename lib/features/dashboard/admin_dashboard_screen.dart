// lib/features/dashboard/admin_dashboard_screen.dart
// Fully live — fetches real data from Supabase on load.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/task_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/models/task_model.dart';
import '../../core/models/profile_model.dart';
import '../../core/theme/app_theme.dart';
import '../tasks/task_detail_sheet.dart';

// ── Cashback wisdom quotes ────────────────────────────────────────────────────
const _cashbackWisdoms = <String>[
  'Cashback turns every transaction into an opportunity — spend smart, earn smarter.',
  'Great cashback strategies start with understanding where every dirham goes.',
  'In cashback, consistency beats impulse — small returns compound into big wins.',
  'The best cashback is the one your customers never have to think about.',
  'Cashback isn\'t an expense — it\'s an investment in customer loyalty.',
  'Track, optimize, repeat — that\'s the cashback growth loop.',
  'Every return to a customer is a step toward lifetime value.',
  'Smart cashback programs turn first-time buyers into brand ambassadors.',
];

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  DashboardStats? _stats;
  List<TaskModel> _recentTasks = [];
  List<ProfileModel> _employees = [];
  bool _loading = true;
  String? _error;

  late final String _wisdom;

  @override
  void initState() {
    super.initState();
    _wisdom = _cashbackWisdoms[Random().nextInt(_cashbackWisdoms.length)];
    _load();
  }

  Future<void> _load({bool animate = true}) async {
    if (animate)
      setState(() {
        _loading = true;
        _error = null;
      });
    final profile = context.read<AuthNotifier>().profile;
    if (profile == null) {
      if (mounted)
        setState(() {
          _error = 'No profile found';
          _loading = false;
        });
      return;
    }

    // Fetch each data source independently so one failure doesn't kill the page.
    DashboardStats? stats;
    List<TaskModel> tasks = [];
    List<ProfileModel> employees = [];

    try {
      stats = await DashboardRepository.fetchStats(profile);
    } catch (_) {
      /* stats stays null — cards show 0 */
    }

    try {
      // Role-aware: admin=all, manager=their team, employee=assigned tasks.
      tasks = await TaskRepository.fetchTasksForProfile(profile);
    } catch (_) {
      /* tasks stays empty — shows "No data" */
    }

    try {
      // Only show members of the user's own team — not all profiles.
      final myTeams = await TeamRepository.fetchByLeadId(profile.id);
      final teamId = myTeams.isNotEmpty
          ? myTeams.first.id
          : profile.teamId; // fallback to assigned team
      if (teamId != null) {
        employees = await TeamRepository.fetchMembers(teamId);
      }
    } catch (_) {
      /* employees stays empty — shows "No data" */
    }

    if (mounted) {
      setState(() {
        _stats =
            stats ??
            const DashboardStats(
              totalTasks: 0,
              doneTasks: 0,
              inProgressTasks: 0,
              totalEmployees: 0,
              presentToday: 0,
              totalRevenue: 0,
              unreadNotifications: 0,
            );
        _recentTasks = tasks.take(5).toList();
        _employees = employees.take(6).toList();
        _loading = false;
      });
    }
  }

  /// True when all numeric stats are zero (fresh / empty database).
  bool get _isDataEmpty {
    if (_stats == null) return true;
    return _stats!.totalTasks == 0 &&
        _stats!.totalEmployees == 0 &&
        _stats!.totalRevenue == 0;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final isAdmin = profile?.isAdmin ?? false;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final dateStr = DateFormat('EEEE, d MMMM y').format(now);
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: AppColors.surfaceContainerLowest,
              elevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 16,
              title: Row(
                children: [
                  Container(
                    height: 38,
                    width: 64,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('CB TO-DO', style: AppTextStyles.headlineSm),
                ],
              ),
              actions: [
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_outlined),
                      if ((_stats?.unreadNotifications ?? 0) > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => context.push('/notifications'),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => context.push('/settings'),
                    child: TAvatar(name: profile?.fullName ?? '', size: 34),
                  ),
                ),
              ],
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: AppColors.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text('Could not load data', style: AppTextStyles.labelMd),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenW > 600 ? 24 : 16,
                  vertical: 16,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Greeting ────────────────────────────────────────────
                    Text(
                      '$greeting, ${profile?.firstName ?? ''} 👋',
                      style: AppTextStyles.displayMd.copyWith(
                        fontSize: screenW < 360 ? 24 : 32,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Wisdom Banner (shown when data is empty) ────────────
                    if (_isDataEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, Color(0xFF2C2600)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: AppColors.gold,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _wisdom,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.goldLight,
                                  fontStyle: FontStyle.italic,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Stats Grid (always visible — zeros when empty) ──────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth > 600
                            ? 4
                            : 2;
                        final ratio = constraints.maxWidth > 600 ? 1.8 : 1.45;
                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: ratio,
                          children: [
                            TStatCard(
                              title: 'TOTAL TASKS',
                              value: '${_stats?.totalTasks ?? 0}',
                              icon: Icons.assignment_outlined,
                              accent: true,
                              onTap: () => context.go('/tasks?filter=All'),
                            ),
                            TStatCard(
                              title: 'COMPLETED',
                              value: '${_stats?.doneTasks ?? 0}',
                              icon: Icons.check_circle_outline,
                              sub: (_stats != null && _stats!.totalTasks > 0)
                                  ? '${(_stats!.doneTasks / _stats!.totalTasks * 100).round()}%'
                                  : '0%',
                              onTap: () =>
                                  context.go('/tasks?filter=Completed'),
                            ),
                            TStatCard(
                              title: 'IN PROGRESS',
                              value: '${_stats?.inProgressTasks ?? 0}',
                              icon: Icons.loop,
                              sub: 'Active',
                              onTap: () =>
                                  context.go('/tasks?filter=In Progress'),
                            ),
                            TStatCard(
                              title: 'TEAM SIZE',
                              value: '${_stats?.totalEmployees ?? 0}',
                              icon: Icons.people_outline,
                              sub: '${_stats?.presentToday ?? 0} present',
                              onTap: () {
                                if (isAdmin) {
                                  context.push('/users');
                                } else if (profile?.teamId != null) {
                                  context.push(
                                    '/teams/${profile!.teamId}/members',
                                    extra: 'My Team',
                                  );
                                } else {
                                  context.push('/users');
                                }
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // ── Quick Actions ───────────────────────────────────────
                    TSectionHeader(title: 'Quick Actions'),
                    const SizedBox(height: 12),
                    _ResponsiveQuickActions(
                      screenWidth: screenW,
                      actions: [
                        _QuickActionData(
                          'Kanban Board',
                          Icons.view_kanban_outlined,
                          () => context.go('/tasks'),
                        ),
                        _QuickActionData(
                          'Analytics',
                          Icons.bar_chart,
                          () => context.push('/analytics'),
                        ),
                        _QuickActionData(
                          'Attendance',
                          Icons.how_to_reg_outlined,
                          () => context.push('/attendance'),
                        ),
                        // Finance & Expenses — admin only
                        if (isAdmin) ..._adminFinanceActions(context),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Overview cards (role-filtered) ─────────────────────
                    TSectionHeader(title: 'Overview'),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 500;
                        final cards = [
                          _OverviewCard(
                            icon: Icons.warning_amber_rounded,
                            iconColor: AppColors.statusHigh,
                            title: 'Recent Alerts',
                            value: (_stats?.unreadNotifications ?? 0) > 0
                                ? '${_stats!.unreadNotifications} unread'
                                : 'No data',
                            onTap: () => context.push('/notifications'),
                          ),
                          // Revenue card — admin only
                          if (isAdmin)
                            _OverviewCard(
                              icon: Icons.account_balance_wallet_outlined,
                              iconColor: AppColors.statusDone,
                              title: 'Total Revenue',
                              value: (_stats?.totalRevenue ?? 0) > 0
                                  ? '\$${NumberFormat.compact().format(_stats!.totalRevenue)}'
                                  : 'No data',
                              onTap: () => context.go('/finance'),
                            ),
                          _OverviewCard(
                            icon: Icons.how_to_reg_outlined,
                            iconColor: AppColors.statusInProgress,
                            title: 'Attendance Today',
                            value: (_stats?.presentToday ?? 0) > 0
                                ? '${_stats!.presentToday} present'
                                : 'No data',
                            onTap: () => context.push('/attendance'),
                          ),
                        ];
                        if (isWide) {
                          return Row(
                            children: cards
                                .map(
                                  (c) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: c != cards.last ? 10 : 0,
                                      ),
                                      child: c,
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        }
                        return Column(children: cards);
                      },
                    ),
                    const SizedBox(height: 24),

                    // ── Task Distribution Mini-Chart (always visible) ───────
                    TSectionHeader(title: 'Task Distribution'),
                    const SizedBox(height: 12),
                    _TaskDistributionBar(stats: _stats),
                    const SizedBox(height: 24),

                    // ── Recent Tasks (always visible) ───────────────────────
                    TSectionHeader(
                      title: 'Recent Tasks',
                      action: 'See All',
                      onAction: () => context.go('/tasks'),
                    ),
                    const SizedBox(height: 12),
                    if (_recentTasks.isEmpty)
                      _EmptyState(message: 'No data')
                    else
                      ..._recentTasks.map(
                        (t) => _TaskRow(
                          task: t,
                          onTap: () => _showDetailSheet(context, t.id),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // ── Team Members — admin only ────────────────────────────
                    if (isAdmin) ...[
                      TSectionHeader(
                        title: 'Team Members',
                        action: 'Manage',
                        onAction: () => context.push('/users'),
                      ),
                      const SizedBox(height: 12),
                      if (_employees.isEmpty)
                        _EmptyState(message: 'No data')
                      else
                        ..._employees.map((u) => _UserRow(user: u)),
                      const SizedBox(height: 24),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, String id) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          TaskDetailSheet(taskId: id, onUpdated: () => _load(animate: false)),
    );
  }
}

// ── Admin-only finance quick actions ──────────────────────────────────────────
List<_QuickActionData> _adminFinanceActions(BuildContext context) => [
  _QuickActionData(
    'Finance',
    Icons.account_balance_wallet_outlined,
    () => context.go('/finance'),
  ),
  _QuickActionData(
    'Expenses',
    Icons.receipt_long_outlined,
    () => context.push('/expenses'),
  ),
  _QuickActionData('Teams', Icons.group_outlined, () => context.push('/teams')),
];

// ── Supporting data class ──────────────────────────────────────────────────────
class _QuickActionData {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickActionData(this.label, this.icon, this.onTap);
}

// ── Responsive Quick Actions (wraps on small screens) ─────────────────────────
class _ResponsiveQuickActions extends StatelessWidget {
  const _ResponsiveQuickActions({
    required this.screenWidth,
    required this.actions,
  });
  final double screenWidth;
  final List<_QuickActionData> actions;

  @override
  Widget build(BuildContext context) {
    // On wider screens, wrap into a grid. On narrow, scroll horizontally.
    if (screenWidth > 500) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: actions
            .map(
              (a) => _QuickAction(label: a.label, icon: a.icon, onTap: a.onTap),
            )
            .toList(),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: actions
            .map(
              (a) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _QuickAction(
                  label: a.label,
                  icon: a.icon,
                  onTap: a.onTap,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Task Distribution Horizontal Bar ──────────────────────────────────────────
class _TaskDistributionBar extends StatelessWidget {
  const _TaskDistributionBar({required this.stats});
  final DashboardStats? stats;

  @override
  Widget build(BuildContext context) {
    final total = stats?.totalTasks ?? 0;
    final done = stats?.doneTasks ?? 0;
    final inProgress = stats?.inProgressTasks ?? 0;
    final todo = total - done - inProgress;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: total > 0
                  ? Row(
                      children: [
                        _barSegment(done / total, AppColors.statusDone),
                        _barSegment(
                          inProgress / total,
                          AppColors.statusInProgress,
                        ),
                        _barSegment(todo / total, AppColors.statusTodo),
                      ],
                    )
                  : Container(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          // Legend — wraps responsively
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend(context, AppColors.statusDone, 'Done', 'Completed', done),
              _legend(
                context,
                AppColors.statusInProgress,
                'In Progress',
                'In Progress',
                inProgress,
              ),
              _legend(
                context,
                AppColors.statusTodo,
                'To Do',
                'To Do',
                todo < 0 ? 0 : todo,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barSegment(double fraction, Color color) => Expanded(
    flex: (fraction * 100).round().clamp(1, 100),
    child: Container(color: color),
  );

  Widget _legend(
    BuildContext context,
    Color color,
    String label,
    String filterName,
    int count,
  ) => InkWell(
    onTap: () => context.go('/tasks?filter=$filterName'),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text('$label ($count)', style: AppTextStyles.bodySm),
        ],
      ),
    ),
  );
}

// ── Overview Info Card ────────────────────────────────────────────────────────
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodySm),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppTextStyles.labelMd.copyWith(
                      color: value == 'No data'
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Center(
      child: Text(
        message,
        style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
      ),
    ),
  );
}

// ── Quick Action Chip ─────────────────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.labelMd),
          ],
        ),
      ),
    );
  }
}

// ── Task Row ──────────────────────────────────────────────────────────────────
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, this.onTap});
  final TaskModel task;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: AppTextStyles.labelMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TAvatar(name: task.leadAssigneeName, size: 18),
                      Text(task.leadAssigneeName, style: AppTextStyles.bodySm),
                      Text(
                        '· ${task.dueDateDisplay}',
                        style: AppTextStyles.bodySm,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TPriorityBadge(priority: task.priorityLabel),
          ],
        ),
      ),
    );
  }
}

// ── User Row ──────────────────────────────────────────────────────────────────
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});
  final ProfileModel user;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          TAvatar(name: user.fullName, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: AppTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user.role,
                  style: AppTextStyles.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TStatusChip(
            label: user.isActive ? 'Active' : 'Inactive',
            color: user.isActive
                ? AppColors.statusDone
                : AppColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
