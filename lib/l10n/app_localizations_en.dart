// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Adinn Recce';

  @override
  String get langSwitchTooltip => 'Change language (English / Tamil)';

  @override
  String get langBadge => 'ENG';

  @override
  String get navHome => 'Home';

  @override
  String get navProjects => 'Projects';

  @override
  String get navSubmitted => 'Submitted';

  @override
  String get navApprovals => 'Approvals';

  @override
  String get navActivity => 'Activity';

  @override
  String get navProfile => 'Profile';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get searchProjects => 'Search project, code or region';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get notApplicable => 'Not applicable';

  @override
  String get next => 'NEXT';

  @override
  String get back => 'BACK';

  @override
  String get done => 'DONE';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get remove => 'Remove';

  @override
  String get skip => 'Skip';

  @override
  String get continueLabel => 'Continue';

  @override
  String get stepMediaType => 'Media Type';

  @override
  String get stepBoardDetails => 'Board Details';

  @override
  String get stepInstallationType => 'Installation Type';

  @override
  String get stepSiteQuestions => 'Site Questions';

  @override
  String get stepSitePhotos => 'Site Photos & Annotation';

  @override
  String get stepVoiceNotes => 'Voice & Text Notes';

  @override
  String get stepDrawing => '2D Drawing & 3D Preview';

  @override
  String get addMediaType => 'Add Media Type';

  @override
  String get otherMedia => '+ Other';

  @override
  String get otherInstallation => '+ Other';

  @override
  String get otherMediaTitle => 'Other Media Type';

  @override
  String get otherMediaHint => 'Enter media type or description';

  @override
  String get otherInstallationTitle => 'Other Installation Type';

  @override
  String get otherInstallationHint => 'Describe the installation method';

  @override
  String get recordVoice => 'Record voice';

  @override
  String get stopRecording => 'Stop recording';

  @override
  String get playRecording => 'Play';

  @override
  String get reRecord => 'Re-record';

  @override
  String get textOrVoiceRequired =>
      'Enter a description or record a voice note.';

  @override
  String get techSpecRequired => 'Technical Specification Required';

  @override
  String get removeMediaTitle => 'Remove media type?';

  @override
  String get removeMediaTooltip => 'Remove media type';

  @override
  String get installationMeasurements => 'Installation Measurements';

  @override
  String get installationSafety => 'Installation Safety';

  @override
  String get additionalSiteRemarks => 'Additional Site Remarks';

  @override
  String get commonSiteQuestions => 'Common Site Questions';

  @override
  String get mediaSpecificQuestions => 'Media-Specific Questions';

  @override
  String get installationSpecificQuestions => 'Installation-Specific Questions';

  @override
  String get gstLabel => 'GST No. (Optional)';

  @override
  String get siteDetailsSummary => 'Site Details Summary';

  @override
  String get placementOptional => 'Placement location (Optional)';

  @override
  String get boardNotesOptional => 'Notes for this board (Optional)';

  @override
  String get boardReady => 'Board ready for submission';

  @override
  String pendingItems(int count) {
    return '$count item(s) pending – tap to view';
  }

  @override
  String requiredPending(int count) {
    return '$count required pending';
  }

  @override
  String get capturePhotos => 'Capture at least two site photos';

  @override
  String get markSignage =>
      'Mark the proposed signage board in at least one photo';

  @override
  String get tourOpenPhoto =>
      'Open the photo to mark the proposed signage board.';

  @override
  String get tourOpen => 'Open';

  @override
  String get tourSignageTool => 'Tap Signage to mark the board area.';

  @override
  String get tourMarkArea =>
      'Mark the exact area where the signage board will be installed.';

  @override
  String get tourSave => 'Tap Save to keep the marking.';

  @override
  String get tourMarkRequired =>
      'A saved signage marking is required before you can continue.';

  @override
  String get reviewAndSubmit => 'REVIEW & SUBMIT';

  @override
  String get pdfPreview => 'Preview';

  @override
  String get pdfDownload => 'Download';

  @override
  String get reportSiteDetails => 'Site Details Summary';

  @override
  String get reportGst => 'GST No.';

  @override
  String get selectMediaFirst => 'Select a media type first.';
}
