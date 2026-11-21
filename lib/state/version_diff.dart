import '../core/utils/formatters.dart';
import '../data/catalog/signage_catalog.dart';
import '../data/models/models.dart';

/// Human-readable list of what changed between two versions of a shop recce.
List<String> diffShops(Shop? before, Shop after) {
  if (before == null) return ['First submission'];
  final changes = <String>[];

  void field(String label, String a, String b) {
    if (a.trim() != b.trim()) changes.add('$label changed');
  }

  field('Shop name', before.name, after.name);
  field('Contact number', before.phone, after.phone);
  field('Address', before.fullAddress, after.fullAddress);
  field('Owner', before.ownerName, after.ownerName);
  final oldGeo = before.geo, newGeo = after.geo;
  if (oldGeo?.coordinates != newGeo?.coordinates) {
    changes.add(switch ((oldGeo, newGeo)) {
      (null, _) => 'Shop GPS location captured',
      (_, null) => 'Shop GPS location removed',
      (final a?, final b?) =>
        'Shop GPS location updated (moved ${fmtDistance(a.distanceTo(b))})',
    });
  }

  final oldBoards = {for (final b in before.boards) b.id: b};
  final newBoards = {for (final b in after.boards) b.id: b};

  for (final b in after.boards) {
    final o = oldBoards[b.id];
    if (o == null) {
      changes.add('Board added: ${b.name}');
      continue;
    }
    final name = b.name;
    if (o.name != b.name) changes.add('Board renamed: ${o.name} → ${b.name}');
    if (o.mediaCode != b.mediaCode) {
      changes.add(
        '$name: media ${SignageCatalog.media(o.mediaCode)?.shortName ?? '—'} → '
        '${SignageCatalog.media(b.mediaCode)?.shortName ?? '—'}',
      );
    }
    if (o.installationCode != b.installationCode) {
      changes.add(
        '$name: installation ${SignageCatalog.installation(o.installationCode)?.name ?? '—'} → '
        '${SignageCatalog.installation(b.installationCode)?.name ?? '—'}',
      );
    }
    if (o.width != b.width || o.height != b.height || o.unit != b.unit) {
      changes.add(
        '$name: size ${fmtSize(o.width, o.height, o.unit)} → '
        '${fmtSize(b.width, b.height, b.unit)}',
      );
    }
    if (o.quantity != b.quantity) {
      changes.add('$name: quantity ${o.quantity} → ${b.quantity}');
    }
    if (o.isSameSize != b.isSameSize) {
      changes.add(
        '$name: ${b.isSameSize ? 'all units same size' : 'units now have different sizes'}',
      );
    }
    for (final u in b.activeUnits) {
      final ou = o.unitById(u.id);
      if (ou == null) continue;
      final label = '$name ${b.unitLabel(u)}';
      if (!b.isSameSize &&
          (o.widthOf(ou) != b.widthOf(u) || o.heightOf(ou) != b.heightOf(u))) {
        changes.add(
          '$label: size ${fmtSize(o.widthOf(ou), o.heightOf(ou), o.unit)} → '
          '${fmtSize(b.widthOf(u), b.heightOf(u), b.unit)}',
        );
      }
      if (ou.placement.trim() != u.placement.trim()) {
        changes.add('$label: placement updated');
      }
      if (o.installationOf(ou) != b.installationOf(u) ||
          ou.installationDetails.trim() != u.installationDetails.trim()) {
        changes.add('$label: installation details updated');
      }
      if (ou.notes.trim() != u.notes.trim()) {
        changes.add('$label: notes updated');
      }
    }
    if (o.previews.length != b.previews.length) {
      changes.add(
        '$name: previews / AR captures ${o.previews.length} → '
        '${b.previews.length}',
      );
    }
    if (o.photos.length != b.photos.length) {
      changes.add('$name: photos ${o.photos.length} → ${b.photos.length}');
    }
    if (o.annotationCount != b.annotationCount) {
      changes.add(
        '$name: photo markings ${o.annotationCount} → ${b.annotationCount}',
      );
    }
    if (o.voiceNotes.length != b.voiceNotes.length) {
      changes.add(
        '$name: voice notes ${o.voiceNotes.length} → ${b.voiceNotes.length}',
      );
    }
    if (o.textNote.trim() != b.textNote.trim()) {
      changes.add('$name: text note updated');
    }
    final keys = {...o.answers.keys, ...b.answers.keys};
    final changedAnswers = keys.where((k) => o.answers[k] != b.answers[k]);
    if (changedAnswers.isNotEmpty) {
      changes.add('$name: ${changedAnswers.length} site answer(s) updated');
    }
  }
  for (final o in before.boards) {
    if (!newBoards.containsKey(o.id)) changes.add('Board removed: ${o.name}');
  }
  if (changes.isEmpty) changes.add('No changes from previous version');
  return changes;
}
