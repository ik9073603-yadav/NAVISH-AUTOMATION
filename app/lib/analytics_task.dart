import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'export_actions.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';
import 'widgets/analytics_range_bar.dart';
import 'widgets/analytics_ui.dart';
import 'l10n/gen/app_localizations.dart';

enum _TaskAnalysisTab { delegation, checklist }

// Task Analysis — Delegation and Checklist live on the same screen (per the
// hub's "Task analysis" card) but are kept visually and structurally
// distinct: a segmented toggle switches between them, and each retains its
// own accent color and layout rather than being merged into one blended view.
class TaskAnalysisScreen extends StatefulWidget {
  const TaskAnalysisScreen({super.key});
  @override
  State<TaskAnalysisScreen> createState() => _TaskAnalysisScreenState();
}

class _TaskAnalysisScreenState extends State<TaskAnalysisScreen> {
  AnalyticsRangePreset _preset = AnalyticsRangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();
  _TaskAnalysisTab _tab = _TaskAnalysisTab.delegation;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _delegation;
  Map<String, dynamic>? _checklists;
  Map<String, dynamic>? _prevDelegation;
  Map<String, dynamic>? _prevChecklists;
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
        Api.analyticsDelegation(from, to),
        Api.analyticsChecklists(from, to),
        Api.analyticsDelegation(prevFrom, prevTo),
        Api.analyticsChecklists(prevFrom, prevTo),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _delegation = results[0];
        _checklists = results[1];
        _prevDelegation = results[2];
        _prevChecklists = results[3];
      });
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  Future<void> _exportTasksReport() async {
    final format = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Export format'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'csv'), child: const Text('CSV')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'xlsx'), child: const Text('Excel (.xlsx)')),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final (from, to) = AnalyticsRangeBar.rangeFor(_preset, _customFrom, _customTo);
    try {
      final (bytes, filename) = await Api.exportTasks(format, from: from, to: to);
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).taskAnalysisTitle),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Export tasks report', onPressed: _exportTasksReport),
        ],
      ),
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
              const SizedBox(height: 12),
              SegmentedButton<_TaskAnalysisTab>(
                segments: const [
                  ButtonSegment(value: _TaskAnalysisTab.delegation, label: Text('Delegation'), icon: Icon(Icons.person_pin_circle_outlined)),
                  ButtonSegment(value: _TaskAnalysisTab.checklist, label: Text('Checklist'), icon: Icon(Icons.event_repeat)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 16),
              if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              if (_error != null)
                Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger))),
              if (!_loading && _error == null)
                _tab == _TaskAnalysisTab.delegation ? _delegationSection(context) : _checklistSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _delegationSection(BuildContext context) {
    final d = _delegation ?? {};
    final prevTotals = (_prevDelegation ?? {})['totals'] as Map<String, dynamic>? ?? {};
    final totals = d['totals'] as Map<String, dynamic>? ?? {};
    final trend = (d['trend'] as List<dynamic>? ?? []);
    final byPerson = (d['byPerson'] as List<dynamic>? ?? []);
    final accent = Theme.of(context).colorScheme.primary;
    final semantic = AppColors.of(context);

    final created = totals['created'] as int? ?? 0;
    final completed = totals['completed'] as int? ?? 0;
    final stuck = totals['stuck'] as int? ?? 0;
    final other = (created - completed - stuck).clamp(0, created);
    final completionPct = totals['completionPct'] as int? ?? 0;
    final prevCompletionPct = prevTotals['completionPct'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text('DELEGATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          children: [
            _miniStat(context, '${totals['created'] ?? 0}', 'Assigned', accent),
            _miniStat(context, '${totals['completed'] ?? 0}', 'Completed', AppColors.of(context).success),
            _miniStat(context, '${totals['stuck'] ?? 0}', 'Stuck', AppColors.of(context).warning),
            _miniStat(context, '${totals['escalated'] ?? 0}', 'Escalated', AppColors.of(context).danger),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            GaugeRing(pct: completionPct.toDouble(), centerLabel: 'completion'),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Text('$completionPct%', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(width: 8),
                    if (deltaPctOf(completionPct, prevCompletionPct) != null)
                      DeltaBadge(deltaPct: deltaPctOf(completionPct, prevCompletionPct)!, higherIsBetter: true),
                  ]),
                  Text('completion rate · avg ${formatDurationMinsOrDash(totals['avgCompletionMins'] as int? ?? 0)} to finish',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        if (created > 0) ...[
          const SizedBox(height: 16),
          DonutComposition(
            centerValue: '$created',
            centerLabel: 'assigned',
            slices: [
              DonutSlice('Completed', completed.toDouble(), semantic.success),
              DonutSlice('Stuck', stuck.toDouble(), semantic.warning),
              DonutSlice('Other', other.toDouble(), Theme.of(context).colorScheme.surfaceContainerHighest),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TakeawayLine(
          text: stuck > 0
              ? '$stuck task${stuck == 1 ? ' is' : 's are'} stuck right now — completion rate is $completionPct%.'
              : 'No stuck tasks in this range — completion rate is $completionPct%.',
        ),
        const SizedBox(height: 16),
        if (trend.isEmpty)
          const Text('No delegation tasks created in this range.')
        else ...[
          const Text('Completion rate over time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['completionPct'] as int).toDouble())],
                  isCurved: true,
                  color: accent,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: accent.withValues(alpha: 0.12)),
                ),
              ],
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              minY: 0,
              maxY: 100,
            )),
          ),
        ],
        if (byPerson.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('By person', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ...byPerson.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(p['name'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text('${p['completed']}/${p['created']} done', style: const TextStyle(fontSize: 12))),
                    Expanded(flex: 2, child: Text('${p['stuck']} stuck', style: const TextStyle(fontSize: 12))),
                    Expanded(flex: 2, child: Text('${p['completionPct']}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                ),
              )),
        ],
        const SizedBox(height: 20),
        AiInsightsCard(screenKey: 'task', screenData: d),
      ],
    );
  }

  Widget _checklistSection(BuildContext context) {
    final c = _checklists ?? {};
    final prevTotals = (_prevChecklists ?? {})['totals'] as Map<String, dynamic>? ?? {};
    final totals = c['totals'] as Map<String, dynamic>? ?? {};
    final perRule = (c['perRule'] as List<dynamic>? ?? []);
    final trend = (c['trend'] as List<dynamic>? ?? []);
    final accent = Theme.of(context).colorScheme.tertiary;
    final compliancePct = totals['compliancePct'] as int? ?? 0;
    final prevCompliancePct = prevTotals['compliancePct'] as int? ?? 0;
    final worst = perRule.isNotEmpty ? perRule.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text('CHECKLIST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 34,
                      sections: [
                        PieChartSectionData(
                          value: (totals['done'] as int? ?? 0).toDouble(),
                          color: AppColors.of(context).success,
                          showTitle: false,
                          radius: 20,
                        ),
                        PieChartSectionData(
                          value: (totals['missed'] as int? ?? 0).toDouble().clamp(0, double.infinity) + ((totals['total'] as int? ?? 0) == 0 ? 1 : 0),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          showTitle: false,
                          radius: 20,
                        ),
                      ],
                    )),
                    Text('${totals['compliancePct'] ?? 0}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendRow(context, AppColors.of(context).success, 'Done', '${totals['done'] ?? 0}'),
                  _legendRow(context, Theme.of(context).colorScheme.surfaceContainerHighest, 'Missed', '${totals['missed'] ?? 0}'),
                  const SizedBox(height: 6),
                  Text('${totals['total'] ?? 0} total occurrences', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (deltaPctOf(compliancePct, prevCompliancePct) != null)
            DeltaBadge(deltaPct: deltaPctOf(compliancePct, prevCompliancePct)!, higherIsBetter: true),
        ]),
        const SizedBox(height: 8),
        TakeawayLine(
          text: worst != null && (worst['compliancePct'] as int) < 70
              ? '"${worst['title']}" has the lowest compliance at ${worst['compliancePct']}%.'
              : 'Compliance is $compliancePct% — no checklist is falling behind.',
        ),
        if (trend.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Adherence over time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['compliancePct'] as int).toDouble())],
                  isCurved: true,
                  color: accent,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: accent.withValues(alpha: 0.12)),
                ),
              ],
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              minY: 0,
              maxY: 100,
            )),
          ),
        ],
        if (perRule.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 16), child: Text('No checklist activity in this range.'))
        else ...[
          const SizedBox(height: 20),
          const Text('Per checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ...perRule.map((r) {
            final pct = r['compliancePct'] as int;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(r['title'] as String, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    flex: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 10,
                        color: pct >= 80 ? AppColors.of(context).success : pct >= 50 ? AppColors.of(context).warning : AppColors.of(context).danger,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$pct%'),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
        AiInsightsCard(screenKey: 'task', screenData: c),
      ],
    );
  }

  Widget _legendRow(BuildContext context, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String value, String label, Color color) {
    return Container(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
