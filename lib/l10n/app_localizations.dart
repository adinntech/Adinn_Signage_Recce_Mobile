import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Adinn Recce'**
  String get appTitle;

  /// No description provided for @langSwitchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change language (English / Tamil)'**
  String get langSwitchTooltip;

  /// No description provided for @langBadge.
  ///
  /// In en, this message translates to:
  /// **'ENG'**
  String get langBadge;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get navProjects;

  /// No description provided for @navSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get navSubmitted;

  /// No description provided for @navApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get navApprovals;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @searchProjects.
  ///
  /// In en, this message translates to:
  /// **'Search project, code or region'**
  String get searchProjects;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @notApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not applicable'**
  String get notApplicable;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get done;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @stepMediaType.
  ///
  /// In en, this message translates to:
  /// **'Media Type'**
  String get stepMediaType;

  /// No description provided for @stepBoardDetails.
  ///
  /// In en, this message translates to:
  /// **'Board Details'**
  String get stepBoardDetails;

  /// No description provided for @stepInstallationType.
  ///
  /// In en, this message translates to:
  /// **'Installation Type'**
  String get stepInstallationType;

  /// No description provided for @stepSiteQuestions.
  ///
  /// In en, this message translates to:
  /// **'Site Questions'**
  String get stepSiteQuestions;

  /// No description provided for @stepSitePhotos.
  ///
  /// In en, this message translates to:
  /// **'Site Photos & Annotation'**
  String get stepSitePhotos;

  /// No description provided for @stepVoiceNotes.
  ///
  /// In en, this message translates to:
  /// **'Voice & Text Notes'**
  String get stepVoiceNotes;

  /// No description provided for @stepDrawing.
  ///
  /// In en, this message translates to:
  /// **'2D Drawing & 3D Preview'**
  String get stepDrawing;

  /// No description provided for @addMediaType.
  ///
  /// In en, this message translates to:
  /// **'Add Media Type'**
  String get addMediaType;

  /// No description provided for @otherMedia.
  ///
  /// In en, this message translates to:
  /// **'+ Other'**
  String get otherMedia;

  /// No description provided for @otherInstallation.
  ///
  /// In en, this message translates to:
  /// **'+ Other'**
  String get otherInstallation;

  /// No description provided for @otherMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Other Media Type'**
  String get otherMediaTitle;

  /// No description provided for @otherMediaHint.
  ///
  /// In en, this message translates to:
  /// **'Enter media type or description'**
  String get otherMediaHint;

  /// No description provided for @otherInstallationTitle.
  ///
  /// In en, this message translates to:
  /// **'Other Installation Type'**
  String get otherInstallationTitle;

  /// No description provided for @otherInstallationHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the installation method'**
  String get otherInstallationHint;

  /// No description provided for @recordVoice.
  ///
  /// In en, this message translates to:
  /// **'Record voice'**
  String get recordVoice;

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// No description provided for @playRecording.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playRecording;

  /// No description provided for @reRecord.
  ///
  /// In en, this message translates to:
  /// **'Re-record'**
  String get reRecord;

  /// No description provided for @textOrVoiceRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a description or record a voice note.'**
  String get textOrVoiceRequired;

  /// No description provided for @techSpecRequired.
  ///
  /// In en, this message translates to:
  /// **'Technical Specification Required'**
  String get techSpecRequired;

  /// No description provided for @removeMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove media type?'**
  String get removeMediaTitle;

  /// No description provided for @removeMediaTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove media type'**
  String get removeMediaTooltip;

  /// No description provided for @installationMeasurements.
  ///
  /// In en, this message translates to:
  /// **'Installation Measurements'**
  String get installationMeasurements;

  /// No description provided for @installationSafety.
  ///
  /// In en, this message translates to:
  /// **'Installation Safety'**
  String get installationSafety;

  /// No description provided for @additionalSiteRemarks.
  ///
  /// In en, this message translates to:
  /// **'Additional Site Remarks'**
  String get additionalSiteRemarks;

  /// No description provided for @commonSiteQuestions.
  ///
  /// In en, this message translates to:
  /// **'Common Site Questions'**
  String get commonSiteQuestions;

  /// No description provided for @mediaSpecificQuestions.
  ///
  /// In en, this message translates to:
  /// **'Media-Specific Questions'**
  String get mediaSpecificQuestions;

  /// No description provided for @installationSpecificQuestions.
  ///
  /// In en, this message translates to:
  /// **'Installation-Specific Questions'**
  String get installationSpecificQuestions;

  /// No description provided for @gstLabel.
  ///
  /// In en, this message translates to:
  /// **'GST No. (Optional)'**
  String get gstLabel;

  /// No description provided for @siteDetailsSummary.
  ///
  /// In en, this message translates to:
  /// **'Site Details Summary'**
  String get siteDetailsSummary;

  /// No description provided for @placementOptional.
  ///
  /// In en, this message translates to:
  /// **'Placement location (Optional)'**
  String get placementOptional;

  /// No description provided for @boardNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes for this board (Optional)'**
  String get boardNotesOptional;

  /// No description provided for @boardReady.
  ///
  /// In en, this message translates to:
  /// **'Board ready for submission'**
  String get boardReady;

  /// No description provided for @pendingItems.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) pending – tap to view'**
  String pendingItems(int count);

  /// No description provided for @requiredPending.
  ///
  /// In en, this message translates to:
  /// **'{count} required pending'**
  String requiredPending(int count);

  /// No description provided for @capturePhotos.
  ///
  /// In en, this message translates to:
  /// **'Capture at least two site photos'**
  String get capturePhotos;

  /// No description provided for @markSignage.
  ///
  /// In en, this message translates to:
  /// **'Mark the proposed signage board in at least one photo'**
  String get markSignage;

  /// No description provided for @tourOpenPhoto.
  ///
  /// In en, this message translates to:
  /// **'Open the photo to mark the proposed signage board.'**
  String get tourOpenPhoto;

  /// No description provided for @tourOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get tourOpen;

  /// No description provided for @tourSignageTool.
  ///
  /// In en, this message translates to:
  /// **'Tap Signage to mark the board area.'**
  String get tourSignageTool;

  /// No description provided for @tourMarkArea.
  ///
  /// In en, this message translates to:
  /// **'Mark the exact area where the signage board will be installed.'**
  String get tourMarkArea;

  /// No description provided for @tourSave.
  ///
  /// In en, this message translates to:
  /// **'Tap Save to keep the marking.'**
  String get tourSave;

  /// No description provided for @tourMarkRequired.
  ///
  /// In en, this message translates to:
  /// **'A saved signage marking is required before you can continue.'**
  String get tourMarkRequired;

  /// No description provided for @reviewAndSubmit.
  ///
  /// In en, this message translates to:
  /// **'REVIEW & SUBMIT'**
  String get reviewAndSubmit;

  /// No description provided for @pdfPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get pdfPreview;

  /// No description provided for @pdfDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get pdfDownload;

  /// No description provided for @reportSiteDetails.
  ///
  /// In en, this message translates to:
  /// **'Site Details Summary'**
  String get reportSiteDetails;

  /// No description provided for @reportGst.
  ///
  /// In en, this message translates to:
  /// **'GST No.'**
  String get reportGst;

  /// No description provided for @selectMediaFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a media type first.'**
  String get selectMediaFirst;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
