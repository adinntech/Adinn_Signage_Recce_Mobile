/// What a shop that comes from the server (not from the device's own demo data) lets the usual screens do. The screens only know
/// this small interface; the real work (saving the draft, uploading photos, submitting) is done by the live recce controllers.
abstract class LiveShopLink {
  /// The local copy of the shop was edited: the link copies what changed to the server's draft (soon, in one go).
  void localChanged();

  /// Saves the draft on the server now. Returns the server's error text, or null.
  Future<String?> saveDraft();

  /// Submits the shop to the server. Returns the problems to show (local checks or the server's text), or an empty list
  /// when it went through; [version] is set on success.
  Future<LiveSubmitResult> submit(String remarks);
}

class LiveSubmitResult {
  const LiveSubmitResult({this.problems = const [], this.version});
  final List<String> problems;
  final int? version;
  bool get ok => problems.isEmpty;
}
