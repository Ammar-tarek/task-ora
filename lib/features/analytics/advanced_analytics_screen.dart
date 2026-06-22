// lib/features/analytics/advanced_analytics_screen.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/mock_data.dart';

class AdvancedAnalyticsScreen extends StatefulWidget {
  const AdvancedAnalyticsScreen({super.key});
  @override
  State<AdvancedAnalyticsScreen> createState() => _AdvancedAnalyticsScreenState();
}

class _AdvancedAnalyticsScreenState extends State<AdvancedAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Advanced Analytics'),
        bottom: TabBar(
          controller: _tabs,
          labelStyle: AppTextStyles.labelMd,
          unselectedLabelStyle: AppTextStyles.bodySm,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: const [
            Tab(text: 'Overview'), Tab(text: 'Tasks'), Tab(text: 'Team'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _OverviewTab(), _TasksTab(), _TeamTab(),
      ]),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6,
          children: [
            TStatCard(title: 'COMPLETION RATE', value: '76%', icon: Icons.pie_chart_outline, sub: '+4% MoM'),
            TStatCard(title: 'AVG VELOCITY', value: '8.4', icon: Icons.speed, sub: 'Tasks/week'),
            TStatCard(title: 'OVERDUE TASKS', value: '2', icon: Icons.warning_outlined, accent: true),
            TStatCard(title: 'ACTIVE SPRINTS', value: '3', icon: Icons.refresh, sub: 'Running'),
          ],
        ),
        const SizedBox(height: 24),
        Text('TASK COMPLETION OVER TIME', style: AppTextStyles.labelCaps),
        const SizedBox(height: 12),
        Container(
          height: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, 160),
            painter: _BarPainter(
              values: [0.4, 0.6, 0.5, 0.75, 0.65, 0.85, 0.76],
              labels: ['Nov','Dec','Jan','Feb','Mar','Apr','May'],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('PRIORITY DISTRIBUTION', style: AppTextStyles.labelCaps),
        const SizedBox(height: 12),
        _PriorityBar(),
      ]),
    );
  }
}

class _TasksTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tasks = MockData.tasks;
    final byTag = <String, int>{};
    for (final t in tasks) byTag[t.tag] = (byTag[t.tag] ?? 0) + 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TASKS BY CATEGORY', style: AppTextStyles.labelCaps),
        const SizedBox(height: 12),
        ...byTag.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 80, child: Text(e.key, style: AppTextStyles.bodyMd)),
            const SizedBox(width: 12),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: e.value / tasks.length, minHeight: 20,
                backgroundColor: AppColors.outlineVariant, color: AppColors.primary,
              ),
            )),
            const SizedBox(width: 8),
            Text('${e.value}', style: AppTextStyles.dataSm),
          ]),
        )),
        const SizedBox(height: 24),
        Text('STATUS BREAKDOWN', style: AppTextStyles.labelCaps),
        const SizedBox(height: 12),
        Row(children: [
          _DonutSlice(label: 'Done', count: MockData.doneTasks.length, color: AppColors.statusDone),
          const SizedBox(width: 12),
          _DonutSlice(label: 'In Progress', count: MockData.inProgressTasks.length, color: AppColors.statusInProgress),
          const SizedBox(width: 12),
          _DonutSlice(label: 'To Do', count: MockData.todoTasks.length, color: AppColors.statusTodo),
        ]),
      ]),
    );
  }
}

class _TeamTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tasksByUser = <String, int>{};
    for (final t in MockData.tasks) {
      tasksByUser[t.assignee] = (tasksByUser[t.assignee] ?? 0) + 1;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WORKLOAD DISTRIBUTION', style: AppTextStyles.labelCaps),
        const SizedBox(height: 12),
        ...tasksByUser.entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(children: [
            TAvatar(name: e.key, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.key, style: AppTextStyles.labelMd),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: e.value / 5, minHeight: 5,
                  backgroundColor: AppColors.outlineVariant, color: AppColors.gold,
                ),
              ),
            ])),
            const SizedBox(width: 12),
            Text('${e.value} tasks', style: AppTextStyles.dataSm),
          ]),
        )),
      ]),
    );
  }
}

class _DonutSlice extends StatelessWidget {
  const _DonutSlice({required this.label, required this.count, required this.color});
  final String label; final int count; final Color color;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text('$count', style: AppTextStyles.dataLg.copyWith(color: color, fontSize: 28)),
        Text(label, style: AppTextStyles.bodySm.copyWith(fontSize: 11), textAlign: TextAlign.center),
      ]),
    ));
  }
}

class _PriorityBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tasks = MockData.tasks;
    final high = tasks.where((t) => t.priority == 'High').length;
    final med  = tasks.where((t) => t.priority == 'Medium').length;
    final low  = tasks.where((t) => t.priority == 'Low').length;
    return Container(
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(flex: high, child: Container(color: AppColors.statusHigh,
          child: Center(child: Text('High $high', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))))),
        Expanded(flex: med, child: Container(color: AppColors.gold,
          child: Center(child: Text('Med $med', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600))))),
        Expanded(flex: low, child: Container(color: AppColors.statusDone,
          child: Center(child: Text('Low $low', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))))),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;
  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final barW = (size.width / n) * 0.5;
    final maxH = size.height - 24;
    for (var i = 0; i < n; i++) {
      final x = (i + 0.5) * (size.width / n);
      final h = values[i] * maxH;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barW / 2, maxH - h, barW, h),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()
        ..color = i == n - 1 ? AppColors.gold : AppColors.primary.withValues(alpha: 0.6));
      final tp = TextPainter(
        text: TextSpan(text: labels[i],
          style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 18));
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
