import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../l10n/gen/app_localizations.dart';

// Shared visual building blocks for every analysis screen (Flow, Employee,
// Department, Task, Inventory) so a senior-analyst look — hero stats with
// trend deltas, ranked leaderboards, donuts, gauges, funnels, a plain-
// language takeaway, and the AI Insights seam — is one implementation
// instead of five near-duplicates that would drift apart over time.

// ─────────────────────────── Hero stat tile ───────────────────────────

// The headline number for a section, with an optional vs-previous-period
// delta. `higherIsBetter` decides whether an increase paints green or red
// (e.g. on-time % up is good; escalations up is bad) — colors always follow
// meaning, never the raw sign of the number.
class HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final double? deltaPct;
  final bool higherIsBetter;
  final Color? accent;
  final VoidCallback? onTap;

  const HeroStat({
    super.key,
    required this.value,
    required this.label,
    this.deltaPct,
    this.higherIsBetter = true,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppTheme.tabularFigures(theme.textTheme.headlineLarge).copyWith(color: color)),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (deltaPct != null) ...[
                const SizedBox(height: 6),
                DeltaBadge(deltaPct: deltaPct!, higherIsBetter: higherIsBetter),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DeltaBadge extends StatelessWidget {
  final double deltaPct;
  final bool higherIsBetter;
  const DeltaBadge({super.key, required this.deltaPct, required this.higherIsBetter});

  @override
  Widget build(BuildContext context) {
    final semantic = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final isFlat = deltaPct.abs() < 0.5;
    final isUp = deltaPct > 0;
    final good = isFlat ? null : (isUp == higherIsBetter);
    final color = isFlat
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (good! ? semantic.success : semantic.danger);
    final icon = isFlat ? Icons.remove : (isUp ? Icons.arrow_upward : Icons.arrow_downward);

    return Tooltip(
      message: l10n.vsPreviousPeriod,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 2),
          Text('${deltaPct.abs().toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// Computes a percentage delta between two comparable numbers, or null if
// the previous value can't meaningfully anchor a percentage (zero).
double? deltaPctOf(num current, num previous) {
  if (previous == 0) return null;
  return ((current - previous) / previous) * 100.0;
}

// ─────────────────────────── Takeaway line ───────────────────────────

// One plain-language sentence summarizing the section above it — e.g. "3
// orders are dragging on-time % down to 78%". Purely presentational; the
// caller supplies the sentence since only it knows which fact is worth
// surfacing.
class TakeawayLine extends StatelessWidget {
  final String text;
  final IconData icon;
  const TakeawayLine({super.key, required this.text, this.icon = Icons.insights_outlined});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── AI Insights seam ───────────────────────────

// Inactive placeholder shown on every analysis screen. Deliberately takes
// the screen's structured data (not just for show — this is the exact
// shape a future AI call would receive) even though nothing is sent
// anywhere yet, so wiring a real provider later is a matter of swapping
// this widget's body, not re-plumbing every screen.
class AiInsightsCard extends StatelessWidget {
  final Map<String, dynamic> screenData;
  const AiInsightsCard({super.key, required this.screenData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant, strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.onSurfaceVariant, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.aiInsightsTitle, style: theme.textTheme.titleSmall),
                      const SizedBox(width: 6),
                      Icon(Icons.lock_outline, size: 13, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.aiInsightsPlaceholder,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Section header ───────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Donut (composition) ───────────────────────────

class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice(this.label, this.value, this.color);
}

// Composition breakdown (status split, category split, ...) as a donut with
// a center total/percentage and a row-legend beside it.
class DonutComposition extends StatelessWidget {
  final List<DonutSlice> slices;
  final String centerValue;
  final String? centerLabel;

  const DonutComposition({super.key, required this.slices, required this.centerValue, this.centerLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: total <= 0
                    ? [
                        PieChartSectionData(
                          value: 1,
                          color: theme.colorScheme.surfaceContainerHighest,
                          showTitle: false,
                          radius: 20,
                        ),
                      ]
                    : [
                        for (final s in slices)
                          PieChartSectionData(value: s.value, color: s.color, showTitle: false, radius: 20),
                      ],
              )),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerValue, style: theme.textTheme.titleLarge),
                  if (centerLabel != null)
                    Text(centerLabel!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.label, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                      Text('${s.value.toInt()}', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Gauge ring (single %) ───────────────────────────

// A single percentage as a progress ring, color-banded by threshold — used
// wherever one number matters more than a breakdown (on-time %, compliance %).
class GaugeRing extends StatelessWidget {
  final double pct; // 0-100
  final String? centerLabel;
  final double size;

  const GaugeRing({super.key, required this.pct, this.centerLabel, this.size = 96});

  Color _colorFor(BuildContext context) {
    final c = AppColors.of(context);
    if (pct >= 80) return c.success;
    if (pct >= 50) return c.warning;
    return c.danger;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              strokeWidth: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${pct.round()}%', style: theme.textTheme.titleLarge?.copyWith(color: color)),
              if (centerLabel != null)
                Text(centerLabel!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Ranked bars (leaderboard) ───────────────────────────

class RankedBarItem {
  final String label;
  final double value;
  final String valueText;
  final Color? color;
  final VoidCallback? onTap;
  const RankedBarItem({required this.label, required this.value, required this.valueText, this.color, this.onTap});
}

// Horizontal ranked bars, best→worst — a leaderboard, not a bar chart axis:
// the bar length itself carries the ranking, name and value sit on the row.
class RankedBarList extends StatelessWidget {
  final List<RankedBarItem> items;
  const RankedBarList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final maxValue = items.fold<double>(0, (a, i) => i.value > a ? i.value : a);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: InkWell(
              onTap: item.onTap,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(item.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final frac = maxValue <= 0 ? 0.0 : (item.value / maxValue).clamp(0, 1);
                          return Stack(
                            children: [
                              Container(height: 16, color: theme.colorScheme.surfaceContainerHighest),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                height: 16,
                                width: constraints.maxWidth * frac,
                                color: item.color ?? theme.colorScheme.primary,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(item.valueText, textAlign: TextAlign.end, style: theme.textTheme.labelMedium),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── Funnel (stage drop-off) ───────────────────────────

class FunnelStep {
  final String label;
  final int count;
  const FunnelStep(this.label, this.count);
}

// Stage-to-stage drop-off as a true visual funnel: bars centered and
// shrinking in width down the list, each annotated with the % retained
// from the previous step.
class FunnelChart extends StatelessWidget {
  final List<FunnelStep> steps;
  const FunnelChart({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final maxCount = steps.first.count <= 0 ? 1 : steps.first.count;
    final accent = theme.colorScheme.primary;

    return Column(
      children: [
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final frac = (steps[i].count / maxCount).clamp(0.08, 1.0);
                    final color = Color.lerp(accent, theme.colorScheme.tertiary, i / (steps.length <= 1 ? 1 : steps.length - 1))!;
                    return Container(
                      width: constraints.maxWidth * frac,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '${steps[i].label} · ${steps[i].count}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _onColor(color)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
                if (i > 0 && steps[i - 1].count > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${((steps[i].count / steps[i - 1].count) * 100).round()}% retained',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Color _onColor(Color bg) => ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black87;
}
