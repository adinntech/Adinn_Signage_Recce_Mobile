import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/l10n/ta_report.dart';

void main() {
  test('probe', () {
    for (final s in [
      'ADINN SIGNAGE - SITE RECCE REPORT',
      'DRAFT – NOT APPROVED FOR FABRICATION',
      'Original site photo – Front view (Unit 01)',
      '2D front elevation',
      'Dimension',
    ]) {
      // ignore: avoid_print
      print('VOCAB|$s|${TamilReport.tr(s)}');
    }
  });
}
