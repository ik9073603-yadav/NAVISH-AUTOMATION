import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:animations/animations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';
import 'widgets/motion.dart';
import 'widgets/cost_of_delay_info.dart';

class OrderHistoryScreen extends StatefulWidget {
  final String orderId;
  final String orderNumber;

  const OrderHistoryScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  Map<String, dynamic>? _history;
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
      final h = await Api.orderHistory(widget.orderId);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static final _fmt = DateFormat('MMM d, h:mm a');

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    return _fmt.format(DateTime.parse(iso).toLocal());
  }

  String _duration(String? enteredAt, String? completedAt) {
    if (enteredAt == null) return '';
    final start = DateTime.parse(enteredAt);
    final end = completedAt != null ? DateTime.parse(completedAt) : DateTime.now();
    return formatDurationMins(end.difference(start).inMinutes);
  }

  String? _plannedMinsLabel(int? plannedMins) {
    if (plannedMins == null) return null;
    return formatDurationMins(plannedMins);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.orderNumber} — history')),
      body: _loading
          ? const ShimmerSkeletonList()
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _slaBanner(),
                    Expanded(child: _buildTimeline()),
                  ],
                ),
    );
  }

  Widget _slaBanner() {
    final sla = _history?['slaStatus'] as String?;
    if (sla == null) return const SizedBox.shrink();

    final stages = (_history?['stages'] as List?) ?? [];
    final lateStages = stages.cast<Map>().where((s) {
      final delayMins = s['delayMins'] as int?;
      return delayMins != null && delayMins > 0;
    }).toList();

    final semantic = AppColors.of(context);
    late final String text;
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    switch (sla) {
      case 'DELAYED':
        bg = semantic.dangerContainer;
        fg = semantic.onDangerContainer;
        icon = Icons.warning;
        final names = lateStages.map((s) => s['name'] as String).join(', ');
        text = lateStages.length == 1
            ? 'Delayed — late at: $names'
            : 'Delayed — late at ${lateStages.length} stages: $names';
        break;
      case 'ON_TIME':
        bg = semantic.successContainer;
        fg = semantic.onSuccessContainer;
        icon = Icons.check_circle;
        text = 'On time so far';
        break;
      default:
        bg = Theme.of(context).colorScheme.surfaceContainerHigh;
        fg = Theme.of(context).colorScheme.onSurfaceVariant;
        icon = Icons.info_outline;
        text = 'No SLA — every stage here is unplanned';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
          if (sla == 'DELAYED') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 26),
                Text(
                  'Total lost to delay: ${formatRupeesOrPrompt(_history?['orderDelayCost'] as num?)}',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const CostOfDelayInfoButton(iconSize: 16),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final stages = (_history?['stages'] as List?) ?? [];
    if (stages.isEmpty) {
      return const Center(child: Text('No stages yet'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: stages.length,
        itemBuilder: (_, i) {
          final s = stages[i] as Map;
          final isLast = i == stages.length - 1;
          final completed = s['completedAt'] != null;
          final delayMins = s['delayMins'] as int?;
          final delayed = delayMins != null && delayMins > 0;

          return StaggeredListItem(index: i, child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      completed ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: completed
                          ? AppColors.of(context).success
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Theme.of(context).colorScheme.outlineVariant,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _StageCard(
                      name: s['name'] as String,
                      entered: _formatDate(s['enteredAt'] as String?),
                      completedText: completed ? _formatDate(s['completedAt'] as String?) : 'In progress',
                      duration: s['enteredAt'] != null
                          ? _duration(s['enteredAt'] as String?, s['completedAt'] as String?)
                          : null,
                      plannedLabel: _plannedMinsLabel(s['plannedMins'] as int?),
                      delayMins: delayMins,
                      delayed: delayed,
                      delayCost: s['delayCost'] as num?,
                      completedByName: s['completedByName'] as String?,
                      data: (s['data'] as Map?)?.cast<String, dynamic>() ?? {},
                    ),
                  ),
                ),
              ],
            ),
          ));
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final String name;
  final String entered;
  final String completedText;
  final String? duration;
  final String? plannedLabel;
  final int? delayMins;
  final bool delayed;
  final num? delayCost;
  final String? completedByName;
  final Map<String, dynamic> data;

  const _StageCard({
    required this.name,
    required this.entered,
    required this.completedText,
    required this.duration,
    required this.plannedLabel,
    required this.delayMins,
    required this.delayed,
    required this.delayCost,
    required this.completedByName,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final remarks = data['__remarks'] as String?;
    final fieldEntries = data.entries.where((e) => e.key != '__remarks').toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Planned: ${plannedLabel ?? "no deadline (unplanned)"}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text('Entered: $entered', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text('Completed: $completedText', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (duration != null)
              Text('Time taken: $duration', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (completedByName != null)
              Text('Done by: $completedByName', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (delayMins != null)
              Text(
                delayed
                    ? 'Delayed by $delayMins min · ${formatRupeesOrPrompt(delayCost)}'
                    : 'On time (${-delayMins!} min to spare)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: delayed ? AppColors.of(context).danger : AppColors.of(context).success,
                ),
              ),
            if (fieldEntries.isNotEmpty) ...[
              const Divider(height: 20),
              ...fieldEntries.map((e) => _fieldValue(context, e.key, e.value)),
            ],
            if (remarks != null && remarks.trim().isNotEmpty) ...[
              const Divider(height: 20),
              const Text('Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text(remarks, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fieldValue(BuildContext context, String label, dynamic value) {
    if (value is List) {
      final urls = value.whereType<String>().toList();
      if (urls.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: urls.map((url) {
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    sharedAxisRoute(_FullScreenPhoto(url: url),
                        type: SharedAxisTransitionType.scaled),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      placeholder: (context, _) => Container(
                        width: 64,
                        height: 64,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            TextSpan(text: '$value'),
          ],
        ),
      ),
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  final String url;
  const _FullScreenPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, _) => const CircularProgressIndicator(color: Colors.white54),
            errorWidget: (context, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
          ),
        ),
      ),
    );
  }
}
