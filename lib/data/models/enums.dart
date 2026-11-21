import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

enum UserRole { vendor, businessTeam, recceOps }

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.vendor => 'Recce Vendor',
    UserRole.businessTeam => 'Business Team',
    UserRole.recceOps => 'Recce Operations',
  };

  bool get isReviewer => this != UserRole.vendor;
}

/// Lifecycle of a shop recce, from assignment until final approval.
enum RecceStatus {
  notStarted,
  inProgress,
  pendingBusiness,
  pendingOps,
  approved,
  rejectedBusiness,
  rejectedOps,
}

extension RecceStatusX on RecceStatus {
  String get label => switch (this) {
    RecceStatus.notStarted => 'Not Started',
    RecceStatus.inProgress => 'In Progress',
    RecceStatus.pendingBusiness => 'Pending Business Approval',
    RecceStatus.pendingOps => 'Pending Ops Approval',
    RecceStatus.approved => 'Approved',
    RecceStatus.rejectedBusiness => 'Rejected by Business',
    RecceStatus.rejectedOps => 'Rejected by Ops',
  };

  String get shortLabel => switch (this) {
    RecceStatus.notStarted => 'Not Started',
    RecceStatus.inProgress => 'In Progress',
    RecceStatus.pendingBusiness => 'With Business',
    RecceStatus.pendingOps => 'With Ops',
    RecceStatus.approved => 'Approved',
    RecceStatus.rejectedBusiness => 'Rejected',
    RecceStatus.rejectedOps => 'Rejected',
  };

  Color get color => switch (this) {
    RecceStatus.notStarted => AdinnColors.muted,
    RecceStatus.inProgress => AdinnColors.info,
    RecceStatus.pendingBusiness => AdinnColors.warning,
    RecceStatus.pendingOps => AdinnColors.purple,
    RecceStatus.approved => AdinnColors.success,
    RecceStatus.rejectedBusiness => AdinnColors.red,
    RecceStatus.rejectedOps => AdinnColors.red,
  };

  IconData get icon => switch (this) {
    RecceStatus.notStarted => Icons.radio_button_unchecked,
    RecceStatus.inProgress => Icons.edit_note,
    RecceStatus.pendingBusiness => Icons.hourglass_top,
    RecceStatus.pendingOps => Icons.engineering,
    RecceStatus.approved => Icons.verified,
    RecceStatus.rejectedBusiness => Icons.report_gmailerrorred,
    RecceStatus.rejectedOps => Icons.report_gmailerrorred,
  };

  /// Vendor may edit the recce in these states.
  bool get isEditable =>
      this == RecceStatus.notStarted ||
      this == RecceStatus.inProgress ||
      this == RecceStatus.rejectedBusiness ||
      this == RecceStatus.rejectedOps;

  bool get isPending =>
      this == RecceStatus.pendingBusiness || this == RecceStatus.pendingOps;

  bool get isRejected =>
      this == RecceStatus.rejectedBusiness || this == RecceStatus.rejectedOps;
}

enum MeasureUnit { ft, inch, m, mm }

extension MeasureUnitX on MeasureUnit {
  String get label => switch (this) {
    MeasureUnit.ft => 'ft',
    MeasureUnit.inch => 'in',
    MeasureUnit.m => 'm',
    MeasureUnit.mm => 'mm',
  };

  /// Number of feet in one of this unit.
  double get feetFactor => switch (this) {
    MeasureUnit.ft => 1.0,
    MeasureUnit.inch => 1 / 12,
    MeasureUnit.m => 3.280839895,
    MeasureUnit.mm => 0.003280839895,
  };

  double toFeet(double value) => value * feetFactor;
  double fromFeet(double feet) => feet / feetFactor;
}

enum ReviewStage { business, ops }

extension ReviewStageX on ReviewStage {
  String get label => switch (this) {
    ReviewStage.business => 'Business Team',
    ReviewStage.ops => 'Recce Operations',
  };
}

enum ReviewDecision { approved, rejected }

/// Photo markings. `rectangle` is the (original) measured signage placement
/// rectangle; the rest were added for the advanced editor. New values are
/// appended so stored names stay valid.
enum AnnotationType {
  rectangle,
  arrow,
  text,
  shapeRect,
  circle,
  line,
  freehand,
  dimension,
  measureLabel,
  poleMarker,
  pipeMarker,
  groundMarker,
  numberMarker,
}

/// Independent visibility layers of the photo editor. The original photo
/// and the 3D model overlay are layers too, but hold no annotations.
enum AnnotationLayer { photo, drawing, text, measurements, placement, model }

extension AnnotationLayerX on AnnotationLayer {
  String get label => switch (this) {
    AnnotationLayer.photo => 'Original photo',
    AnnotationLayer.drawing => 'Drawing',
    AnnotationLayer.text => 'Text',
    AnnotationLayer.measurements => 'Measurements',
    AnnotationLayer.placement => 'Board placement',
    AnnotationLayer.model => 'Model overlay',
  };
}

extension AnnotationTypeX on AnnotationType {
  /// Drawn from a start to an end point ([Annotation.x],[Annotation.y] →
  /// [Annotation.x2],[Annotation.y2]).
  bool get isTwoPoint =>
      this == AnnotationType.arrow ||
      this == AnnotationType.line ||
      this == AnnotationType.dimension;

  bool get isFreehand => this == AnnotationType.freehand;

  /// Centre + size + rotation boxes (resizable and rotatable).
  bool get isBox => !isTwoPoint && !isFreehand;

  bool get isMarker =>
      this == AnnotationType.poleMarker ||
      this == AnnotationType.pipeMarker ||
      this == AnnotationType.groundMarker ||
      this == AnnotationType.numberMarker;

  AnnotationLayer get layer => switch (this) {
    AnnotationType.text => AnnotationLayer.text,
    AnnotationType.dimension ||
    AnnotationType.measureLabel => AnnotationLayer.measurements,
    AnnotationType.rectangle ||
    AnnotationType.poleMarker ||
    AnnotationType.pipeMarker ||
    AnnotationType.groundMarker ||
    AnnotationType.numberMarker => AnnotationLayer.placement,
    _ => AnnotationLayer.drawing,
  };

  String get label => switch (this) {
    AnnotationType.rectangle => 'Signage placement',
    AnnotationType.arrow => 'Arrow',
    AnnotationType.text => 'Text',
    AnnotationType.shapeRect => 'Rectangle',
    AnnotationType.circle => 'Circle',
    AnnotationType.line => 'Line',
    AnnotationType.freehand => 'Freehand',
    AnnotationType.dimension => 'Dimension line',
    AnnotationType.measureLabel => 'Measurement label',
    AnnotationType.poleMarker => 'Pole location',
    AnnotationType.pipeMarker => 'Support pipe',
    AnnotationType.groundMarker => 'Ground level',
    AnnotationType.numberMarker => 'Numbered marker',
  };
}

/// What a reviewer can point at when rejecting a specific signage item.
enum IssueAspect { item, photo, annotation, dimension, installation }

extension IssueAspectX on IssueAspect {
  String get label => switch (this) {
    IssueAspect.item => 'Signage item',
    IssueAspect.photo => 'Photo',
    IssueAspect.annotation => 'Annotation',
    IssueAspect.dimension => 'Dimension',
    IssueAspect.installation => 'Installation detail',
  };
}

/// How the size of a multi-unit media group is captured.
enum SizeMode { same, different }

/// Kind of generated image stored against a signage item.
enum CaptureKind { live, ar, edited }

extension CaptureKindX on CaptureKind {
  String get label => switch (this) {
    CaptureKind.live => 'Live preview',
    CaptureKind.ar => 'AR capture',
    CaptureKind.edited => 'Annotated photo',
  };
}

enum QuestionType { text, number, yesNo, choice }
