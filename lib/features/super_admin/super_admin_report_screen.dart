// lib/features/super_admin/super_admin_report_screen.dart
// Master Detailed Report screen exclusive for Super Admin.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/repositories/app_settings_repository.dart';
import '../../core/repositories/super_admin_report_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/super_admin_pdf_exporter.dart';
import '../tasks/task_detail_sheet.dart';

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

  // Cutoff date state
  String? _currentCutoffDate;
  bool _savingCutoff = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadCutoffDate();
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCutoffDate() async {
    final date = await AppSettingsRepository.getWorkDataCutoffDate();
    if (mounted) {
      setState(() => _currentCutoffDate = (date != null && date.trim().isNotEmpty) ? date.trim() : null);
    }
  }

  Future<void> _pickAndSaveCutoffDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      if (!mounted) return;
      final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _savingCutoff = true);
      try {
        final profile = context.read<AuthNotifier>().profile;
        await AppSettingsRepository.setWorkDataCutoffDate(dateStr, updatedBy: profile?.id);
        if (mounted) {
          setState(() {
            _currentCutoffDate = dateStr;
            _savingCutoff = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cutoff date set to $dateStr. Older work data will be hidden for non-Super-Admin roles.'),
              backgroundColor: AppColors.statusDone,
            ),
          );
        }
      } catch (e) {
        if (mounted) setState(() => _savingCutoff = false);
      }
    }
  }

  Future<void> _clearCutoffDate() async {
    setState(() => _savingCutoff = true);
    try {
      final profile = context.read<AuthNotifier>().profile;
      await AppSettingsRepository.clearWorkDataCutoffDate(updatedBy: profile?.id);
      if (mounted) {
        setState(() {
          _currentCutoffDate = null;
          _savingCutoff = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cutoff date cleared. Non-Super-Admins can view all historical work data.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _savingCutoff = false);
    }
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
    final isDark = AppColors.isDark;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final colorScheme = isDark
            ? ColorScheme.dark(
                primary: AppColors.gold,
                onPrimary: Colors.black,
                surface: AppColors.surfaceContainerLowest,
                onSurface: AppColors.onSurface,
              )
            : ColorScheme.light(
                primary: AppColors.gold,
                onPrimary: Colors.white,
                surface: AppColors.surfaceContainerLowest,
                onSurface: AppColors.onSurface,
              );
        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: colorScheme,
            dialogTheme: DialogThemeData(backgroundColor: AppColors.surfaceContainerLowest),
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
              'Total Departments: ${d.tasksByDepartment.length}\n'
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
              'Complete multi-page analytics & un-truncated dossiers',
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
            Tab(icon: Icon(Icons.category_outlined, size: 18), text: 'Tasks by Department'),
            Tab(icon: Icon(Icons.badge_outlined, size: 18), text: 'Staff & Employee Dossiers'),
            Tab(icon: Icon(Icons.access_time_outlined, size: 18), text: 'Attendance per Employee'),
            Tab(icon: Icon(Icons.business_outlined, size: 18), text: 'Client Dossiers & Meetings'),
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
                    : RefreshIndicator(
                        onRefresh: _loadReport,
                        color: AppColors.gold,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildTasksByDepartmentTab(),
                            _buildStaffAndEmployeeDossiersTab(),
                            _buildAttendancePerEmployeeTab(),
                            _buildClientDossiersTab(),
                            _buildFinanceTab(),
                            _buildCommentsTab(),
                          ],
                        ),
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

  // ── 1. Overview & Graphs + Super Admin Cutoff Control ─────────────────────
  Widget _buildOverviewTab() {
    final d = _data!;
    final isSuperAdmin = context.watch<AuthNotifier>().profile?.isSuperAdmin == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Super Admin Cutoff Control Banner
          if (isSuperAdmin) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_clock_outlined, color: AppColors.gold, size: 22),
                      const SizedBox(width: 10),
                      Text('Super Admin Control: Previous Work Data Cutoff', style: AppTextStyles.headlineSm.copyWith(fontSize: 16)),
                      const Spacer(),
                      if (_currentCutoffDate != null)
                        Chip(
                          label: Text('Active Cutoff: $_currentCutoffDate', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          backgroundColor: AppColors.gold,
                          labelStyle: const TextStyle(color: Colors.black),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Select a specific date to hide previous month/period work data (tasks, finance, attendance, expenses) for all non-Super-Admin roles (Admins, Managers, Employees, Clients). The Super Admin will retain full access to all historical data.',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                        ),
                        icon: _savingCutoff
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Choose Cutoff Date'),
                        onPressed: _savingCutoff ? null : _pickAndSaveCutoffDate,
                      ),
                      if (_currentCutoffDate != null) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Cutoff (Show All Data)'),
                          onPressed: _savingCutoff ? null : _clearCutoffDate,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],

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
                  _kpiCard('Departments', '${d.tasksByDepartment.length}', Icons.category_outlined, AppColors.statusInProgress),
                  _kpiCard('Hours Logged', '${d.totalHoursWorked.toStringAsFixed(1)} h', Icons.timer_outlined, AppColors.statusDone),
                  _kpiCard('Net Balance', '\$${d.netBalance.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined, d.netBalance >= 0 ? AppColors.statusDone : AppColors.error),
                  _kpiCard('Total Revenue', '\$${d.totalRevenue.toStringAsFixed(2)}', Icons.trending_up, AppColors.statusDone),
                  _kpiCard('Paid Revenue', '\$${d.totalPaidRevenue.toStringAsFixed(2)}', Icons.payments_outlined, AppColors.statusDone),
                  _kpiCard('Total Expenses', '\$${d.totalExpenses.toStringAsFixed(2)}', Icons.trending_down, AppColors.error),
                  _kpiCard('Penalties Sum', '\$${d.totalPenalties.toStringAsFixed(2)}', Icons.gavel, AppColors.gold),
                  _kpiCard('Staff / Employees', '${d.userList.length}', Icons.people_alt_outlined, AppColors.statusInProgress),
                  _kpiCard('Active Clients', '${d.clientList.length}', Icons.business_outlined, AppColors.gold),
                  _kpiCard('Scheduled Meetings', '${d.meetingList.length}', Icons.event_outlined, AppColors.statusDone),
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

  // ── 2. Tasks Categorized by Department ───────────────────────────────────
  Widget _buildTasksByDepartmentTab() {
    final deptMap = _data?.tasksByDepartment ?? {};
    if (deptMap.isEmpty) {
      return const Center(child: Text('No task data found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: deptMap.length,
      separatorBuilder: (_, _) => const SizedBox(height: 20),
      itemBuilder: (ctx, i) {
        final entry = deptMap.entries.elementAt(i);
        final deptName = entry.key;
        final tasks = entry.value;

        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Department: ${deptName.toUpperCase()}', style: AppTextStyles.headlineSm.copyWith(color: AppColors.gold)),
                    _chip('${tasks.length} Tasks', AppColors.primary),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Task Title')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Priority')),
                      DataColumn(label: Text('Progress')),
                      DataColumn(label: Text('Assigned Staff')),
                      DataColumn(label: Text('Due Date')),
                    ],
                    rows: tasks.map((t) {
                      final assigneesStr = t.assignees.isNotEmpty
                          ? t.assignees.map((a) => a.name).join(', ')
                          : 'Unassigned';
                      return DataRow(cells: [
                        DataCell(Text(t.title, style: AppTextStyles.labelMd)),
                        DataCell(_chip(t.status.toUpperCase(), _statusColor(t.status))),
                        DataCell(_chip(t.priority.toUpperCase(), _priorityColor(t.priority))),
                        DataCell(Text('${t.completionPercentage}%')),
                        DataCell(Text(assigneesStr)),
                        DataCell(Text(t.dueDate != null ? (t.dueDate!.length >= 10 ? t.dueDate!.substring(0, 10) : t.dueDate!) : '-')),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 3. Staff Directory & Detailed Employee Dossiers ──────────────────────
  Widget _buildStaffAndEmployeeDossiersTab() {
    final dossiers = _data?.employeeDossiers ?? [];
    if (dossiers.isEmpty) {
      return const Center(child: Text('No staff registered.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: dossiers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (ctx, i) {
        final d = dossiers[i];
        final u = d.user;

        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(u.fullName, style: AppTextStyles.headlineSm),
                    Row(
                      children: [
                        _chip(u.role.toUpperCase(), AppColors.gold),
                        const SizedBox(width: 6),
                        _chip(u.department, AppColors.primary),
                        const SizedBox(width: 6),
                        _chip(u.isActive ? 'Active' : 'Inactive', u.isActive ? AppColors.statusDone : AppColors.error),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Email: ${u.email.isNotEmpty ? u.email : "-"}   |   Phone: ${u.phone ?? "-"}', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                Text('Assigned Tasks (${d.assignedTasks.length}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                const SizedBox(height: 6),
                d.assignedTasks.isEmpty
                    ? Text('No tasks assigned.', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant))
                    : Column(
                        children: d.assignedTasks.map((t) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.title, style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold)),
                            subtitle: Text('Status: ${t.status.toUpperCase()} (${t.completionPercentage}%) - Progress/Accomplishment: ${t.description ?? "N/A"}'),
                            trailing: _chip(t.priority.toUpperCase(), _priorityColor(t.priority)),
                          );
                        }).toList(),
                      ),
                const SizedBox(height: 12),

                Text('Attendance Summary (${d.attendanceLogs.length} logs, Total Logged: ${d.totalHours.toStringAsFixed(1)} h):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                const SizedBox(height: 6),
                d.attendanceLogs.isEmpty
                    ? Text('No attendance recorded.', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: d.attendanceLogs.take(5).map((a) {
                          return Chip(
                            backgroundColor: AppColors.surfaceHigh,
                            label: Text('${a.date}: In ${a.checkIn12h} - Out ${a.checkOut12h} (${a.hoursWorked.toStringAsFixed(1)}h)', style: AppTextStyles.bodySm),
                          );
                        }).toList(),
                      ),

                if (d.penalties.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Penalties Issued (${d.penalties.length}, Total: \$${d.totalPenalties.toStringAsFixed(2)}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.error)),
                  const SizedBox(height: 4),
                  ...d.penalties.map((p) => Text('• ${p.date} - \$${p.amount.toStringAsFixed(2)}: ${p.reason} (${p.status})', style: AppTextStyles.bodySm)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 4. Attendance Tables per Employee (12-hour format & Date column) ──────
  Widget _buildAttendancePerEmployeeTab() {
    final dossiers = (_data?.employeeDossiers ?? []).where((d) => d.attendanceLogs.isNotEmpty).toList();
    if (dossiers.isEmpty) {
      return const Center(child: Text('No attendance records logged.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: dossiers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (ctx, i) {
        final d = dossiers[i];

        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Attendance Table: ${d.user.fullName}', style: AppTextStyles.headlineSm.copyWith(color: AppColors.gold)),
                    _chip('${d.attendanceLogs.length} Records', AppColors.primary),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date (YYYY-MM-DD)')),
                      DataColumn(label: Text('Check In (12h)')),
                      DataColumn(label: Text('Check Out (12h)')),
                      DataColumn(label: Text('Hours Logged')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Method')),
                      DataColumn(label: Text('Daily Work Report / Notes')),
                    ],
                    rows: d.attendanceLogs.map((a) => DataRow(cells: [
                      DataCell(Text(a.date, style: AppTextStyles.labelMd)),
                      DataCell(Text(a.checkIn12h)),
                      DataCell(Text(a.checkOut12h)),
                      DataCell(Text('${a.hoursWorked.toStringAsFixed(1)} h')),
                      DataCell(_chip(a.status.toUpperCase(), a.status == 'present' ? AppColors.statusDone : AppColors.gold)),
                      DataCell(Text(a.isManual ? 'Manual' : (a.wifiSsid != null ? 'WiFi' : 'Auto'))),
                      DataCell(Text(a.dailyReport ?? a.notes ?? '-')),
                    ])).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 5. Client Dossiers & Scheduled Meetings ──────────────────────────────
  Widget _buildClientDossiersTab() {
    final clientDossiers = _data?.clientDossiers ?? [];
    if (clientDossiers.isEmpty) {
      return const Center(child: Text('No registered clients.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: clientDossiers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (ctx, i) {
        final cd = clientDossiers[i];
        final c = cd.client;

        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(c.companyName, style: AppTextStyles.headlineSm),
                    _chip(c.status.toUpperCase(), AppColors.statusDone),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Contact: ${c.contactName ?? "-"}   |   Email: ${c.email ?? "-"}   |   Phone: ${c.phone ?? "-"}', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                Text('Client Tasks (${cd.tasks.length}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                const SizedBox(height: 6),
                cd.tasks.isEmpty
                    ? Text('No tasks created for this client.', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant))
                    : Column(
                        children: cd.tasks.map((t) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.title, style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('Status: ${t.status.toUpperCase()} (${t.completionPercentage}%)'),
                        )).toList(),
                      ),
                const SizedBox(height: 12),

                Text('Financials & Contracts (${cd.crmEntries.length}, Value: \$${cd.totalContractValue.toStringAsFixed(2)}, Paid: \$${cd.totalPaid.toStringAsFixed(2)}, Outstanding: \$${cd.totalOutstanding.toStringAsFixed(2)}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                const SizedBox(height: 6),
                cd.crmEntries.isEmpty
                    ? Text('No financial records.', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant))
                    : Column(
                        children: cd.crmEntries.map((crm) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(crm.title, style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('Billed: \$${crm.amount.toStringAsFixed(2)} | Paid: \$${crm.paidAmount.toStringAsFixed(2)} | Outstanding: \$${crm.outstanding.toStringAsFixed(2)} | Status: ${crm.status.toUpperCase()}'),
                        )).toList(),
                      ),
                const SizedBox(height: 12),

                Text('Scheduled Meetings & Events (${cd.meetings.length}):', style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
                const SizedBox(height: 6),
                cd.meetings.isEmpty
                    ? Text('No meetings recorded.', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant))
                    : Column(
                        children: cd.meetings.map((m) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.title, style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text('Start: ${m.startTime} | Status: ${m.status.toUpperCase()} | Location/Notes: ${m.location ?? m.meetingNotes ?? "N/A"}'),
                        )).toList(),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 6. Finance & Expenses ─────────────────────────────────────────────────
  Widget _buildFinanceTab() {
    final d = _data!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CRM & Revenue Transactions (${d.crmList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.crmList.isEmpty
              ? const Text('No revenue entries.')
              : Card(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Title / Invoice')),
                        DataColumn(label: Text('Client')),
                        DataColumn(label: Text('Billed')),
                        DataColumn(label: Text('Paid')),
                        DataColumn(label: Text('Outstanding')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: d.crmList.map((c) => DataRow(cells: [
                        DataCell(Text(c.title, style: AppTextStyles.labelMd)),
                        DataCell(Text(c.clientName)),
                        DataCell(Text('\$${c.amount.toStringAsFixed(2)}')),
                        DataCell(Text('\$${c.paidAmount.toStringAsFixed(2)}')),
                        DataCell(Text('\$${c.outstanding.toStringAsFixed(2)}')),
                        DataCell(_chip(c.status.toUpperCase(), c.status == 'paid' ? AppColors.statusDone : AppColors.error)),
                      ])).toList(),
                    ),
                  ),
                ),
          const SizedBox(height: 28),

          Text('Expense Entries (${d.expenseList.length})', style: AppTextStyles.headlineSm),
          const SizedBox(height: 10),
          d.expenseList.isEmpty
              ? const Text('No expense entries.')
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
                      ],
                      rows: d.expenseList.map((e) => DataRow(cells: [
                        DataCell(Text(e.categoryName, style: AppTextStyles.labelMd)),
                        DataCell(Text(e.description.isNotEmpty ? e.description : '-')),
                        DataCell(Text('\$${e.amount.toStringAsFixed(2)}')),
                        DataCell(Text(e.date)),
                        DataCell(Text(e.recordedByName)),
                        DataCell(_chip(e.status.toUpperCase(), AppColors.statusDone)),
                      ])).toList(),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── 7. Comments Feed ──────────────────────────────────────────────────────
  Widget _buildCommentsTab() {
    final list = _data?.commentsList ?? [];
    if (list.isEmpty) {
      return const Center(child: Text('No comments recorded.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final c = list[i];
        return Card(
          color: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            title: Text(c.taskTitle, style: AppTextStyles.labelMd.copyWith(color: AppColors.gold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                ClickableCommentText(text: c.content, style: AppTextStyles.bodyMd),
                const SizedBox(height: 4),
                Text('By ${c.authorName} on ${c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt}', style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper widgets
  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
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
                Text(title, style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.headlineSm.copyWith(fontSize: 16, color: color), maxLines: 1),
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
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelMd),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: AppTextStyles.bodySm.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'done':
      case 'completed':
      case 'employee_done':
        return AppColors.statusDone;
      case 'in_progress':
        return AppColors.statusInProgress;
      case 'on_hold':
        return AppColors.gold;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
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
