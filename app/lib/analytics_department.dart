import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'widgets/analytics_range_bar.dart';
import 'widgets/analytics_ui.dart';
import 'l10n/gen/app_localizations.dart';

// Department Analysis — the same per-employee metrics rolled up by
// department (Department model / User.departmentId). Users with no
// department land in a single "Unassigned" bucket rather than being
// dropped. A grouped bar chart compares departments head-to-head; tapping
// one drills into its member employees.
class DepartmentAnalysisScreen extends StatefulWidget {
  const DepartmentAnalysisScreen({super.key});
  @override
  State<DepartmentAnalysisScreen> createState() => _DepartmentAnalysisScreenState();
}

class _DepartmentAnalysisScreenState extends State<DepartmentAnalysisScreen> {
  AnalyticsRangePreset _preset = AnalyticsRangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();

  bool _loading = true;
  String? _error;
  List<dynamic> _departments = [];
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
      final results = await Future.wait([
        Api.analyticsDepartments(from, to),
        Api.analyticsEmployees(from, to),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _departments = results[0];
        _employees = results[1];
      });
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  void _openDepartment(Map<String, dynamic> dept) {
    final l10n = AppLocalizations.of(context);
    final members = _employees.where((e) => e['departmentId'] == dept['departmentId']).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => _DepartmentMembersScreen(
      title: dept['departmentId'] == null ? l10n.notAssigned : dept['name'] as String,
      members: members,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).departmentAnalysisTitle)),
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
    final l10n = AppLocalizations.of(context);
    if (_departments.isEmpty) {
      return const [Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('No departments yet.')))];
    }
    final withHeadcount = _departments.where((d) => (d['employeeCount'] as int) > 0).toList();
    final totalEmployees = _departments.fold<int>(0, (a, d) => a + (d['employeeCount'] as int));
    final avgOnTime = withHeadcount.isEmpty
        ? 0
        : (withHeadcount.fold<int>(0, (a, d) => a + (d['onTimePct'] as int)) / withHeadcount.length).round();
    final weakest = withHeadcount.isNotEmpty
        ? (([...withHeadcount]..sort((a, b) => (a['onTimePct'] as int).compareTo(b['onTimePct'] as int))).first)
        : null;
    final semantic = AppColors.of(context);
    final donutColors = [
      Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary,
      semantic.info, semantic.success, semantic.warning, semantic.danger,
    ];

    return [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: [
          HeroStat(value: '${_departments.length}', label: 'Groups'),
          HeroStat(value: '$totalEmployees', label: 'People'),
          HeroStat(value: '$avgOnTime%', label: 'Avg on-time', accent: semantic.info),
        ],
      ),
      const SizedBox(height: 16),
      TakeawayLine(
        text: weakest != null && (weakest['onTimePct'] as int) < 70
            ? '${weakest['departmentId'] == null ? l10n.notAssigned : weakest['name']} is the weakest group at ${weakest['onTimePct']}% on-time.'
            : withHeadcount.isEmpty
                ? 'No department activity in this range yet.'
                : 'All groups are performing within a healthy range.',
      ),
      const SizedBox(height: 20),
      if (withHeadcount.isNotEmpty) ...[
        const SectionHeader(title: 'Headcount by department'),
        DonutComposition(
          centerValue: '$totalEmployees',
          centerLabel: 'people',
          slices: [
            for (int i = 0; i < withHeadcount.length; i++)
              DonutSlice(
                withHeadcount[i]['departmentId'] == null ? l10n.notAssigned : withHeadcount[i]['name'] as String,
                (withHeadcount[i]['employeeCount'] as int).toDouble(),
                donutColors[i % donutColors.length],
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('On-time % vs checklist compliance %', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(children: [
          _legendDot(context, Theme.of(context).colorScheme.primary, 'On-time %'),
          const SizedBox(width: 16),
          _legendDot(context, Theme.of(context).colorScheme.tertiary, 'Checklist %'),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            maxY: 100,
            barGroups: [
              for (int i = 0; i < withHeadcount.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (withHeadcount[i]['onTimePct'] as int).toDouble(), color: Theme.of(context).colorScheme.primary, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                  BarChartRodData(toY: (withHeadcount[i]['checklistCompliancePct'] as int).toDouble(), color: Theme.of(context).colorScheme.tertiary, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                ]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= withHeadcount.length) return const SizedBox.shrink();
                  final d = withHeadcount[i];
                  final name = d['departmentId'] == null ? l10n.notAssigned : d['name'] as String;
                  // Full name, not just the first word — unlike employee first
                  // names, department names ("Not assigned") turn misleading
                  // when truncated to one word ("Not").
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(name, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                  );
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
      ],
      Text('Departments', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ..._departments.map((d) {
        final name = d['departmentId'] == null ? l10n.notAssigned : d['name'] as String;
        final completed = d['completed'] as int;
        final late = d['late'] as int;
        final theme = Theme.of(context);
        return Card(
          child: ListTile(
            onTap: () => _openDepartment(d as Map<String, dynamic>),
            leading: CircleAvatar(child: Text('${d['employeeCount']}')),
            title: Text(name, style: theme.textTheme.titleSmall),
            subtitle: Text(completed > 0 ? '$completed done · $late late · load ${d['currentLoad']}' : 'No completed tasks in this range',
                style: theme.textTheme.bodySmall),
            trailing: completed > 0
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${d['onTimePct']}%',
                          style: AppTheme.tabularFigures(theme.textTheme.titleMedium)
                              .copyWith(color: _colorFor(context, d['onTimePct'] as int))),
                      Text('on-time', style: theme.textTheme.labelSmall),
                    ],
                  )
                : const Icon(Icons.chevron_right),
          ),
        );
      }),
      const SizedBox(height: 20),
      AiInsightsCard(screenKey: 'department', screenData: {'departments': _departments}),
    ];
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Color _colorFor(BuildContext context, int pct) {
    final c = AppColors.of(context);
    if (pct >= 80) return c.success;
    if (pct >= 50) return c.warning;
    return c.danger;
  }

}

class _DepartmentMembersScreen extends StatelessWidget {
  final String title;
  final List<dynamic> members;
  const _DepartmentMembersScreen({required this.title, required this.members});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: members.isEmpty
          ? const Center(child: Text('No employees in this group.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: members.length,
              itemBuilder: (context, i) {
                final e = members[i] as Map<String, dynamic>;
                final theme = Theme.of(context);
                return Card(
                  child: ListTile(
                    title: Text(e['name'] as String, style: theme.textTheme.titleSmall),
                    subtitle: Text('${e['completed']} done · ${e['escalated']} escalated · load ${e['currentLoad']}',
                        style: theme.textTheme.bodySmall),
                    trailing: Text('${e['onTimePct']}%', style: AppTheme.tabularFigures(theme.textTheme.titleMedium)),
                  ),
                );
              },
            ),
    );
  }
}
