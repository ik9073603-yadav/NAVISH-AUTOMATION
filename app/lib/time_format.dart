// Shared time/duration formatting — one implementation reused everywhere a
// minute count or an ISO timestamp needs a human-readable label, instead of
// the same "min/hrs/days" (or "time ago") logic reimplemented per screen.

// "N min" / "N.N hrs" / "N.N days", for a non-negative minute count.
String formatDurationMins(int mins) {
  if (mins < 60) return '$mins min';
  if (mins < 1440) return '${(mins / 60).toStringAsFixed(1)} hrs';
  return '${(mins / 1440).toStringAsFixed(1)} days';
}

// Same as [formatDurationMins], but zero/negative reads as '—' instead of
// "0 min" — for call sites where "no data yet" must look different from
// "took no time at all".
String formatDurationMinsOrDash(int mins) {
  if (mins <= 0) return '—';
  return formatDurationMins(mins);
}

// "just now" / "N min ago" / "N hr ago" / "N day(s) ago", from an ISO
// timestamp compared to now.
String timeAgo(String iso) {
  final mins = DateTime.now().difference(DateTime.parse(iso).toLocal()).inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  final hrs = mins ~/ 60;
  if (hrs < 24) return '$hrs hr ago';
  return '${hrs ~/ 24} day(s) ago';
}
