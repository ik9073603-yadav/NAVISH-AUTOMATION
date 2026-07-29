import 'package:flutter/material.dart';
import 'api.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';
import 'widgets/analytics_range_bar.dart';
import 'widgets/analytics_ui.dart';
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
  List<dynamic> _previousEmployees = [];
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
    final (prevFrom, prevTo) = AnalyticsRangeBar.previousRangeFor(_preset, _customFrom, _customTo);
    try {
      final results = await Future.wait([
        Api.analyticsEmployees(from, to),
        Api.analyticsEmployees(prevFrom, prevTo),
      ]);
      if (mounted && requestId == _loadRequestId) {
        setState(() { _employees = results[0]; _previousEmployees = results[1]; });
      }
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  int _avgOnTime(List<dynamic> employees) {
    final withActivity = employees.where((e) => (e['completed'] as int) > 0).toList();
    if (withActivity.isEmpty) return 0;
    return (withActivity.fold<int>(0, (a, e) => a + (e['onTimePct'] as int)) / withActivity.length).round();
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
    final avgOnTime = _avgOnTime(_employees);
    final prevAvgOnTime = _avgOnTime(_previousEmployees);
    final bottleneck = ranked.isNotEmpty ? ranked.last : null;
    final semantic = AppColors.of(context);

    final takeaway = bottleneck != null && (bottleneck['onTimePct'] as int) < 70
        ? '${bottleneck['name']} has the lowest on-time rate (${bottleneck['onTimePct']}%) — likely the current bottleneck.'
        : ranked.isEmpty
            ? 'No completed work in this range yet.'
            : 'Team on-time rate is $avgOnTime% — no single person is dragging it down.';

    return [
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
        children: [
          HeroStat(value: '${_employees.length}', label: 'Active people'),
          HeroStat(value: '$totalCompleted', label: 'Completed', accent: semantic.success),
          HeroStat(
            value: '$avgOnTime%', label: 'Avg on-time',
            deltaPct: deltaPctOf(avgOnTime, prevAvgOnTime),
            accent: semantic.info,
          ),
          HeroStat(value: '$totalEscalated', label: 'Escalated', accent: totalEscalated > 0 ? semantic.danger : semantic.success),
        ],
      ),
      const SizedBox(height: 16),
      TakeawayLine(text: takeaway, icon: bottleneck != null && (bottleneck['onTimePct'] as int) < 70 ? Icons.report_gmailerrorred : Icons.insights_outlined),
      const SizedBox(height: 20),
      const SectionHeader(title: 'On-time %, best to worst'),
      RankedBarList(items: [
        for (final e in ranked)
          RankedBarItem(
            label: (e['name'] as String).split(' ').first,
            value: (e['onTimePct'] as int).toDouble(),
            valueText: '${e['onTimePct']}%',
            color: _colorFor(context, e['onTimePct'] as int),
            onTap: () => _openDetail(e as Map<String, dynamic>),
          ),
      ]),
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
      const SizedBox(height: 20),
      AiInsightsCard(screenData: {'employees': _employees}),
    ];
  }

  Color _colorFor(BuildContext context, int pct) {
    final c = AppColors.of(context);
    if (pct >= 80) return c.success;
    if (pct >= 50) return c.warning;
    return c.danger;
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
