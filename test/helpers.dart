import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/services/location_service.dart';

/// Answers every visible required site question with a plausible value.
/// Every physical board (unit) answers its own questions.
void completeAnswers(Board b) {
  for (final u in b.activeUnits) {
    final a = SignageCatalog.answersOf(b, u);
    for (var guard = 0; guard < 5; guard++) {
      final missing = [
        ...SignageCatalog.missingAnswersFor(b, u),
        ...SignageCatalog.missingMeasurementsFor(b, u),
      ];
      if (missing.isEmpty) break;
      for (final q in missing) {
        a[q.id] = switch (q.type) {
          QuestionType.yesNo => true,
          QuestionType.choice => q.options.first,
          QuestionType.number => 5.0,
          QuestionType.text => 'ok',
        };
      }
    }
  }
  completeChecklists(b);
}

/// Answers every required media-specific checklist question of every unit
/// (new required validation since the advanced site survey).
void completeChecklists(Board b) {
  for (final u in b.activeUnits) {
    for (final q in SiteChecklists.questionsFor(
      b.mediaCode,
      b.installationOf(u),
    )) {
      if (!q.required || q.isAnswered(u.checklist[q.id])) continue;
      u.checklist[q.id] = ChecklistResponse(
        questionId: q.id,
        value: switch (q.type) {
          ChecklistResponseType.yesNoNa => 'yes',
          ChecklistResponseType.dropdown => q.options.first,
          ChecklistResponseType.numeric => 2,
          _ => 'ok',
        },
        evidencePhotoIds: q.type == ChecklistResponseType.photoEvidence
            ? [if (b.photos.isNotEmpty) b.photos.first.id]
            : null,
      );
    }
  }
}

GeoFix gpsAt(double lat, double lng, {double accuracy = 5}) => GeoFix(
  latitude: lat,
  longitude: lng,
  accuracyM: accuracy,
  capturedAt: DateTime(2026, 11, 17, 10),
);

/// Deterministic GPS for widget tests (no platform plugin involved).
class FakeLocationService implements LocationService {
  FakeLocationService({this.fix, this.error});

  GeoFix? fix;
  LocationException? error;
  int calls = 0;

  @override
  Future<GeoFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls++;
    if (error != null) throw error!;
    return fix ?? gpsAt(10.86270, 78.68970);
  }

  @override
  Future<bool> openSettings({bool appSettings = false}) async => true;
}
