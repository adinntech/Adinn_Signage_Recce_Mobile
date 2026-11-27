import 'package:flutter/widgets.dart';

import '../data/models/enums.dart';
import '../data/models/models.dart';
import 'app_localizations.dart';
import 'app_localizations_en.dart';
import 'ta_catalog.dart';
import 'ta_display.dart';
import 'ta_ui.dart';

export 'app_localizations.dart';

/// `context.t.save` - the localized strings of the current locale. Falls
/// back to English when a screen is hosted without the app's localization
/// delegates (for example in isolated widget tests).
extension AppStringsX on BuildContext {
  AppLocalizations get t =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();

  bool get isTamil => Localizations.localeOf(this).languageCode == 'ta';

  /// Display text of a catalog item (question, answer option, media or
  /// installation name). The English text stays the stored / matched value;
  /// unknown text (custom names, user content) is shown unchanged.
  String tq(String en) {
    if (!isTamil) return en;
    return TaDisplay.media[en] ??
        TaDisplay.installations[en] ??
        TaDisplay.installationDescriptions[en] ??
        TaCatalog.questions[en] ??
        TaCatalog.options[en] ??
        TaCatalog.media[en] ??
        TaCatalog.installations[en] ??
        en;
  }

  /// Display text of a fixed UI string (button, dialog, tooltip, message).
  /// Unknown text (user content) is returned unchanged.
  String ui(String en) => isTamil ? (TaUi.tr(en) ?? tq(en)) : en;

  /// Localized template with positional `{0}`, `{1}` parameters. Only the
  /// fixed template is translated; the arguments (user content, ids,
  /// numbers) are inserted unchanged.
  /// Single-pass substitution: an inserted user value containing literal
  /// `{0}` / `{1}` is never re-scanned as another placeholder.
  String uf(String template, List<Object?> args) =>
      ui(template).replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final i = int.tryParse(m.group(1) ?? '');
        return i != null && i >= 0 && i < args.length
            ? '${args[i]}'
            : m.group(0)!;
      });

  // ---------------------------------------------------------------------
  // Fixed UI presentation helpers.
  //
  // These map *canonical* values (enums, summary codes, message templates)
  // to localized presentation text. The stored/business value is never
  // changed and user-generated content is never passed through here.
  // ---------------------------------------------------------------------

  static const _enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Tamil month names live in one place only – never hardcoded per screen.
  static const _taMonths = [
    'ஜனவரி',
    'பிப்ரவரி',
    'மார்ச்',
    'ஏப்ரல்',
    'மே',
    'ஜூன்',
    'ஜூலை',
    'ஆகஸ்ட்',
    'செப்டம்பர்',
    'அக்டோபர்',
    'நவம்பர்',
    'டிசம்பர்',
  ];

  static const _pluralStatus = <String, String>{
    'Approved': 'ஒப்புதல் பெற்றவை',
    'Rejected': 'நிராகரிக்கப்பட்டவை',
    'In progress': 'நடைபெறுகிறது',
    'In Progress': 'நடைபெறுகிறது',
    'Pending approval': 'ஒப்புதல் நிலுவையில்',
    'Pending Approval': 'ஒப்புதல் நிலுவையில்',
    'Pending': 'நிலுவையில்',
    'Not started': 'தொடங்கவில்லை',
    'Not Started': 'தொடங்கவில்லை',
    'Completed': 'நிறைவடைந்தது',
    'Action required': 'நடவடிக்கை தேவை',
    'Assigned shops': 'ஒதுக்கப்பட்ட கடைகள்',
    'Projects': 'திட்டங்கள்',
    'Submitted': 'சமர்ப்பிக்கப்பட்டவை',
    'To do': 'செய்ய வேண்டியவை',
    'All': 'அனைத்தும்',
    'No shops yet': 'இன்னும் கடைகள் இல்லை',
  };

  /// Locale-aware relative time: "just now", "5 min ago", ... .
  /// The instant is untouched; only the wording changes.
  String fmtRelativeL(DateTime d, [DateTime? now]) {
    if (!isTamil) {
      final n = now ?? DateTime.now();
      final diff = n.difference(d);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} h ago';
      if (diff.inDays < 7) {
        return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      }
      return '${d.toLocal().day} ${_enMonths[d.toLocal().month - 1]} ${d.toLocal().year}';
    }
    final n = now ?? DateTime.now();
    final diff = n.difference(d);
    if (diff.inSeconds < 60) return ui('just now');
    if (diff.inMinutes < 60) return uf('{0} min ago', [diff.inMinutes]);
    if (diff.inHours < 24) return uf('{0} h ago', [diff.inHours]);
    if (diff.inDays < 7) {
      return uf(diff.inDays == 1 ? '{0} day ago' : '{0} days ago', [
        diff.inDays,
      ]);
    }
    return fmtDateL(d);
  }

  /// Locale-aware date: `27 Nov 2026` / `27 நவம்பர் 2026`.
  /// The timestamp itself is untouched; only the presentation changes.
  String fmtDateL(DateTime d) {
    final l = d.toLocal();
    final month = isTamil ? _taMonths[l.month - 1] : _enMonths[l.month - 1];
    return '${l.day} $month ${l.year}';
  }

  /// Presentation label of a canonical [RecceStatus]. The enum value, its
  /// colour, filtering and progress math are unaffected.
  String statusLabel(RecceStatus s) {
    if (!isTamil) return s.label;
    return switch (s) {
      RecceStatus.notStarted => 'தொடங்கவில்லை',
      RecceStatus.inProgress => 'நடைபெறுகிறது',
      RecceStatus.pendingBusiness => 'வணிக ஒப்புதல் நிலுவையில்',
      RecceStatus.pendingOps => 'செயல்பாட்டு ஒப்புதல் நிலுவையில்',
      RecceStatus.approved => 'ஒப்புதல் பெற்றது',
      RecceStatus.rejectedBusiness => 'வணிகத்தால் நிராகரிக்கப்பட்டது',
      RecceStatus.rejectedOps => 'செயல்பாட்டால் நிராகரிக்கப்பட்டது',
    };
  }

  /// Compact presentation label of a canonical [RecceStatus].
  String statusShortLabel(RecceStatus s) {
    if (!isTamil) return s.shortLabel;
    return switch (s) {
      RecceStatus.notStarted => 'தொடங்கவில்லை',
      RecceStatus.inProgress => 'நடைபெறுகிறது',
      RecceStatus.pendingBusiness => 'வணிகத்திடம்',
      RecceStatus.pendingOps => 'செயல்பாட்டுத் துறையிடம்',
      RecceStatus.approved => 'ஒப்புதல் பெற்றது',
      RecceStatus.rejectedBusiness => 'நிராகரிக்கப்பட்டது',
      RecceStatus.rejectedOps => 'நிராகரிக்கப்பட்டது',
    };
  }

  /// Aggregate / count wording (dashboard cards, count chips, filter chips).
  /// Unknown values fall back unchanged – never mislabelled as Approved.
  String statusPlural(String en) => isTamil ? (_pluralStatus[en] ?? en) : en;

  /// Singular wording for a project card status badge.
  String statusSingular(String en) {
    if (!isTamil) return en;
    return switch (en) {
      'Approved' => 'ஒப்புதல் பெற்றது',
      'Rejected' => 'நிராகரிக்கப்பட்டது',
      _ => _pluralStatus[en] ?? en,
    };
  }

  // Dynamic messages: only the template is translated; arguments (counts,
  // dates and user content) are inserted unchanged.
  String shopsNeedFieldWork(int n) => uf('{0} shop(s) need field work', [n]);

  String reccesAwaitApproval(int n) =>
      uf('{0} recce(s) awaiting your approval', [n]);

  String shopsApproved(int approved, int total) =>
      uf('{0}/{1} shops approved', [approved, total]);

  String taskCount(int n) =>
      isTamil ? uf('{0} task(s)', [n]) : '$n task${n == 1 ? '' : 's'}';

  String shopCount(int n) => isTamil
      ? (n == 1 ? '$n கடை' : '$n கடைகள்')
      : '$n shop${n == 1 ? '' : 's'}';

  String boardCount(int n) => isTamil
      ? (n == 1 ? '$n பலகை' : '$n பலகைகள்')
      : '$n board${n == 1 ? '' : 's'}';

  /// `Ends 4 Jan 2027` / `முடிவு நாள்: 4 ஜனவரி 2027`.
  String endsOn(DateTime d) => uf('Ends {0}', [fmtDateL(d)]);

  /// `Due 9 Dec 2026` / `கடைசி நாள்: 9 டிசம்பர் 2026`.
  String dueOn(DateTime d) => uf('Due {0}', [fmtDateL(d)]);

  String dateRange(DateTime a, DateTime b) => '${fmtDateL(a)} – ${fmtDateL(b)}';

  /// `0/1 shops submitted • In Progress` /
  /// `1 கடையில் 0 கடைகள் சமர்ப்பிக்கப்பட்டுள்ளன • நடைபெறுகிறது`.
  String shopsSubmittedSummary(int submitted, int total, String status) {
    final st = statusPlural(status);
    if (!isTamil) return '$submitted/$total shops submitted • $st';
    if (total == 1) {
      return uf('1 shop: {0} submitted of {1} • {2}', [submitted, total, st]);
    }
    return uf('{0} shops: {1} submitted • {2}', [total, submitted, st]);
  }

  /// `1 shops • In Progress` / `1 கடை • நடைபெறுகிறது`.
  String shopsWithStatus(int total, String status) =>
      '$shopCount(total) • ${statusPlural(status)}';

  String priorityLabel(String priority) {
    if (!isTamil) return priority;
    return switch (priority) {
      'Low' => 'குறைந்த முன்னுரிமை',
      'Medium' => 'நடுத்தர முன்னுரிமை',
      'High' => 'அதிக முன்னுரிமை',
      _ => priority,
    };
  }

  String priorityBadge(String priority) =>
      isTamil ? priorityLabel(priority) : '$priority priority';

  // ---------------------------------------------------------------------
  // Verified predefined display data. Every override is id-guarded and only
  // applied while the stored value still equals the verified original, so a
  // user-edited record is never relabelled.
  // ---------------------------------------------------------------------

  /// Display name of a verified predefined project.
  String projectName(String id, String storedName) {
    if (!isTamil) return storedName;
    final d = TaDisplay.projects[id];
    return d != null && storedName == d.name ? d.nameTa : storedName;
  }

  /// Display description of a verified predefined project.
  String projectDescription(String id, String storedDescription) {
    if (!isTamil) return storedDescription;
    final d = TaDisplay.projects[id];
    return d != null && storedDescription == d.description
        ? d.descriptionTa
        : storedDescription;
  }

  /// Predefined region label; arbitrary addresses are returned unchanged.
  String regionLabel(String region) =>
      isTamil ? (TaDisplay.regions[region] ?? region) : region;

  /// Verified predefined location component; arbitrary text is unchanged.
  String locationLabel(String value) => isTamil
      ? (TaDisplay.locations[value] ?? TaDisplay.regions[value] ?? value)
      : value;

  /// Verified predefined shop display data. A single edited field disables
  /// the whole alias set, so a customised record is never relabelled.
  ShopDisplay? _verifiedShop(Shop s) {
    if (!isTamil) return null;
    final d = TaDisplay.shops[s.id];
    if (d == null ||
        !d.matches(
          currentName: s.name,
          currentAddress: s.address,
          currentArea: s.area,
          currentCity: s.city,
          currentPincode: s.pincode,
          currentOwner: s.ownerName,
        )) {
      return null;
    }
    return d;
  }

  String shopName(Shop s) => _verifiedShop(s)?.nameTa ?? s.name;
  String shopAddress(Shop s) => _verifiedShop(s)?.addressTa ?? s.address;
  String shopArea(Shop s) => _verifiedShop(s)?.areaTa ?? s.area;
  String shopCity(Shop s) => _verifiedShop(s)?.cityTa ?? s.city;
  String shopOwner(Shop s) => _verifiedShop(s)?.ownerNameTa ?? s.ownerName;
  String shopFullAddress(Shop s) =>
      _verifiedShop(s)?.fullAddressTa ?? s.fullAddress;

  /// Verified predefined task title; custom titles stay untouched.
  String taskTitle(RecceTask task) {
    if (!isTamil) return task.title;
    final d = TaDisplay.tasks[task.id];
    return d != null && d.title == task.title ? d.titleTa : task.title;
  }

  /// Verified predefined person name (initials/numerals are preserved).
  String personName(String name) =>
      isTamil ? (TaDisplay.people[name] ?? name) : name;

  /// Canonical media display label (tabs, cards, generated names).
  String mediaLabel(String label) =>
      isTamil ? (TaDisplay.media[label] ?? tq(label)) : label;

  /// Canonical installation name.
  String installationLabel(String name) =>
      isTamil ? (TaDisplay.installations[name] ?? tq(name)) : name;

  /// Predefined installation description; custom text is unchanged.
  String installationDescription(String text) =>
      isTamil ? (TaDisplay.installationDescriptions[text] ?? tq(text)) : text;

  /// Translate ONLY an app-generated "<media> NN" board name. Callers must
  /// verify provenance (SignageCatalog.isAutoBoardName) before using this.
  String generatedBoardName(String name) {
    if (!isTamil) return name;
    final m = RegExp(r'^(.+) (\d{2})$').firstMatch(name.trim());
    if (m == null) return name;
    final prefix = TaDisplay.generatedNamePrefixes[m.group(1)!];
    return prefix == null ? name : '$prefix ${m.group(2)}';
  }

  /// `{count} pending` / `{n} photos` / `{c}/{t} sized` with correct grammar.
  String countLabel(int n, String enSingular, String enPlural, String taWord) =>
      isTamil ? '$n $taWord' : '$n ${n == 1 ? enSingular : enPlural}';

  /// Media groups vs physical boards (they are different counts).
  String mediaBoardSummary(int mediaTypes, int boards) {
    if (!isTamil) {
      return '$mediaTypes media type${mediaTypes == 1 ? '' : 's'} • '
          '$boards signage unit${boards == 1 ? '' : 's'}';
    }
    return '$mediaTypes ${mediaTypes == 1 ? 'பலகை வகை' : 'பலகை வகைகள்'} · '
        '${boardCount(boards)}';
  }

  String readyUnitsSummary(int ready, int total) =>
      uf('{0} of {1} signage unit(s) ready for review', [ready, total]);

  String continueAction(String boardName, String nextAction) =>
      uf('Continue: {0} – {1}', [boardName, nextAction]);

  /// Section headings of the unified Site Questions form.
  String tSection(String en) {
    final s = t;
    return switch (en) {
      'Common Site Questions' => s.commonSiteQuestions,
      'Media-Specific Questions' => s.mediaSpecificQuestions,
      'Installation-Specific Questions' => s.installationSpecificQuestions,
      'Additional Site Remarks' => s.additionalSiteRemarks,
      'Installation Safety' => s.installationSafety,
      _ => en,
    };
  }
}
