import '../../data/models/enums.dart';
import 'formatters.dart';

const _num = r'(\d+(?:\.\d+)?(?:\s+\d+/\d+)?|\d+/\d+|\.\d+)';
final _ftIn = RegExp('^(?:$_num\\s*\')?\\s*(?:$_num\\s*"?)?\$');
final _metric = RegExp(r'^(\d+(?:\.\d+)?|\.\d+)\s*(mm|cm|m)$');
final _ftWord = RegExp(r'(?<![a-z])(feet|foot|ft)(?![a-z])\.?');
final _inWord = RegExp(r'(?<![a-z])(inches|inch|in)(?![a-z])\.?');

/// "6", "6.5", "1/2", "6 1/2" → value (null when malformed).
double? _parseNum(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  final parts = t.split(RegExp(r'\s+'));
  var total = 0.0;
  for (final p in parts) {
    if (p.contains('/')) {
      final f = p.split('/');
      if (f.length != 2) return null;
      final n = double.tryParse(f[0]), d = double.tryParse(f[1]);
      if (n == null || d == null || d == 0) return null;
      total += n / d;
    } else {
      final v = double.tryParse(p);
      if (v == null) return null;
      total += v;
    }
  }
  return total.isFinite ? total : null;
}

/// Parses a typed length into feet (full precision, no rounding).
///
/// Imperial units ([MeasureUnit.ft] / [MeasureUnit.inch]) accept feet and
/// inches: `5 ft 6 in`, `5' 6"`, `5'6`, `66 in`, `66"`, `5.5 ft`,
/// `2 ft 3 1/2 in`. A bare number is read in [unit] (feet for ft, inches for
/// inch, metres / millimetres for metric). An explicit `m` / `cm` / `mm`
/// suffix is always honoured. Returns null for text that is not a length;
/// the sign is kept so callers can reject negative values with a clear
/// message.
double? parseLengthToFeet(String raw, MeasureUnit unit) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  var sign = 1.0;
  if (s.startsWith('-')) {
    sign = -1;
    s = s.substring(1).trim();
  }
  s = s
      .replaceAll('’', "'")
      .replaceAll('′', "'")
      .replaceAll('”', '"')
      .replaceAll('″', '"')
      .replaceAll("''", '"');
  final metric = _metric.firstMatch(s);
  if (metric != null) {
    final v = double.parse(metric.group(1)!);
    final mm = switch (metric.group(2)) {
      'mm' => v,
      'cm' => v * 10,
      _ => v * 1000,
    };
    return sign * mm / 304.8;
  }
  s = s.replaceAll(_ftWord, "'").replaceAll(_inWord, '"').trim();
  final hasMarker = s.contains("'") || s.contains('"');
  double? feet;
  if (!hasMarker) {
    final v = _parseNum(s);
    if (v != null) feet = unit.toFeet(v);
  } else {
    final m = _ftIn.firstMatch(s);
    if (m != null && (m.group(1) != null || m.group(2) != null)) {
      final f = m.group(1) == null ? 0.0 : _parseNum(m.group(1));
      final i = m.group(2) == null ? 0.0 : _parseNum(m.group(2));
      if (f != null && i != null) feet = f + i / 12;
    }
  }
  if (feet == null || !feet.isFinite) return null;
  return sign * feet;
}

/// "5 ft 6 in", "10 ft", "9 in", "2 ft 3.5 in" (inches to 0.01 in).
String fmtFeetInches(double feet) {
  if (!feet.isFinite) return '—';
  final neg = feet < 0;
  final hundredths = (feet.abs() * 1200).round(); // 1/100 inch
  final ft = hundredths ~/ 1200;
  final rest = hundredths - ft * 1200;
  final inch = rest / 100;
  final parts = <String>[
    if (ft > 0) '$ft ft',
    if (inch > 0 || ft == 0) '${fmtNum(inch)} in',
  ];
  return '${neg ? '-' : ''}${parts.join(' ')}';
}

/// Text shown in an exact-length field for [feet] in the board's unit.
String formatLengthInput(double feet, MeasureUnit unit) => switch (unit) {
  MeasureUnit.ft || MeasureUnit.inch => fmtFeetInches(feet),
  MeasureUnit.m => '${fmtNum(unit.fromFeet(feet), maxDecimals: 3)} m',
  MeasureUnit.mm => '${fmtNum(unit.fromFeet(feet), maxDecimals: 0)} mm',
};

/// Validation result for a typed length (null = valid).
String? validateLengthFeet(
  double? feet, {
  required String label,
  double minFt = 0,
  double? maxFt,
  bool allowZero = false,
}) {
  if (feet == null) return 'Enter $label like 5 ft 6 in';
  if (feet < 0) return '$label cannot be negative';
  if (feet == 0 && !allowZero) return '$label must be greater than zero';
  if (feet < minFt) return '$label must be at least ${fmtFeetInches(minFt)}';
  if (maxFt != null && feet > maxFt) {
    return '$label cannot exceed ${fmtFeetInches(maxFt)}';
  }
  return null;
}
