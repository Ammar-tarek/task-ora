// lib/features/super_admin/super_admin_report_screen.dart
// Master Detailed Report screen exclusive for Super Admin.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/repositories/super_admin_report_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/super_admin_pdf_exporter.dart';

class SuperAdminReportScreen extends StatefulWidget {
  const SuperAdminReportScreen({super.key});

  @override
  State<SuperAdminReportScreen> createState() => _SuperAdminReportScreenState();
}

class _SuperAdminReportScreenState extends State<SuperAdminReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  SuperAdminReportData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await SuperAdminReportRepository.fetchMasterReport();
      if (mounted) {
        setState(() {
          _data = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _showExportSummary() {
    if (_data == null) return;
    final d = _data!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.description_outlined, color: AppColors.gold),
            const SizedBox(width: 10),
            Text('Master Report Text Summary', style: AppTextStyles.headlineSm),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: SelectableText(
              '=== TASK ORA SUPER ADMIN MASTER REPORT ===\n'
              'Generated: ${DateTime.now().toLocal()}\n\n'
              '--- EXECUTIVE SUMMARY ---\n'
              'Total Tasks: ${d.totalTasks}\n'
              'Total Attendance Records: ${d.totalAttendanceRecords}\n'
              'Total Revenue: \$${d.totalRevenue.toStringAsFixed(2)}\n'
              'Total Expenses: \$${d.totalExpenses.toStringAsFixed(2)}\n'
              'Total Penalties: \$${d.totalPenalties.toStringAsFixed(2)}\n'
              'Net Balance: \$${d.netBalance.toStringAsFixed(2)}\n'
              'Total Comments: ${d.totalComments}\n\n'
              '--- TASKS SUMMARY ---\n'
              'Status Breakdown: ${d.tasksByStatus}\n'
              'Priority Breakdown: ${d.tasksByPriority}\n',
              style: AppTextStyles.bodySm.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Export Full PDF'),
            onPressed: () {
              Navigator.pop(ctx);
              SuperAdminPdfExporter.exportAndPrintPdf(_data!);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Super Admin Detailed Master Report'),
            Text(
              'Complete multi-page analytics & log records',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Export / Print PDF'),
              onPressed: _data == null
                  ? null
                  : () => SuperAdminPdfExporter.exportAndPrintPdf(_data!),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.text_snippet_outlined),
            tooltip: 'Text Summary',
            onPressed: _data == null ? null : _showExportSummary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Report',
            onPressed: _loadReport,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          indicatorColor: AppColors.gold,
          tabs: const [
            Tab(icon: Icon(Icons.pie_chart_outline, size: 18), text: 'Overview & Graphs'),
            Tab(icon: Icon(Icons.task_alt_outlined, size: 18), text: 'Tasks All Details'),
            Tab(icon: Icon(Icons.access_time_outlined, size: 18), text: 'Attendance Logs'),
            Tab(icon: Icon(Icons.attach_money_outlined, size: 18), text: 'Finance & Expenses'),
            Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Comments'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text('Error loading report: $_error', style: AppTextStyles.bodyMd),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadReport, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildTasksTab(),
                    _buildAttendanceTab(),
                    _buildFinanceTab(),
                    _buildCommentsTab(),
                  ],
                ),
    );
  }

  // ── 1. Overview & Graphs ──────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final d = _data!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards
          LayoutBuilder(
            builder: (ctx, constraints) {
              final crossCount = constraints.maxWidth > 900 ? 4 : 2;
              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.2,
                children: [
                  _kpiCard('Total Tasks', '${d.totalTasks}', Icons.check_circle_outline, AppColors.gold),
                  _kpiCard('Hours Logged', '${d.totalHoursWorked.toStringAsFixed(1)} h', Icons.timer_outlined, AppColors.statusInProgress),
                  _kpiCard('Net Financial Balance', '\$${d.netBalance.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined, d.netBalance >= 0 ? AppColors.statusDone : AppColors.error),
                  _kpiCard('Attendance Records', '${d.totalAttendanceRecords}', Icons.badge_outlined, AppColors.statusDone),
                  _kpiCard('Total Revenue', '\$${d.totalRevenue.toStringAsFixed(2)}', Icons.trending_up, AppColors.statusDone),
                  _kpiCard('Total Expenses', '\$${d.totalExpenses.toStringAsFixed(2)}', Icons.trending_down, AppColors.error),
                  _kpiCard('Penalties Sum', '\$${d.totalPenalties.toStringAsFixed(2)}', Icons.gavel, AppColors.gold),
                  _kpiCard('Total Comments', '${d.totalComments}', Icons.comment_outlined, AppColors.statusMedium),
                ],
              );
            },
          ),
          const SizedBox(height: 28),

          // Charts section
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              // Task Status Distribution Pie Chart
              _chartContainer(
                title: 'Task Status Breakdown',
                width: 380,
                height: 280,
                child: d.tasksByStatus.isEmpty
                    ? const Center(child: Text('No task data'))
                    : PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 40,
                          sections: d.tasksByStatus.entries.map((e) {
                            final color = _statusColor(e.key);
                            return PieChartSectionData(
                              color: color,
                              value: e.value.toDouble(),
                              title: '${e.key.toUpperCase()}\n(${e.value})',
                              radius: 50,
                              titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            );
                          }).toList(),
                        ),
                      ),
              ),

              // Attendance Ratio Pie Chart
              _chartContainer(
                title: 'Attendance Ratios',
                width: 380,
                height: 280,
                child: (d.presentCount + d.lateCount + d.absentCount) == 0
                    ? const Center(child: Text('No attendance data'))
                    : PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 40,
                          sections: [
                            PieChartSectionData(color: AppColors.statusDone, value: d.presentCount.toDouble(), title: 'Present (${d.presentCount})', radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
                            PieChartSectionData(color: AppColors.gold, value: d.lateCount.toDouble(), title: 'Late (${d.lateCount})', radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
                            PieChartSectionData(color: AppColors.error, value: d.absentCount.toDouble(), title: 'Absent (${d.absentCount})', radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Tasks & All Details ────────────────────────────────────────────────
  Widget _buildTasksTab() {
    final list = _data?.taskList ?? [];
    if (list.isEmpty) {
      return const Center(child: Text('No tasks found in system.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final t = list[i];
        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Title & Badges
                Row(
                  children: [
                    Expanded(
                      child: Text(t.title, style: AppTextStyles.headlineSm),
                    ),
                    _chip(t.priority.toUpperCase(), _priorityColor(t.priority)),
                    const SizedBox(width: 8),
                    _chip(t.status.toUpperCase(), _statusColor(t.status)),
                  ],
                ),
                if (t.description != null && t.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(t.description!, style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),

                // Progress Bar
                Row(
                  children: [
                    Text('Progress: ${t.completionPercentage}%', style: AppTextStyles.labelMd),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: t.completionPercentage / 100.0,
                          backgroundColor: AppColors.outlineVariant,
                          color: t.completionPercentage == 100 ? AppColors.statusDone : AppColors.gold,
                          minHeight: 8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // Details Grid: Client, Department / Team, Cost, Assignees
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    if (t.clientName != null)
                      _detailBadge(Icons.business, 'Client: ${t.clientName}'),
                    if (t.teamName != null)
                      _detailBadge(Icons.groups, 'Team: ${t.teamName}${t.department != null ? " (${t.department})" : ""}'),
                    if (t.cost != null)
                      _detailBadge(Icons.attach_money, 'Cost: \$${t.cost!.toStringAsFixed(2)}'),
                    if (t.dueDate != null)
                      _detailBadge(Icons.calendar_today, 'Due: ${t.dueDate!.substring(0, 10)}'),
                  ],
                ),
                const SizedBox(height: 10),

                // Assigned Employees
                if (t.assignees.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.people_outline, size: 16, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text('Assigned Employees: ', style: AppTextStyles.labelMd),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: t.assignees.map((a) {
                            return _chip('${a.name}${a.isLead ? " (Lead)" : ""}', a.isLead ? AppColors.gold : AppColors.primary);
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],

                // Task Specific Comments
                if (t.comments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Comments (${t.comments.length}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                        const SizedBox(height: 6),
                        ...t.comments.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• ${c.authorName}: "${c.content}"', style: AppTextStyles.bodySm),
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 3. Attendance Logs ────────────────────────────────────────────────────
  Widget _buildAttendanceTab() {
    final list = _data?.attendanceList ?? [];
    if (list.isEmpty) {
      return const Center(child: Text('No attendance records found.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Employee Name')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Check-In')),
            DataColumn(label: Text('Check-Out')),
            DataColumn(label: Text('Hours Logged')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Override / Type')),
          ],
          rows: list.map((a) {
            return DataRow(
              cells: [
                DataCell(Text(a.userName, style: AppTextStyles.labelMd)),
                DataCell(Text(a.date)),
                DataCell(Text(a.checkIn ?? '-')),
                DataCell(Text(a.checkOut ?? '-')),
                DataCell(Text('${a.hoursWorked.toStringAsFixed(1)} h')),
                DataCell(_chip(
                  a.status.toUpperCase(),
                  a.status == 'present'
                      ? AppColors.statusDone
                      : a.status == 'late'
                          ? AppColors.gold
                          : AppColors.error,
                )),
                DataCell(Text(a.isManual ? 'Manual Override' : 'Auto / WiFi')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 4. Finance & Expenses ─────────────────────────────────────────────────
  Widget _buildFinanceTab() {
    final d = _data!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Finance Summaries
          Row(
            children: [
              Expanded(child: _kpiCard('CRM Billed Revenue', '\$${d.totalRevenue.toStringAsFixed(2)}', Icons.trending_up, AppColors.statusDone)),
              const SizedBox(width: 16),
              Expanded(child: _kpiCard('Paid Revenue', '\$${d.totalPaidRevenue.toStringAsFixed(2)}', Icons.payments_outlined, AppColors.statusDone)),
              const SizedBox(width: 16),
              Expanded(child: _kpiCard('Total Expenses', '\$${d.totalExpenses.toStringAsFixed(2)}', Icons.trending_down, AppColors.error)),
            ],
          ),
          const SizedBox(height: 28),

          // CRM / Financial Entries Table
          Text('CRM & Financial Transactions', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.crmList.isEmpty
              ? const Text('No financial transactions recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Client')),
                      DataColumn(label: Text('Billed Amount')),
                      DataColumn(label: Text('Paid Amount')),
                      DataColumn(label: Text('Outstanding')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: d.crmList.map((c) => DataRow(cells: [
                      DataCell(Text(c.title, style: AppTextStyles.labelMd)),
                      DataCell(Text(c.clientName)),
                      DataCell(Text('\$${c.amount.toStringAsFixed(2)}')),
                      DataCell(Text('\$${c.paidAmount.toStringAsFixed(2)}')),
                      DataCell(Text('\$${c.outstanding.toStringAsFixed(2)}', style: TextStyle(color: c.outstanding > 0 ? AppColors.error : AppColors.statusDone))),
                      DataCell(_chip(c.status.toUpperCase(), c.status == 'paid' ? AppColors.statusDone : AppColors.gold)),
                    ])).toList(),
                  ),
                ),
          const SizedBox(height: 28),

          // Detailed Expense Items Table
          Text('Expense Entries', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.expenseList.isEmpty
              ? const Text('No expense items recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Recorded By')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: d.expenseList.map((e) => DataRow(cells: [
                      DataCell(_chip(e.categoryName, AppColors.gold)),
                      DataCell(Text(e.description.isNotEmpty ? e.description : '-')),
                      DataCell(Text('\$${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error))),
                      DataCell(Text(e.date)),
                      DataCell(Text(e.recordedByName)),
                      DataCell(_chip(e.status.toUpperCase(), AppColors.statusDone)),
                    ])).toList(),
                  ),
                ),
          const SizedBox(height: 28),

          // Penalties List
          Text('Penalties', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.penaltyList.isEmpty
              ? const Text('No penalties recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Employee Name')),
                      DataColumn(label: Text('Reason')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: d.penaltyList.map((p) => DataRow(cells: [
                      DataCell(Text(p.employeeName, style: AppTextStyles.labelMd)),
                      DataCell(Text(p.reason)),
                      DataCell(Text('\$${p.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.error))),
                      DataCell(Text(p.date)),
                      DataCell(_chip(p.status.toUpperCase(), AppColors.gold)),
                    ])).toList(),
                  ),
                ),
        ],
      ),
    );
  }

  // ── 5. Comments ───────────────────────────────────────────────────────────
  Widget _buildCommentsTab() {
    final list = _data?.commentsList ?? [];
    if (list.isEmpty) {
      return const Center(child: Text('No comments recorded across tasks.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final c = list[i];
        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.gold.withValues(alpha: 0.1),
              child: Text(
                c.authorName.isNotEmpty ? c.authorName[0].toUpperCase() : 'U',
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Text(c.authorName, style: AppTextStyles.labelMd),
                const SizedBox(width: 8),
                Text('on ${c.taskTitle}', style: AppTextStyles.bodySm.copyWith(color: AppColors.gold)),
              ],
            ),
            subtitle: Text(c.content, style: AppTextStyles.bodyMd),
            trailing: Text(
              c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _detailBadge(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: AppTextStyles.bodySm),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.headlineSm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartContainer({required String title, required double width, required double height, required Widget child}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelMd),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'completed':
        return AppColors.statusDone;
      case 'in_progress':
        return AppColors.statusInProgress;
      case 'in_review':
        return AppColors.gold;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.statusMedium;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.gold;
      default:
        return AppColors.statusDone;
    }
  }
}
