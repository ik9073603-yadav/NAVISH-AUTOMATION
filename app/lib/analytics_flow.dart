import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'flow_analytics.dart' show FlowOrdersListScreen;
import 'theme/app_theme.dart';
import 'time_format.dart';
import 'widgets/analytics_range_bar.dart';
import 'widgets/cost_of_delay_info.dart';
import 'l10n/gen/app_localizations.dart';

// Flow Analysis — the deep-dive behind the "Flow analysis" hub card.
// Deliberately a standalone screen (not a reuse of FlowAnalyticsView, which
// stays exactly as-is embedded inside the FMS module's own Analytics tab)
// so this richer version can't affect that existing surface.
class FlowAnalysisScreen extends StatefulWidget {
  const FlowAnalysisScreen({super.key});
  @override
  State<FlowAnalysisScreen> createState() => _FlowAnalysisScreenState();
}

class _FlowAnalysisScreenState extends State<FlowAnalysisScreen> {
  AnalyticsRangePreset _preset = AnalyticsRangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary; // all-time KPIs — current state, not date-ranged
  Map<String, dynamic>? _costOfDelay;
  Map<String, dynamic>? _stageMetrics;
  List<dynamic> _bottlenecks = []; // current state — which stages are backed up right now
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    setState(() { _loading = true; _error = null; });
    final (from, to) = AnalyticsRangeBar.rangeFor(_preset, _customFrom, _customTo);
    try {
      final results = await Future.wait([
        Api.fmsAnalyticsSummary(),
        Api.fmsAnalyticsCostOfDelay(from: from, to: to),
        Api.analyticsFms(from, to),
        Api.bottlenecks(),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _costOfDelay = results[1] as Map<String, dynamic>;
        _stageMetrics = results[2] as Map<String, dynamic>;
        _bottlenecks = results[3] as List<dynamic>;
      });
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  void _openCategory(String category, String title) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => FlowOrdersListScreen(category: category, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).flowAnalysisTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AnalyticsRangeBar(
              preset: _preset,
              customFrom: _customFrom,
              customTo: _customTo,
              onPresetChanged: (p) { setState(() => _preset = p); _load(); },
              onCustomRangePicked: (r) {
                setState(() { _customFrom = r.start; _customTo = r.end; _preset = AnalyticsRangePreset.custom; });
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger))),
            if (!_loading && _error == null) ..._content(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final s = _summary ?? {};
    final stageData = _stageMetrics ?? {};
    final throughput = stageData['throughput'] as Map<String, dynamic>? ?? {};
    final stages = (stageData['stages'] as List<dynamic>? ?? []);
    final funnel = (stageData['funnel'] as List<dynamic>? ?? []);

    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _kpiCard('Pending', s['pending'] as int? ?? 0, AppColors.of(context).info, Icons.hourglass_top,
              () => _openCategory('PENDING', 'Pending orders')),
          _kpiCard('Completed', s['completed'] as int? ?? 0, AppColors.of(context).success, Icons.check_circle,
              () => _openCategory('COMPLETED', 'Completed orders')),
          _kpiCard('Delayed', s['delayed'] as int? ?? 0, AppColors.of(context).danger, Icons.warning,
              () => _openCategory('DELAYED', 'Delayed orders')),
          _kpiCard('On-time', s['onTime'] as int? ?? 0, Theme.of(context).colorScheme.tertiary, Icons.thumb_up,
              () => _openCategory('ONTIME', 'On-time orders')),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryTile(context, '${s['totalOrders'] ?? 0}', 'Total orders'),
              _summaryTile(context, '${throughput['completedOrders'] ?? 0}', 'Completed in range'),
              _summaryTile(context, formatDurationMinsOrDash(throughput['avgCycleTimeMins'] as int? ?? 0), 'Avg cycle time'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      _costOfDelaySection(context),
      const SizedBox(height: 20),
      _funnelSection(context, funnel),
      const SizedBox(height: 20),
      _stageMetricsSection(context, stages),
      const SizedBox(height: 20),
      _bottlenecksSection(context),
    ];
  }

  Widget _summaryTile(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _kpiCard(String label, int count, Color color, IconData icon, VoidCallback onTap) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              Text('$count', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _costOfDelaySection(BuildContext context) {
    final c = _costOfDelay;
    if (c == null) return const SizedBox.shrink();

    final total = c['totalRupeesLost'] as num?;
    final missing = c['ordersMissingCostInfo'] as int? ?? 0;
    final mostExpensive = (c['mostExpensiveOrders'] as List?) ?? [];
    final costliestStages = (c['costliestStages'] as List?) ?? [];
    final costliestPeople = (c['costliestPeople'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Cost of Delay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const CostOfDelayInfoButton(),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          color: AppColors.of(context).danger.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRupeesOrPrompt(total),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: total == null ? Theme.of(context).colorScheme.onSurfaceVariant : AppColors.of(context).danger,
                  ),
                ),
                Text(
                  total == null ? 'Set a ₹/hr rate or capture order values to see ₹ lost to delay' : 'Total ₹ lost to delay in this range',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (missing > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$missing delayed order(s) not counted — no rate or order value set',
                    style: TextStyle(fontSize: 11, color: AppColors.of(context).warning),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (mostExpensive.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Most expensive delayed orders', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...mostExpensive.take(5).map((o) => _costRow(context, o['orderNumber'] as String, o['cost'] as num)),
        ],
        if (costliestStages.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Costliest stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...costliestStages.take(3).map((s) => _costRow(context, '${s['stageName']} (${s['flowName']})', s['cost'] as num)),
        ],
        if (costliestPeople.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Costliest person', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...costliestPeople.take(3).map((p) => _costRow(context, p['name'] as String, p['cost'] as num)),
        ],
      ],
    );
  }

  Widget _costRow(BuildContext context, String label, num cost) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('₹${cost.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.of(context).danger)),
        ],
      ),
    );
  }

  Widget _funnelSection(BuildContext context, List<dynamic> funnel) {
    if (funnel.isEmpty) return const SizedBox.shrink();
    final maxCount = funnel.fold<int>(0, (a, f) => (f['count'] as int) > a ? (f['count'] as int) : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Order funnel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Orders that reached each stage position in this range', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxCount <= 0 ? 1 : maxCount * 1.15,
            barGroups: [
              for (final f in funnel)
                BarChartGroupData(x: f['sequence'] as int, barRods: [
                  BarChartRodData(
                    toY: (f['count'] as int).toDouble(),
                    color: Theme.of(context).colorScheme.primary,
                    width: 28,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('S${v.toInt()}', style: const TextStyle(fontSize: 11)),
                ),
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
          )),
        ),
      ],
    );
  }

  Widget _stageMetricsSection(BuildContext context, List<dynamic> stages) {
    final withActivity = stages.where((s) => (s['completedInRange'] as int) > 0).toList()
      ..sort((a, b) => (b['completedInRange'] as int).compareTo(a['completedInRange'] as int));
    if (withActivity.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Avg time per stage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...withActivity.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('${s['flowName']} — ${s['stageName']}', style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 2, child: Text('avg ${formatDurationMinsOrDash(s['avgMins'] as int)}', style: const TextStyle(fontSize: 12))),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (s['avgDelayMins'] as int) > 0 ? '+${formatDurationMinsOrDash(s['avgDelayMins'] as int)} late' : 'on time',
                      style: TextStyle(
                          fontSize: 12,
                          color: (s['avgDelayMins'] as int) > 0 ? AppColors.of(context).danger : AppColors.of(context).success),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: BarChart(BarChartData(
            barGroups: [
              for (int i = 0; i < withActivity.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (withActivity[i]['avgMins'] as int).toDouble(), color: Theme.of(context).colorScheme.primary, width: 16),
                ]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= withActivity.length) return const SizedBox.shrink();
                  final name = withActivity[i]['stageName'] as String;
                  return Padding(padding: const EdgeInsets.only(top: 4), child: Text(name.split(' ').first, style: const TextStyle(fontSize: 10)));
                },
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
          )),
        ),
      ],
    );
  }

  Widget _bottlenecksSection(BuildContext context) {
    final top = _bottlenecks.where((b) => (b['ordersStuck'] as int) > 0).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bottleneck stages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Where orders are piling up right now', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (top.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('No stage is currently backed up.'))
        else
          ...top.map((b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.of(context).danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${b['flowName']} — ${b['stageName']}', style: const TextStyle(fontSize: 13))),
                    Text('${b['ordersStuck']} stuck', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.of(context).danger)),
                  ],
                ),
              )),
      ],
    );
  }

}
