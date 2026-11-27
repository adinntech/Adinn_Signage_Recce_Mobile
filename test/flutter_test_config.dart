import 'dart:async';

import 'package:signage_recce/data/models/evidence_policy.dart';

/// Automated tests run in explicit demo / test evidence mode (fake file
/// paths, built-in demo photos). Tests of the production rule switch it off
/// themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  EvidencePolicy.allowDemo = true;
  EvidencePolicy.checkFiles = false;
  await testMain();
}
