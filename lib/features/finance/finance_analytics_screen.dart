// lib/features/finance/finance_analytics_screen.dart
import 'package:flutter/material.dart';
import '../../core/repositories/finance_repository.dart';
import '../../core/theme/app_theme.dart';

class FinanceAnalyticsScreen extends StatefulWidget {
  const FinanceAnalyticsScreen({super.key});

  @override
  State<FinanceAnalyticsScreen> createState() => _FinanceAnalyticsScreenState();
}

class _FinanceAnalyticsScreenState extends State<FinanceAnalyticsScreen> {
  FinanceSummary             _summary    = const FinanceSummary();
  List<Map<String, dynamic>> _monthly    = [];
  List<Map<String, dynamic>> _expCats    = [];
  List<Map<String, dynamic>> _topClients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      FinanceRepository.fetchSummary(),
      FinanceRepository.fetchMonthlyBreakdown(),
      FinanceRepository.fetchExpensesByCategory(),
      FinanceRepository.fetchTopClients(),
    ]);
    if (mounted) {
      setState(() {
        _summary    = results[0] as FinanceSummary;
        _monthly    = results[1] as List<Map<String, dynamic>>;
        _expCats    = results[2] as List<Map<String, dynamic>>;
        _topClients = results[3] as List<Map<String, dynamic>>;
        _loading    = false;
      });
    }
  }

  // Compute month-over-month trend for gross revenue
  String get _revenueTrend {
    if (_monthly.length < 2) return '—';
    final curr = _monthly.last['value'] as double;
    final prev = _monthly[_monthly.length - 2]['value'] as double;
    if (prev == 0) return curr > 0 ? '+100%' : '—';
    final pct = ((curr - prev) / prev * 100).round();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }

  bool get _trendUp {
    if (_monthly.length < 2) return true;
    return (_monthly.last['value'] as double) >=
        (_monthly[_monthly.length - 2]['value'] as double);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Finance Analytics'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // ── KPI row ────────────────────────────────────────────────
                  Row(children: [
                    Expanded(child: _KpiCard(
                        label: 'GROSS REVENUE',
                        value: _fmtAmount(_summary.grossRevenue),
                        trend: _revenueTrend,
                        up: _trendUp)),
                    const SizedBox(width: 12),
                    Expanded(child: _KpiCard(
                        label: 'NET PROFIT',
                        value: _fmtAmount(_summary.netProfit),
                        trend: _summary.netProfit >= 0 ? 'Positive' : 'Negative',
                        up: _summary.netProfit >= 0)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _KpiCard(
                        label: 'TOTAL EXPENSES',
                        value: _fmtAmount(_summary.totalExpenses),
                        trend: 'All time',
                        up: false)),
                    const SizedBox(width: 12),
                    Expanded(child: _KpiCard(
                        label: 'OUTSTANDING',
                        value: _fmtAmount(_summary.outstanding),
                        trend: '${_summary.pendingInvoices} invoices',
                        up: false)),
                  ]),
                  const SizedBox(height: 24),

                  // ── Revenue chart ──────────────────────────────────────────
                  Text('MONTHLY REVENUE (TASKS + MEETINGS)',
                      style: AppTextStyles.labelCaps),
                  const SizedBox(height: 12),
                  _monthly.isEmpty
                      ? _EmptySection(message: 'No revenue data yet.')
                      : _LineChart(data: _monthly),
                  const SizedBox(height: 24),

                  // ── Expense breakdown ──────────────────────────────────────
                  Text('EXPENSE BREAKDOWN', style: AppTextStyles.labelCaps),
                  const SizedBox(height: 12),
                  _expCats.isEmpty
                      ? _EmptySection(message: 'No expenses recorded yet.')
                      : _ExpenseBreakdown(categories: _expCats),
                  const SizedBox(height: 24),

                  // ── Top clients ────────────────────────────────────────────
                  Text('TOP CLIENTS BY TASK REVENUE',
                      style: AppTextStyles.labelCaps),
                  const SizedBox(height: 12),
                  _topClients.isEmpty
                      ? _EmptySection(message: 'No client task revenue yet.')
                      : Column(
                          children: _topClients
                              .map((c) => _ClientRow(client: c))
                              .toList()),
                ]),
              ),
            ),
    );
  }
}

String _fmtAmount(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

// ── KPI Card ───────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.up,
  });
  final String label, value, trend;
  final bool up;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.labelCaps),
        const SizedBox(height: 8),
        Text(value, style: AppTextStyles.dataLg.copyWith(fontSize: 22)),
        const SizedBox(height: 8),
        Row(children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 14,
              color: up ? AppColors.statusDone : AppColors.statusHigh),
          const SizedBox(width: 4),
          Text(trend,
              style: AppTextStyles.bodySm.copyWith(
                  color: up ? AppColors.statusDone : AppColors.statusHigh,
                  fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

// ── Line chart ────────────────────────────────────────────────────────────────
class _LineChart extends StatelessWidget {
  const _LineChart({required this.data});
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    final maxVal =
        data.map((d) => d['value'] as double).fold(0.0, (a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1.0 : maxVal;
    const h = 120.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(children: [
        SizedBox(
          height: h,
          child: CustomPaint(
            size: const Size(double.infinity, h),
            painter: _LinePainter(
              values: data
                  .map((d) => (d['value'] as double) / safeMax)
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: data
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d['month'] as String,
                          style:
                              AppTextStyles.bodySm.copyWith(fontSize: 10)),
                    ),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.gold.withValues(alpha: 0.25),
          AppColors.gold.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final n = values.length;
    if (n < 2) return;
    final path     = Path();
    final fillPath = Path();
    for (var i = 0; i < n; i++) {
      final x = (i / (n - 1)) * size.width;
      final y = size.height - values[i] * size.height * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, paint);
    for (var i = 0; i < n; i++) {
      final x = (i / (n - 1)) * size.width;
      final y = size.height - values[i] * size.height * 0.9;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = AppColors.gold);
      canvas.drawCircle(Offset(x, y), 4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Expense breakdown ──────────────────────────────────────────────────────────
class _ExpenseBreakdown extends StatelessWidget {
  const _ExpenseBreakdown({required this.categories});
  final List<Map<String, dynamic>> categories;

  @override
  Widget build(BuildContext context) {
    const colors = [
      AppColors.gold,
      AppColors.statusInProgress,
      AppColors.primary,
      AppColors.outline,
      AppColors.statusHigh,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: categories.asMap().entries.map((e) {
          final idx   = e.key;
          final cat   = e.value;
          final pct   = (cat['value'] as double).clamp(0.0, 100.0);
          final color = colors[idx % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                  width: 10, height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(cat['label'] as String,
                  style: AppTextStyles.bodyMd)),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.outlineVariant,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${pct.toInt()}%', style: AppTextStyles.dataSm),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ── Top client row ─────────────────────────────────────────────────────────────
class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});
  final Map<String, dynamic> client;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        TAvatar(name: client['name'] as String, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(client['name'] as String, style: AppTextStyles.labelMd),
          Text('${client['tasks']} task(s)',
              style: AppTextStyles.bodySm),
        ])),
        Text('${_fmtAmount(client['revenue'] as double)} SAR',
            style: AppTextStyles.dataMd),
      ]),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Text(message,
          style:
              AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          textAlign: TextAlign.center),
    );
  }
}
