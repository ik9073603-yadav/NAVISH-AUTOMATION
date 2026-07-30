import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'widgets/analytics_ui.dart';
import 'l10n/gen/app_localizations.dart';

// Per-user AI usage — token counts only (it's the user's own key/plan, so
// cost isn't ours to report). Owner/manager see their OWN usage here, same
// as anyone else — this is never org-wide.
class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({super.key});
  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _usage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Api.aiUsage();
      if (mounted) setState(() => _usage = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiUsageTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger))))
              : RefreshIndicator(onRefresh: _load, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final u = _usage ?? {};
    final totals = u['totals'] as Map<String, dynamic>? ?? {};
    final byFeature = u['byFeature'] as Map<String, dynamic>? ?? {};
    final trend = (u['trend'] as List<dynamic>? ?? []);
    final semantic = AppColors.of(context);
    final calls = totals['calls'] as int? ?? 0;
    final inputTokens = totals['inputTokens'] as int? ?? 0;
    final outputTokens = totals['outputTokens'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
          children: [
            HeroStat(value: '$calls', label: l10n.aiUsageTotalCalls),
            HeroStat(value: '$inputTokens', label: 'Input tokens', accent: semantic.info),
            HeroStat(value: '$outputTokens', label: 'Output tokens', accent: semantic.success),
          ],
        ),
        const SizedBox(height: 24),
        if (byFeature.isNotEmpty) ...[
          const SectionHeader(title: 'By feature'),
          for (final entry in byFeature.entries)
            Card(
              child: ListTile(
                title: Text(_featureLabel(entry.key)),
                subtitle: Text('${(entry.value as Map)['calls']} calls'),
                trailing: Text('${(entry.value)['inputTokens'] + (entry.value)['outputTokens']} tok'),
              ),
            ),
          const SizedBox(height: 24),
        ],
        if (trend.length > 1) ...[
          const SectionHeader(title: 'Tokens over time'),
          SizedBox(
            height: 180,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (int i = 0; i < trend.length; i++)
                      FlSpot(i.toDouble(), ((trend[i]['inputTokens'] as int) + (trend[i]['outputTokens'] as int)).toDouble()),
                  ],
                  isCurved: true,
                  color: Theme.of(context).colorScheme.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
                ),
              ],
              titlesData: const FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              minY: 0,
            )),
          ),
        ],
        if (calls == 0)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(child: Text('No AI usage yet.', style: Theme.of(context).textTheme.bodyMedium)),
          ),
      ],
    );
  }

  String _featureLabel(String key) {
    switch (key) {
      case 'OVERVIEW': return 'Business overview';
      case 'ASSIST': return 'App assist / chat';
      case 'INSIGHTS': return 'Analytics insights';
      default: return key;
    }
  }
}
