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
  bool _exportingPdf = false;
  SuperAdminReportData? _data;
  String? _error;

  String _selectedFilterKey = 'all_time';
  String _filterLabel = 'All Time';
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _monthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(m - 1) % 12];
  }

  void _applyFilter(String key, {DateTimeRange? customRange, String? customLabel}) {
    final now = DateTime.now();
    DateTimeRange? range;
    String label = 'All Time';

    switch (key) {
      case 'all_time':
        range = null;
        label = 'All Time';
        break;
      case 'this_month':
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        range = DateTimeRange(start: start, end: end);
        label = 'This Month (${_monthName(now.month)} ${now.year})';
        break;
      case '3_months':
        final start = DateTime(now.year, now.month - 2, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        range = DateTimeRange(start: start, end: end);
        label = 'Last 3 Months';
        break;
      case '6_months':
        final start = DateTime(now.year, now.month - 5, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        range = DateTimeRange(start: start, end: end);
        label = 'Last 6 Months';
        break;
      case '1_year':
        final start = DateTime(now.year - 1, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        range = DateTimeRange(start: start, end: end);
        label = 'Last 1 Year';
        break;
      case 'custom':
        range = customRange;
        label = customLabel ?? 'Custom Range';
        break;
    }

    setState(() {
      _selectedFilterKey = key;
      _filterLabel = label;
      _selectedDateRange = range;
    });

    _loadReport();
  }

  void _showMonthPicker() {
    final now = DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) {
        int selectedYear = now.year;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Specific Month', style: AppTextStyles.headlineSm),
                  DropdownButton<int>(
                    value: selectedYear,
                    dropdownColor: AppColors.surfaceContainerLowest,
                    underline: const SizedBox(),
                    items: [for (int y = now.year; y >= now.year - 5; y--) y]
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y', style: AppTextStyles.bodyMd)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedYear = v);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final monthNum = index + 1;
                    final mName = _monthName(monthNum);
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(ctx);
                        final start = DateTime(selectedYear, monthNum, 1);
                        final end = DateTime(selectedYear, monthNum + 1, 0);
                        _applyFilter(
                          'custom',
                          customRange: DateTimeRange(start: start, end: end),
                          customLabel: '$mName $selectedYear',
                        );
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(mName, style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.surfaceContainerLow,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final startStr = '${picked.start.year}-${picked.start.month.toString().padLeft(2, '0')}-${picked.start.day.toString().padLeft(2, '0')}';
      final endStr = '${picked.end.year}-${picked.end.month.toString().padLeft(2, '0')}-${picked.end.day.toString().padLeft(2, '0')}';
      _applyFilter('custom', customRange: picked, customLabel: '$startStr to $endStr');
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await SuperAdminReportRepository.fetchMasterReport(
        dateRange: _selectedDateRange,
        filterTitle: _filterLabel,
      );
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

  Future<void> _exportPdf() async {
    if (_data == null || _exportingPdf) return;
    setState(() => _exportingPdf = true);

    try {
      await SuperAdminPdfExporter.exportAndPrintPdf(_data!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
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
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              '=== TASK ORA SUPER ADMIN MASTER REPORT ===\n'
              'Generated: ${DateTime.now().toLocal()}\n\n'
              '--- EXECUTIVE SUMMARY ---\n'
              'Total Employees: ${d.userList.length}\n'
              'Total Clients: ${d.clientList.length}\n'
              'Total Tasks: ${d.totalTasks}\n'
              'Total Attendance Records: ${d.totalAttendanceRecords}\n'
              'Total Hours Logged: ${d.totalHoursWorked.toStringAsFixed(1)} h\n'
              'Total Billed Revenue: \$${d.totalRevenue.toStringAsFixed(2)}\n'
              'Total Paid Revenue: \$${d.totalPaidRevenue.toStringAsFixed(2)}\n'
              'Total Expenses: \$${d.totalExpenses.toStringAsFixed(2)}\n'
              'Total Penalties: \$${d.totalPenalties.toStringAsFixed(2)}\n'
              'Net Financial Balance: \$${d.netBalance.toStringAsFixed(2)}\n'
              'Total Task Comments: ${d.totalComments}\n\n'
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
              _exportPdf();
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
            const Text('Super Admin Master Detailed Report'),
            Text(
              'Complete multi-page analytics & un-truncated logs',
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
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_exportingPdf ? 'Generating...' : 'Export / Print PDF'),
              onPressed: (_data == null || _exportingPdf) ? null : _exportPdf,
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
            Tab(icon: Icon(Icons.pie_chart_outline, size: 18), text: 'Overview & KPI'),
            Tab(icon: Icon(Icons.badge_outlined, size: 18), text: 'Staff & Clients'),
            Tab(icon: Icon(Icons.task_alt_outlined, size: 18), text: 'Tasks All Details'),
            Tab(icon: Icon(Icons.access_time_outlined, size: 18), text: 'Attendance & Daily Reports'),
            Tab(icon: Icon(Icons.attach_money_outlined, size: 18), text: 'Finance & Expenses'),
            Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Comments Feed'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading
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
                          _buildStaffAndClientsTab(),
                          _buildTasksTab(),
                          _buildAttendanceTab(),
                          _buildFinanceTab(),
                          _buildCommentsTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: AppColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.tune_outlined, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Text('Period Filter: ', style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface)),
            const SizedBox(width: 8),
            _filterChip('All Time', 'all_time'),
            const SizedBox(width: 6),
            _filterChip('This Month', 'this_month'),
            const SizedBox(width: 6),
            _filterChip('Last 3 Months', '3_months'),
            const SizedBox(width: 6),
            _filterChip('Last 6 Months', '6_months'),
            const SizedBox(width: 6),
            _filterChip('Last 1 Year', '1_year'),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.gold),
              label: Text(
                _selectedFilterKey == 'custom' && !_filterLabel.contains('to') ? 'Month: $_filterLabel' : 'Specific Month...',
                style: AppTextStyles.bodySm.copyWith(
                  color: _selectedFilterKey == 'custom' && !_filterLabel.contains('to') ? AppColors.gold : AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: _selectedFilterKey == 'custom' && !_filterLabel.contains('to') ? AppColors.primary : AppColors.surfaceHigh,
              onPressed: _showMonthPicker,
            ),
            const SizedBox(width: 6),
            ActionChip(
              avatar: const Icon(Icons.date_range_outlined, size: 16, color: AppColors.gold),
              label: Text(
                _selectedFilterKey == 'custom' && _filterLabel.contains('to') ? 'Range: $_filterLabel' : 'Custom Range...',
                style: AppTextStyles.bodySm.copyWith(
                  color: _selectedFilterKey == 'custom' && _filterLabel.contains('to') ? AppColors.gold : AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: _selectedFilterKey == 'custom' && _filterLabel.contains('to') ? AppColors.primary : AppColors.surfaceHigh,
              onPressed: _pickCustomDateRange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    final selected = _selectedFilterKey == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.gold,
      backgroundColor: AppColors.surfaceHigh,
      labelStyle: AppTextStyles.bodySm.copyWith(
        color: selected ? Colors.black : AppColors.onSurface,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => _applyFilter(key),
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
              final crossCount = constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 3 : 2);
              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 2.2,
                children: [
                  _kpiCard('Total Tasks', '${d.totalTasks}', Icons.check_circle_outline, AppColors.gold),
                  _kpiCard('Hours Logged', '${d.totalHoursWorked.toStringAsFixed(1)} h', Icons.timer_outlined, AppColors.statusInProgress),
                  _kpiCard('Net Balance', '\$${d.netBalance.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined, d.netBalance >= 0 ? AppColors.statusDone : AppColors.error),
                  _kpiCard('Attendance Logs', '${d.totalAttendanceRecords}', Icons.badge_outlined, AppColors.statusDone),
                  _kpiCard('Total Revenue', '\$${d.totalRevenue.toStringAsFixed(2)}', Icons.trending_up, AppColors.statusDone),
                  _kpiCard('Paid Revenue', '\$${d.totalPaidRevenue.toStringAsFixed(2)}', Icons.payments_outlined, AppColors.statusDone),
                  _kpiCard('Total Expenses', '\$${d.totalExpenses.toStringAsFixed(2)}', Icons.trending_down, AppColors.error),
                  _kpiCard('Penalties Sum', '\$${d.totalPenalties.toStringAsFixed(2)}', Icons.gavel, AppColors.gold),
                  _kpiCard('Staff / Employees', '${d.userList.length}', Icons.people_alt_outlined, AppColors.statusInProgress),
                  _kpiCard('Active Clients', '${d.clientList.length}', Icons.business_outlined, AppColors.gold),
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

  // ── 2. Staff & Clients Directory ─────────────────────────────────────────
  Widget _buildStaffAndClientsTab() {
    final d = _data!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Staff & Employees Master Directory (${d.userList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.userList.isEmpty
              ? const Text('No staff members registered.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Full Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Department')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: d.userList.map((u) => DataRow(cells: [
                        DataCell(Text(u.fullName, style: AppTextStyles.labelMd)),
                        DataCell(Text(u.email.isNotEmpty ? u.email : '-')),
                        DataCell(_chip(u.role.toUpperCase(), AppColors.gold)),
                        DataCell(Text(u.department)),
                        DataCell(Text(u.phone ?? '-')),
                        DataCell(_chip(u.isActive ? 'Active' : 'Inactive', u.isActive ? AppColors.statusDone : AppColors.error)),
                      ])).toList(),
                    ),
                  ),
                ),
          const SizedBox(height: 28),

          Text('Clients Directory (${d.clientList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.clientList.isEmpty
              ? const Text('No client profiles registered.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Company Name')),
                        DataColumn(label: Text('Contact Person')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Notes')),
                      ],
                      rows: d.clientList.map((c) => DataRow(cells: [
                        DataCell(Text(c.companyName, style: AppTextStyles.labelMd)),
                        DataCell(Text(c.contactName ?? '-')),
                        DataCell(Text(c.email ?? '-')),
                        DataCell(Text(c.phone ?? '-')),
                        DataCell(_chip(c.status.toUpperCase(), AppColors.statusDone)),
                        DataCell(Text(c.notes ?? '-')),
                      ])).toList(),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── 3. Tasks & All Details ────────────────────────────────────────────────
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

                // Details Grid: Client, Department / Team, Cost, Dates, Creator
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    if (t.clientName != null)
                      _detailBadge(Icons.business, 'Client: ${t.clientName}'),
                    if (t.teamName != null)
                      _detailBadge(Icons.groups, 'Team: ${t.teamName}${t.department != null ? " (${t.department})" : ""}'),
                    if (t.createdByName != null)
                      _detailBadge(Icons.person_outline, 'Created By: ${t.createdByName}'),
                    if (t.cost != null)
                      _detailBadge(Icons.attach_money, 'Cost: \$${t.cost!.toStringAsFixed(2)}'),
                    if (t.startDate != null)
                      _detailBadge(Icons.play_arrow_outlined, 'Start: ${t.startDate!.length >= 10 ? t.startDate!.substring(0, 10) : t.startDate}'),
                    if (t.dueDate != null)
                      _detailBadge(Icons.calendar_today, 'Due: ${t.dueDate!.length >= 10 ? t.dueDate!.substring(0, 10) : t.dueDate}'),
                    if (t.createdAt != null)
                      _detailBadge(Icons.schedule, 'Created: ${t.createdAt!.length >= 10 ? t.createdAt!.substring(0, 10) : t.createdAt}'),
                    if (t.attachmentUrl != null && t.attachmentUrl!.isNotEmpty)
                      _detailBadge(Icons.attach_file, 'Attachment: ${t.attachmentUrl}'),
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
                      Text('Assigned Staff (${t.assignees.length}): ', style: AppTextStyles.labelMd),
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
                ] else ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 16, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('Assigned Staff: Unassigned', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
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
                              child: Text('• ${c.authorName} (${c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt}): "${c.content}"', style: AppTextStyles.bodySm),
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

  // ── 4. Attendance & Employee Daily Work Reports ─────────────────────────
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Employee Name')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Check-In')),
              DataColumn(label: Text('Check-Out')),
              DataColumn(label: Text('Hours Logged')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Override / Method')),
              DataColumn(label: Text('Daily Written Work Report')),
            ],
            rows: list.map((a) {
              final String reportTxt = (a.dailyReport != null && a.dailyReport!.isNotEmpty)
                  ? a.dailyReport!
                  : (a.notes ?? 'No report submitted');
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
                  DataCell(Text(a.isManual ? 'Manual Override' : (a.wifiSsid != null ? 'WiFi (${a.wifiSsid})' : 'Auto'))),
                  DataCell(
                    SizedBox(
                      width: 250,
                      child: Text(
                        reportTxt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── 5. Finance & Expenses ─────────────────────────────────────────────────
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
          Text('CRM & Financial Transactions (${d.crmList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.crmList.isEmpty
              ? const Text('No financial transactions recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Invoice # / Title')),
                        DataColumn(label: Text('Client')),
                        DataColumn(label: Text('Billed Amount')),
                        DataColumn(label: Text('Paid Amount')),
                        DataColumn(label: Text('Outstanding')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Due Date')),
                        DataColumn(label: Text('Notes')),
                      ],
                      rows: d.crmList.map((c) => DataRow(cells: [
                        DataCell(Text(c.invoiceNumber != null ? '[#${c.invoiceNumber}] ${c.title}' : c.title, style: AppTextStyles.labelMd)),
                        DataCell(Text(c.clientName)),
                        DataCell(Text('\$${c.amount.toStringAsFixed(2)}')),
                        DataCell(Text('\$${c.paidAmount.toStringAsFixed(2)}')),
                        DataCell(Text('\$${c.outstanding.toStringAsFixed(2)}', style: TextStyle(color: c.outstanding > 0 ? AppColors.error : AppColors.statusDone))),
                        DataCell(_chip(c.status.toUpperCase(), c.status == 'paid' ? AppColors.statusDone : AppColors.gold)),
                        DataCell(Text(c.dueDate != null ? (c.dueDate!.length >= 10 ? c.dueDate!.substring(0, 10) : c.dueDate!) : '-')),
                        DataCell(Text(c.notes ?? '-')),
                      ])).toList(),
                    ),
                  ),
                ),
          const SizedBox(height: 28),

          // Detailed Expense Items Table
          Text('Expense Entries (${d.expenseList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.expenseList.isEmpty
              ? const Text('No expense items recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Description')),
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Recorded By')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Receipt')),
                      ],
                      rows: d.expenseList.map((e) => DataRow(cells: [
                        DataCell(_chip(e.categoryName, AppColors.gold)),
                        DataCell(Text(e.description.isNotEmpty ? e.description : '-')),
                        DataCell(Text('\$${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error))),
                        DataCell(Text(e.date)),
                        DataCell(Text(e.recordedByName)),
                        DataCell(_chip(e.status.toUpperCase(), AppColors.statusDone)),
                        DataCell(Text(e.receiptUrl != null ? 'Attached' : '-')),
                      ])).toList(),
                    ),
                  ),
                ),
          const SizedBox(height: 28),

          // Penalties List
          Text('Penalties Log (${d.penaltyList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.penaltyList.isEmpty
              ? const Text('No penalties recorded.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Employee Name')),
                        DataColumn(label: Text('Reason')),
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Notes')),
                      ],
                      rows: d.penaltyList.map((p) => DataRow(cells: [
                        DataCell(Text(p.employeeName, style: AppTextStyles.labelMd)),
                        DataCell(Text(p.reason)),
                        DataCell(Text('\$${p.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.error))),
                        DataCell(Text(p.date)),
                        DataCell(_chip(p.status.toUpperCase(), AppColors.gold)),
                        DataCell(Text(p.notes ?? '-')),
                      ])).toList(),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── 6. Comments ───────────────────────────────────────────────────────────
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
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
