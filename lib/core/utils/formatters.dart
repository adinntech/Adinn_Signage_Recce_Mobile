import 'dart:math';

import '../../data/models/enums.dart';

final _rand = Random();
int _counter = 0;

/// Short unique id, e.g. `b_lq2k9x_3f`.
String newId(String prefix) {
  _counter = (_counter + 1) % 1296;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _rand.nextInt(1296).toRadixString(36).padLeft(2, '0');
  final c = _counter.toRadixString(36).padLeft(2, '0');
  return '${prefix}_$t$c$r';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String two(int v) => v.toString().padLeft(2, '0');

/// 17 Nov 2026 (always in device local time; GPS fixes arrive in UTC)
String fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// 17 Nov 2026, 4:05 PM (device local time)
String fmtDateTime(DateTime utcOrLocal) {
  final d = utcOrLocal.toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${fmtDate(d)}, $h:${two(d.minute)} $ampm';
}

/// "just now", "5 min ago", "3 h ago", "2 days ago", or a date.
String fmtRelative(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final diff = n.difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  return fmtDate(d);
}

/// mm:ss
String fmtDuration(Duration d) =>
    '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';

/// Trims trailing zeros: 10.0 -> "10", 2.50 -> "2.5".
String fmtNum(double v, {int maxDecimals = 2}) {
  var s = v.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// "10 × 4 ft"
String fmtSize(double? w, double? h, MeasureUnit unit) {
  if (w == null || h == null || w <= 0 || h <= 0) return 'Size not set';
  return '${fmtNum(w)} × ${fmtNum(h)} ${unit.label}';
}

/// "45 m" or "1.2 km"
String fmtDistance(double metres) => metres < 1000
    ? '${metres.round()} m'
    : '${fmtNum(metres / 1000, maxDecimals: 1)} km';

/// Feet value rendered in the given unit, e.g. `fmtFeetIn(10, MeasureUnit.inch)`.
String fmtLength(double feet, MeasureUnit unit) =>
    '${fmtNum(unit.fromFeet(feet), maxDecimals: unit == MeasureUnit.mm ? 0 : 2)} ${unit.label}';
