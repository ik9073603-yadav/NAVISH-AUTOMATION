import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:animations/animations.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';

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
      setState(() => _history = h);
    } catch (e) {
      setState(() => _error = '$e');
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
    final mins = end.difference(start).inMinutes;
    if (mins < 60) return '$mins min';
    if (mins < 1440) return '${(mins / 60).toStringAsFixed(1)} hrs';
    return '${(mins / 1440).toStringAsFixed(1)} days';
  }

  String? _plannedMinsLabel(int? plannedMins) {
    if (plannedMins == null) return null;
    if (plannedMins < 60) return '$plannedMins min';
    if (plannedMins < 1440) return '${(plannedMins / 60).toStringAsFixed(1)} hrs';
    return '${(plannedMins / 1440).toStringAsFixed(1)} days';
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
    late final Color color;
    late final IconData icon;
    switch (sla) {
      case 'DELAYED':
        color = semantic.danger;
        icon = Icons.warning;
        final names = lateStages.map((s) => s['name'] as String).join(', ');
        text = lateStages.length == 1
            ? 'Delayed — late at: $names'
            : 'Delayed — late at ${lateStages.length} stages: $names';
        break;
      case 'ON_TIME':
        color = semantic.success;
        icon = Icons.check_circle;
        text = 'On time so far';
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        icon = Icons.info_outline;
        text = 'No SLA — every stage here is unplanned';
    }

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
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
                      color: completed ? Colors.green : Colors.grey,
                      size: 22,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey.shade300,
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
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Planned: ${plannedLabel ?? "no deadline (unplanned)"}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Entered: $entered', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Completed: $completedText', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (duration != null)
              Text('Time taken: $duration', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (completedByName != null)
              Text('Done by: $completedByName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (delayMins != null)
              Text(
                delayed ? 'Delayed by $delayMins min' : 'On time (${-delayMins!} min to spare)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: delayed ? Colors.red : Colors.green,
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
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                    child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover),
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
            TextSpan(text: '$label: ', style: const TextStyle(color: Colors.grey)),
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
          child: Image.network(url),
        ),
      ),
    );
  }
}
