import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

Color _bandColor(BuildContext context, String? band) {
  final semantic = AppColors.of(context);
  switch (band) {
    case 'HEALTHY':
      return semantic.success;
    case 'NEEDS_ATTENTION':
      return semantic.warning;
    case 'AT_RISK':
      return semantic.danger;
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

String _bandLabel(AppLocalizations l10n, String? band) {
  switch (band) {
    case 'HEALTHY':
      return l10n.healthBandHealthy;
    case 'NEEDS_ATTENTION':
      return l10n.healthBandNeedsAttention;
    case 'AT_RISK':
      return l10n.healthBandAtRisk;
    default:
      return '';
  }
}

// Same 85/60 thresholds the backend bands the overall score with — reused
// here to colour each individual component consistently.
Color _scoreColor(BuildContext context, double score) {
  final semantic = AppColors.of(context);
  if (score >= 85) return semantic.success;
  if (score >= 60) return semantic.warning;
  return semantic.danger;
}

String _componentLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'ON_TIME':
      return l10n.healthComponentOnTime;
    case 'STUCK_LOAD':
      return l10n.healthComponentStuckLoad;
    case 'CHECKLIST':
      return l10n.healthComponentChecklist;
    case 'INVENTORY':
      return l10n.healthComponentInventory;
    case 'ESCALATIONS':
      return l10n.healthComponentEscalations;
    default:
      return key;
  }
}

// Rebuilds a bilingual one-liner from the component's structured `metrics`
// (see health-score.service.ts) instead of the backend's English-only
// `reason` string, which is kept server-side only as a debug fallback.
String _componentReason(AppLocalizations l10n, Map component) {
  final metrics = (component['metrics'] as Map?) ?? const {};
  switch (component['key']) {
    case 'ON_TIME':
      return l10n.healthReasonOnTime(metrics['pct'] ?? 0, metrics['late'] ?? 0, metrics['total'] ?? 0);
    case 'STUCK_LOAD':
      final count = (metrics['itemCount'] as num?)?.toInt() ?? 0;
      return count == 0 ? l10n.healthReasonStuckLoadZero : l10n.healthReasonStuckLoad(count);
    case 'CHECKLIST':
      return l10n.healthReasonChecklist(metrics['pct'] ?? 0, metrics['done'] ?? 0, metrics['total'] ?? 0);
    case 'INVENTORY':
      return l10n.healthReasonInventory(metrics['alertCount'] ?? 0, metrics['deadPct'] ?? 0);
    case 'ESCALATIONS':
      return l10n.healthReasonEscalations(metrics['escalated'] ?? 0, metrics['total'] ?? 0);
    default:
      return component['reason'] as String? ?? '';
  }
}

// ---------------- GAUGE (Home dashboard, front and centre) ----------------
class HealthGauge extends StatelessWidget {
  final int? score;
  final String? band;
  final int? delta; // vs previous period; null = no history yet
  final VoidCallback? onTap;

  const HealthGauge({super.key, required this.score, required this.band, this.delta, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppColors.of(context);
    final color = _bandColor(context, band);
    final reduced = reducedMotion(context);
    final target = (score ?? 0).toDouble();

    return PressableScale(
      onTap: onTap,
      child: Card(
        color: color.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: target),
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => CustomPaint(
                    painter: _GaugePainter(value: value, color: color, trackColor: color.withValues(alpha: 0.15)),
                    child: Center(
                      child: score == null
                          ? const Text('—', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
                          : Text(
                              '${value.round()}',
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.companyHealthScore, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      score == null ? l10n.noDataYet : _bandLabel(l10n, band),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (delta == null)
                      Text(l10n.healthNoTrendYet, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            delta! > 0 ? Icons.trending_up : (delta! < 0 ? Icons.trending_down : Icons.trending_flat),
                            size: 15,
                            color: delta! > 0 ? semantic.success : (delta! < 0 ? semantic.danger : theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            delta! > 0
                                ? l10n.healthTrendUpBy(delta!)
                                : (delta! < 0 ? l10n.healthTrendDownBy(delta!) : l10n.healthTrendFlat),
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value; // 0-100
  final Color color;
  final Color trackColor;
  const _GaugePainter({required this.value, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 8.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 0, 2 * math.pi, false, track);

    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * (value.clamp(0, 100) / 100);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
}

// ---------------- BREAKDOWN SCREEN ----------------
class HealthScoreScreen extends StatefulWidget {
  final void Function(String module) onNavigateToModule;
  const HealthScoreScreen({super.key, required this.onNavigateToModule});

  @override
  State<HealthScoreScreen> createState() => _HealthScoreScreenState();
}

class _HealthScoreScreenState extends State<HealthScoreScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.healthScore();
      setState(() => _data = d);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showHowCalculated() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.healthHowCalculatedTitle),
        content: Text(l10n.healthHowCalculatedBody),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.done))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.healthBreakdownTitle),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showHowCalculated),
        ],
      ),
      body: _loading
          ? const ShimmerSkeletonList()
          : _error != null
              ? Center(child: Text(_error!))
              : _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final data = _data!;
    final overall = data['overall'] as int?;
    final band = data['band'] as String?;
    final components = (data['components'] as List).cast<Map>();
    final drags = (data['drags'] as List).cast<Map>();
    final trend = data['trend'] as Map?;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HealthGauge(score: overall, band: band, delta: trend?['delta'] as int?),
          const SizedBox(height: 28),
          ...components.indexed.map((e) => StaggeredListItem(index: e.$1, child: _componentBar(l10n, e.$2))),
          const SizedBox(height: 16),
          Text(l10n.healthBiggestDrags, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (drags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.healthNoDrags, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            ...drags.indexed.map((e) => StaggeredListItem(index: e.$1, child: _dragTile(l10n, e.$2, components))),
        ],
      ),
    );
  }

  Widget _componentBar(AppLocalizations l10n, Map c) {
    final theme = Theme.of(context);
    final included = c['included'] == true;
    final score = (c['score'] as num?)?.toDouble();
    final weight = (c['effectiveWeight'] as num?)?.toDouble() ?? 0;
    final color = included ? _scoreColor(context, score!) : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_componentLabel(l10n, c['key'] as String), style: theme.textTheme.titleSmall)),
              Text(
                included ? '${score!.round()}' : '—',
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: included ? (score! / 100).clamp(0, 1) : 0,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  included ? _componentReason(l10n, c) : l10n.healthExcludedNoData,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.healthWeightLabel(weight.round()),
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dragTile(AppLocalizations l10n, Map d, List<Map> components) {
    final theme = Theme.of(context);
    final semantic = AppColors.of(context);
    final match = components.firstWhere((c) => c['key'] == d['key'], orElse: () => d);
    final module = d['module'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.trending_down, color: semantic.danger),
        title: Text(_componentLabel(l10n, d['key'] as String), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_componentReason(l10n, match)),
        trailing: module != null ? Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant) : null,
        onTap: module == null
            ? null
            : () {
                Navigator.pop(context);
                widget.onNavigateToModule(module);
              },
      ),
    );
  }
}
