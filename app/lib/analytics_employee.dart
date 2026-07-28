import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';
import 'widgets/analytics_range_bar.dart';
import 'l10n/gen/app_localizations.dart';

// Employee Analysis — per-person on-time %, completed/late/escalated,
// current load, checklist compliance, avg completion time. Ranked
// best-to-worst so the bottleneck (if any) is immediately visible.
class EmployeeAnalysisScreen extends StatefulWidget {
  const EmployeeAnalysisScreen({super.key});
  @override
  State<EmployeeAnalysisScreen> createState() => _EmployeeAnalysisScreenState();
}

class _EmployeeAnalysisScreenState extends State<EmployeeAnalysisScreen> {
  AnalyticsRangePreset _preset = AnalyticsRangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();

  bool _loading = true;
  String? _error;
  List<dynamic> _employees = [];
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
      final data = await Api.analyticsEmployees(from, to);
      if (mounted && requestId == _loadRequestId) setState(() => _employees = data);
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  List<dynamic> get _ranked {
    final withActivity = _employees.where((e) => (e['completed'] as int) > 0).toList();
    withActivity.sort((a, b) => (b['onTimePct'] as int).compareTo(a['onTimePct'] as int));
    return withActivity;
  }

  void _openDetail(Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EmployeeDetailSheet(employee: e),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).employeeAnalysisTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: MaxWidthCenter(
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
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (_employees.isEmpty) {
      return const [Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('No employee activity in this range.')))];
    }
    final ranked = _ranked;
    final totalCompleted = _employees.fold<int>(0, (a, e) => a + (e['completed'] as int));
    final totalEscalated = _employees.fold<int>(0, (a, e) => a + (e['escalated'] as int));
    final avgOnTime = ranked.isEmpty ? 0 : (ranked.fold<int>(0, (a, e) => a + (e['onTimePct'] as int)) / ranked.length).round();
    final bottleneck = ranked.isNotEmpty ? ranked.last : null;

    return [
      Row(
        children: [
          Expanded(child: _statTile(context, '${_employees.length}', 'Active people')),
          Expanded(child: _statTile(context, '$totalCompleted', 'Completed')),
          Expanded(child: _statTile(context, '$avgOnTime%', 'Avg on-time')),
          Expanded(child: _statTile(context, '$totalEscalated', 'Escalated')),
        ],
      ),
      if (bottleneck != null && (bottleneck['onTimePct'] as int) < 70) ...[
        const SizedBox(height: 16),
        Card(
          color: AppColors.of(context).warning.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.report_gmailerrorred, color: AppColors.of(context).warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${bottleneck['name']} has the lowest on-time rate (${bottleneck['onTimePct']}%) — likely the current bottleneck.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 20),
      const Text('On-time %, best to worst', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: BarChart(BarChartData(
          maxY: 100,
          barGroups: [
            for (int i = 0; i < ranked.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: (ranked[i]['onTimePct'] as int).toDouble(),
                  color: _colorFor(context, ranked[i]['onTimePct'] as int),
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= ranked.length) return const SizedBox.shrink();
                final name = ranked[i]['name'] as String;
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(name.split(' ').first, style: const TextStyle(fontSize: 10)));
              },
            )),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
        )),
      ),
      const SizedBox(height: 20),
      const Text('Everyone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...([..._employees]..sort((a, b) => (b['onTimePct'] as int).compareTo(a['onTimePct'] as int))).map((e) => Card(
            child: ListTile(
              onTap: () => _openDetail(e as Map<String, dynamic>),
              title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${e['completed']} done · ${e['escalated']} escalated · load ${e['currentLoad']}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${e['onTimePct']}%', style: TextStyle(fontWeight: FontWeight.bold, color: _colorFor(context, e['onTimePct'] as int))),
                  const Text('on-time', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          )),
    ];
  }

  Color _colorFor(BuildContext context, int pct) {
    final c = AppColors.of(context);
    if (pct >= 80) return c.success;
    if (pct >= 50) return c.warning;
    return c.danger;
  }

  Widget _statTile(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
      ],
    );
  }
}

class _EmployeeDetailSheet extends StatelessWidget {
  final Map<String, dynamic> employee;
  const _EmployeeDetailSheet({required this.employee});

  @override
  Widget build(BuildContext context) {
    final e = employee;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e['name'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _row(context, 'Completed', '${e['completed']}'),
            _row(context, 'Late (escalated before finishing)', '${e['late']}'),
            _row(context, 'On-time %', '${e['onTimePct']}%'),
            _row(context, 'Escalated', '${e['escalated']}'),
            _row(context, 'Current load', '${e['currentLoad']}'),
            _row(context, 'Checklist compliance', '${e['checklistCompliancePct']}% (${e['checklistDone']}/${e['checklistTotal']})'),
            _row(context, 'Avg completion time', formatDurationMinsOrDash(e['avgCompletionMins'] as int)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
