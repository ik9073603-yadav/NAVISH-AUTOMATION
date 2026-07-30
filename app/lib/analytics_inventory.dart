import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'widgets/analytics_range_bar.dart';
import 'widgets/analytics_ui.dart';
import 'l10n/gen/app_localizations.dart';

// Inventory Analysis — the 5th Analytics hub card. Stock value/low/dead
// counts are current-state snapshots (not date-ranged, so no "vs previous
// period" delta is shown for them — that would compare a snapshot to
// itself and mislead). Movement volume, the fastest/slowest movers, and the
// trend chart genuinely depend on the selected range, so those do carry a
// delta / redraw per range.
class InventoryAnalysisScreen extends StatefulWidget {
  const InventoryAnalysisScreen({super.key});
  @override
  State<InventoryAnalysisScreen> createState() => _InventoryAnalysisScreenState();
}

class _InventoryAnalysisScreenState extends State<InventoryAnalysisScreen> {
  AnalyticsRangePreset _preset = AnalyticsRangePreset.week;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _previous;
  int _loadRequestId = 0;

  static const _categoryColors = [
    Color(0xFF4B57C9), Color(0xFF3B5BA5), Color(0xFF1F7A5C),
    Color(0xFF8A5A00), Color(0xFFB3261E), Color(0xFF5B5F73),
  ];

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
        Api.analyticsInventory(from, to),
        Api.analyticsInventory(prevFrom, prevTo),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _current = results[0];
        _previous = results[1];
      });
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  int _movementVolume(Map<String, dynamic>? data) {
    final trend = (data?['movementTrend'] as List<dynamic>? ?? []);
    return trend.fold<int>(0, (a, d) => a + (d['inQty'] as int) + (d['outQty'] as int));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).inventoryAnalysisTitle)),
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
    final c = _current ?? {};
    final semantic = AppColors.of(context);

    final totalStockValue = (c['totalStockValue'] as num?) ?? 0;
    final lowStockCount = (c['lowStockCount'] as int?) ?? 0;
    final deadStockCount = (c['deadStockCount'] as int?) ?? 0;
    final deadStockValue = (c['deadStockValue'] as num?) ?? 0;
    final stockByCategory = (c['stockByCategory'] as List<dynamic>? ?? []);
    final movementTrend = (c['movementTrend'] as List<dynamic>? ?? []);
    final fastestMoving = (c['fastestMoving'] as List<dynamic>? ?? []);
    final slowestMoving = (c['slowestMoving'] as List<dynamic>? ?? []);
    final reorderList = (c['reorderList'] as List<dynamic>? ?? []);

    final currentVolume = _movementVolume(_current);
    final previousVolume = _movementVolume(_previous);

    final takeaway = reorderList.isNotEmpty
        ? '${reorderList.length} SKU${reorderList.length == 1 ? '' : 's'} need reordering now'
            '${deadStockValue > 0 ? " · ₹${deadStockValue.toStringAsFixed(0)} sitting in dead stock" : ''}.'
        : deadStockValue > 0
            ? '₹${deadStockValue.toStringAsFixed(0)} of stock has had no movement in 90+ days.'
            : 'Stock levels are healthy — nothing needs reordering right now.';

    return [
      GridView.count(
        crossAxisCount: switch (screenSizeOf(context)) { ScreenSize.compact => 2, ScreenSize.medium => 4, ScreenSize.expanded => 4 },
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: [
          HeroStat(value: '₹${totalStockValue.toStringAsFixed(0)}', label: 'Total stock value'),
          HeroStat(
            value: '$lowStockCount', label: 'Low stock',
            accent: lowStockCount > 0 ? semantic.warning : semantic.success,
          ),
          HeroStat(
            value: '$deadStockCount', label: 'Dead stock SKUs',
            accent: deadStockCount > 0 ? semantic.danger : semantic.success,
          ),
          HeroStat(
            value: '$currentVolume', label: 'Units moved',
            deltaPct: deltaPctOf(currentVolume, previousVolume),
            accent: semantic.info,
          ),
        ],
      ),
      const SizedBox(height: 16),
      TakeawayLine(text: takeaway, icon: reorderList.isNotEmpty ? Icons.warning_amber_rounded : Icons.insights_outlined),
      const SizedBox(height: 20),

      if (stockByCategory.isNotEmpty) ...[
        SectionHeader(title: 'Stock value by category', subtitle: 'Where working capital is tied up'),
        DonutComposition(
          centerValue: '₹${(totalStockValue / 1000).toStringAsFixed(1)}k',
          centerLabel: 'total',
          slices: [
            for (int i = 0; i < stockByCategory.length; i++)
              DonutSlice(
                stockByCategory[i]['category'] as String,
                (stockByCategory[i]['value'] as num).toDouble(),
                _categoryColors[i % _categoryColors.length],
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],

      if (movementTrend.isNotEmpty) ...[
        SectionHeader(title: 'Movement trend', subtitle: 'Units in vs out over the selected range'),
        Row(children: [
          _legendDot(context, semantic.success, 'In'),
          const SizedBox(width: 16),
          _legendDot(context, semantic.danger, 'Out'),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: [for (int i = 0; i < movementTrend.length; i++) FlSpot(i.toDouble(), (movementTrend[i]['inQty'] as int).toDouble())],
                isCurved: true, color: semantic.success, dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: semantic.success.withValues(alpha: 0.12)),
              ),
              LineChartBarData(
                spots: [for (int i = 0; i < movementTrend.length; i++) FlSpot(i.toDouble(), (movementTrend[i]['outQty'] as int).toDouble())],
                isCurved: true, color: semantic.danger, dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: semantic.danger.withValues(alpha: 0.12)),
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
          )),
        ),
        const SizedBox(height: 24),
      ],

      if (fastestMoving.isNotEmpty) ...[
        SectionHeader(title: 'Fastest moving SKUs', subtitle: 'Highest volume moved in this range'),
        RankedBarList(items: [
          for (final m in fastestMoving)
            RankedBarItem(
              label: m['name'] as String,
              value: (m['totalQty'] as num).toDouble(),
              valueText: '${m['totalQty']} ${m['unit']}',
              color: semantic.success,
            ),
        ]),
        const SizedBox(height: 24),
      ],

      if (slowestMoving.isNotEmpty) ...[
        SectionHeader(title: 'Slowest moving SKUs', subtitle: 'Lowest volume moved in this range — dead-stock candidates'),
        RankedBarList(items: [
          for (final m in slowestMoving)
            RankedBarItem(
              label: m['name'] as String,
              value: (m['totalQty'] as num).toDouble(),
              valueText: '${m['totalQty']} ${m['unit']}',
              color: semantic.warning,
            ),
        ]),
        const SizedBox(height: 24),
      ],

      if (reorderList.isNotEmpty) ...[
        SectionHeader(title: 'Reorder needed', subtitle: '${reorderList.length} SKU(s) at or below minimum stock'),
        ...reorderList.map((r) => Card(
              child: ListTile(
                title: Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${r['currentStock']} ${r['unit']} left · min ${r['minStock']}'),
                trailing: Text('+${r['suggestedReorderQty']}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: semantic.warning)),
              ),
            )),
        const SizedBox(height: 24),
      ],

      AiInsightsCard(screenKey: 'inventory', screenData: c),
    ];
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}
