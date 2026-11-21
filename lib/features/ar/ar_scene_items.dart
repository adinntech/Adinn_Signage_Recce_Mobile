import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../drawing/signage_geometry.dart';
import '../preview_live/live_preview_controller.dart' show unitGeometry;
import 'ar_model_builder.dart';

/// A signage item already configured in the shop recce that can be inserted
/// into the AR scene. Read-only view of the business record: the AR editor
/// never creates or edits signage items through it.
@immutable
class ArSceneItem {
  const ArSceneItem({
    required this.unitId,
    required this.groupId,
    required this.mediaCode,
    required this.installationCode,
    required this.mediaName,
    required this.mediaShortName,
    required this.unitLabel,
    required this.sizeText,
    required this.installationName,
    required this.widthFt,
    required this.heightFt,
    required this.hasSize,
    required this.preferVertical,
    required this.doubleSided,
    required this.isFlange,
    required this.signature,
    required this.buildModel,
    this.unavailableReason,
  });

  /// Signage Item ID ([SignageUnit.id]).
  final String unitId;

  /// Media Group ID ([Board.id]).
  final String groupId;
  final String mediaCode;
  final String installationCode;
  final String mediaName;
  final String mediaShortName;

  /// "Unit 01".
  final String unitLabel;

  /// Entered size, e.g. "8 × 3 ft" (or "Size not set").
  final String sizeText;
  final String installationName;
  final double widthFt;
  final double heightFt;

  /// False: no size entered yet, the model uses the default preview size.
  final bool hasSize;
  final bool preferVertical;
  final bool doubleSided;
  final bool isFlange;

  /// Geometry the model is generated from; changes when dimensions or
  /// installation details change (used to refresh the rendered model).
  final Object signature;

  /// Builds the AR model lazily (only when the item is inserted).
  final ArModelData Function() buildModel;

  /// Why no 3D model can be generated (null = available).
  final String? unavailableReason;

  bool get modelAvailable => unavailableReason == null;

  /// "GSB – Unit 01".
  String get label => '$mediaShortName – $unitLabel';

  /// Glass is often not detected by ARCore.
  bool get mayNeedManualPlacement =>
      SignageCatalog.glassPasting == installationCode;

  String get surfaceHint => preferVertical
      ? (mayNeedManualPlacement
            ? 'Vertical (glass – may need manual placement)'
            : 'Vertical surface (wall)')
      : 'Horizontal surface (floor / ground)';
}

/// Every signage unit of every media group in [shop], in recce order.
List<ArSceneItem> arSceneItemsForShop(Shop shop, {String brand = 'ADINN'}) => [
  for (final b in shop.boards)
    for (final u in b.activeUnits) arSceneItemFor(b, u, brand: brand),
];

ArSceneItem arSceneItemFor(Board b, SignageUnit u, {String brand = 'ADINN'}) {
  final media = SignageCatalog.media(b.mediaCode);
  final installationCode = b.installationOf(u);
  final inst = SignageCatalog.installation(installationCode);
  final String? unavailable = b.mediaCode == null || media == null
      ? 'Media type not selected'
      : (installationCode == null || inst == null
            ? 'Installation type not selected'
            : null);
  final SignageGeometry g = unitGeometry(b, u);
  return ArSceneItem(
    unitId: u.id,
    groupId: b.id,
    mediaCode: b.mediaCode ?? '',
    installationCode: installationCode ?? '',
    mediaName: media?.name ?? 'Media not set',
    mediaShortName: media?.shortName ?? b.name,
    unitLabel: b.unitLabel(u),
    sizeText: fmtSize(b.widthOf(u), b.heightOf(u), b.unit),
    installationName: inst?.name ?? 'Installation not set',
    widthFt: g.widthFt,
    heightFt: g.heightFt,
    hasSize: b.unitHasSize(u),
    preferVertical: prefersVerticalPlacement(installationCode),
    doubleSided: g.doubleSided,
    isFlange: installationCode == SignageCatalog.flangeBracket,
    signature: g,
    buildModel: () => buildArModel(b, u, brand: brand),
    unavailableReason: unavailable,
  );
}
