import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'export_actions.dart';

enum _RangePreset { today, week, month, custom }

// Owner/Manager only. Date-ranged aggregates across every module — numbers
// first, charts second. Each section calls its own analytics endpoint so a
// slow one (FMS/inventory) never blocks the others from rendering.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _RangePreset _preset = _RangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();

  bool _loading = true;
  String? _error;
  List<dynamic> _employees = [];
  List<dynamic> _delegation = [];
  List<dynamic> _checklists = [];
  Map<String, dynamic> _fms = {};
  Map<String, dynamic> _inventory = {};

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    switch (_preset) {
      case _RangePreset.today:
        return (DateTime(now.year, now.month, now.day), now);
      case _RangePreset.week:
        return (now.subtract(const Duration(days: 7)), now);
      case _RangePreset.month:
        return (DateTime(now.year, now.month, 1), now);
      case _RangePreset.custom:
        return (_customFrom, _customTo);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final (from, to) = _range;
    try {
      final results = await Future.wait([
        Api.analyticsEmployees(from, to),
        Api.analyticsDelegation(from, to),
        Api.analyticsChecklists(from, to),
        Api.analyticsFms(from, to),
        Api.analyticsInventory(from, to),
      ]);
      setState(() {
        _employees = results[0] as List<dynamic>;
        _delegation = results[1] as List<dynamic>;
        _checklists = results[2] as List<dynamic>;
        _fms = results[3] as Map<String, dynamic>;
        _inventory = results[4] as Map<String, dynamic>;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
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

    final (from, to) = _range;
    try {
      final (bytes, filename) = await Api.exportTasks(format, from: from, to: to);
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _customFrom, end: _customTo),
    );
    if (picked == null) return;
    setState(() {
      _customFrom = picked.start;
      _customTo = picked.end;
      _preset = _RangePreset.custom;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export tasks report',
            onPressed: _exportTasksReport,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _rangeSelector(),
            const SizedBox(height: 12),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (!_loading && _error == null) ...[
              _sectionCard('Employee performance', _employeeSection()),
              _sectionCard('Delegation completion rate', _delegationSection()),
              _sectionCard('Checklist compliance', _checklistSection()),
              _sectionCard('Flow Monitoring System', _fmsSection()),
              _sectionCard('Inventory', _inventorySection()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rangeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_RangePreset>(
          segments: const [
            ButtonSegment(value: _RangePreset.today, label: Text('Today')),
            ButtonSegment(value: _RangePreset.week, label: Text('Week')),
            ButtonSegment(value: _RangePreset.month, label: Text('Month')),
            ButtonSegment(value: _RangePreset.custom, label: Text('Custom')),
          ],
          selected: {_preset},
          onSelectionChanged: (s) {
            if (s.first == _RangePreset.custom) {
              _pickCustomRange();
            } else {
              setState(() => _preset = s.first);
              _load();
            }
          },
        ),
        if (_preset == _RangePreset.custom)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_customFrom.toLocal().toString().split(' ')[0]} → ${_customTo.toLocal().toString().split(' ')[0]}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _employeeSection() {
    if (_employees.isEmpty) return const Text('No employee activity in this range.');
    return Column(
      children: [
        ..._employees.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(e['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(flex: 2, child: Text('${e['completed']} done')),
                  Expanded(flex: 2, child: Text('${e['onTimePct']}% on-time')),
                  Expanded(flex: 2, child: Text('${e['escalated']} escalated')),
                  Expanded(flex: 2, child: Text('load: ${e['currentLoad']}')),
                ],
              ),
            )),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: BarChart(BarChartData(
            barGroups: [
              for (int i = 0; i < _employees.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (_employees[i]['onTimePct'] as int).toDouble(), color: Colors.green, width: 18),
                ]),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= _employees.length) return const SizedBox.shrink();
                  final name = _employees[i]['name'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(name.split(' ').first, style: const TextStyle(fontSize: 10)),
                  );
                },
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            maxY: 100,
          )),
        ),
      ],
    );
  }

  Widget _delegationSection() {
    if (_delegation.isEmpty) return const Text('No delegation tasks created in this range.');
    final totalCreated = _delegation.fold<int>(0, (a, d) => a + (d['created'] as int));
    final totalCompleted = _delegation.fold<int>(0, (a, d) => a + (d['completed'] as int));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$totalCompleted / $totalCreated completed (${totalCreated > 0 ? (totalCompleted * 100 / totalCreated).round() : 0}%)'),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: LineChart(LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < _delegation.length; i++)
                    FlSpot(i.toDouble(), (_delegation[i]['completionPct'] as int).toDouble()),
                ],
                isCurved: true,
                color: Colors.teal,
                dotData: const FlDotData(show: true),
              ),
            ],
            titlesData: const FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            minY: 0,
            maxY: 100,
          )),
        ),
      ],
    );
  }

  Widget _checklistSection() {
    if (_checklists.isEmpty) return const Text('No checklist activity in this range.');
    return Column(
      children: _checklists.map((c) {
        final pct = c['compliancePct'] as int;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(c['title'])),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 10,
                    color: pct >= 80 ? Colors.green : pct >= 50 ? Colors.orange : Colors.red,
                    backgroundColor: Colors.grey.shade300,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$pct%'),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _fmsSection() {
    final throughput = _fms['throughput'] as Map<String, dynamic>? ?? {};
    final stages = (_fms['stages'] as List<dynamic>? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${throughput['completedOrders'] ?? 0} orders completed · avg cycle ${throughput['avgCycleTimeMins'] ?? 0} min'),
        const SizedBox(height: 12),
        if (stages.isEmpty)
          const Text('No stage activity in this range.')
        else
          ...stages.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text('${s['flowName']} — ${s['stageName']}')),
                    Expanded(flex: 2, child: Text('avg ${s['avgMins']}m')),
                    Expanded(
                      flex: 2,
                      child: Text(
                        s['avgDelayMins'] > 0 ? '+${s['avgDelayMins']}m late' : 'on time',
                        style: TextStyle(color: s['avgDelayMins'] > 0 ? Colors.red : Colors.green),
                      ),
                    ),
                    Expanded(flex: 2, child: Text('${s['ordersStuckNow']} stuck now')),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _inventorySection() {
    final total = (_inventory['totalStockValue'] as num?)?.toDouble() ?? 0;
    final dead = (_inventory['deadStockValue'] as num?)?.toDouble() ?? 0;
    final low = _inventory['lowStockCount'] ?? 0;
    final trend = (_inventory['movementTrend'] as List<dynamic>? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stock value: ₹${total.toStringAsFixed(0)}  ·  Dead stock: ₹${dead.toStringAsFixed(0)}  ·  Low stock: $low SKUs'),
        const SizedBox(height: 12),
        if (trend.isEmpty)
          const Text('No stock movements in this range.')
        else
          SizedBox(
            height: 160,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['inQty'] as num).toDouble())],
                  isCurved: true, color: Colors.green, dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['outQty'] as num).toDouble())],
                  isCurved: true, color: Colors.red, dotData: const FlDotData(show: false),
                ),
              ],
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
            )),
          ),
        if (trend.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('green = IN, red = OUT', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ],
    );
  }
}
