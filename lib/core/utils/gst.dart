/// Optional GST identification number helpers. Pure Dart.
///
/// Validation checks the published 15-character FORMAT only; it cannot (and
/// must not claim to) prove that the number is actually registered.
class Gst {
  Gst._();

  static final _format = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  /// Upper-case, all whitespace removed.
  static String normalize(String input) =>
      input.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// True when [input] is empty (optional) or has a valid GSTIN format.
  static bool isAcceptable(String input) {
    final n = normalize(input);
    return n.isEmpty || _format.hasMatch(n);
  }

  /// Error text for the form (null = fine, including empty).
  static String? error(String input) =>
      isAcceptable(input) ? null : 'Enter a 15-character GST number';
}
