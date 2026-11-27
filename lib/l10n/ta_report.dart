import 'ta_catalog.dart';

/// Tamil wording of the PDF report's fixed vocabulary (headings, labels,
/// header / footer, status). Pure Dart (usable inside the PDF isolate).
///
/// Only DISPLAY wording is translated. Anything not listed here (shop
/// names, board names, custom descriptions, remarks, free text, measured
/// values) returns null and is printed exactly as entered.
class TamilReport {
  TamilReport._();

  static const _vocab = <String, String>{
    // Headings / sections
    'Shop overview': 'கடை கண்ணோட்டம்',
    'Review information': 'மதிப்பாய்வு தகவல்',
    'Site Details Summary': 'தள விவரச் சுருக்கம்',
    'Open issues': 'தீர்வு காணாத சிக்கல்கள்',
    'Installation measurements': 'பொருத்தும் அளவீடுகள்',
    'Obstructions': 'தடைகள்',
    'Board placement markers': 'பலகை வைக்கும் இட குறியீடுகள்',
    'Outstanding review comments': 'நிலுவையில் உள்ள மதிப்பாய்வு கருத்துகள்',
    // Key labels
    'Project': 'திட்டம்',
    'Task': 'பணி',
    'Brand': 'பிராண்ட்',
    'Shop': 'கடை',
    'Shop address': 'கடை முகவரி',
    'Landmark': 'அடையாளம்',
    'GPS': 'GPS',
    'Recce person': 'ரெக்கி செய்பவர்',
    'Visit date': 'வருகை தேதி',
    'Report generated': 'அறிக்கை உருவாக்கியது',
    'Approval status': 'ஒப்புதல் நிலை',
    'Submission version': 'சமர்ப்பிப்பு பதிப்பு',
    'Report content from': 'அறிக்கை உள்ளடக்கம்',
    'Total media groups': 'மொத்த மீடியா குழுக்கள்',
    'Total signage units': 'மொத்த பலகைகள்',
    'Media group ID': 'மீடியா குழு அடையாளம்',
    'Media type': 'மீடியா வகை',
    'Installation (group)': 'பொருத்தும் வகை (குழு)',
    'Installation type': 'பொருத்தும் வகை',
    'Quantity': 'எண்ணிக்கை',
    'Unit number': 'பலகை எண்',
    'Width': 'அகலம்',
    'Height': 'உயரம்',
    'Specification': 'விவரக்குறிப்பு',
    'Placement': 'வைக்கும் இடம்',
    'Site feasibility': 'தள சாத்தியக்கூறு',
    'GST No.': 'GST எண்',
    'Additional site remarks': 'கூடுதல் தளக் குறிப்புகள்',
    'Group notes': 'குழு குறிப்புகள்',
    'Media summary': 'மீடியா சுருக்கம்',
    'Media types': 'மீடியா வகைகள்',
    'Overall recce completion': 'ஒட்டுமொத்த ரெக்கி நிறைவு',
    'Open recce issues': 'தீர்வு காணாத ரெக்கி சிக்கல்கள்',
    'Site feasibility summary': 'தள சாத்தியக்கூறு சுருக்கம்',
    'Quantity context': 'எண்ணிக்கைச் சூழல்',
    'Ground clearance (bottom height)': 'தரை இடைவெளி (கீழ் உயரம்)',
    'Top height from ground': 'தரையிலிருந்து மேல் உயரம்',
    'Question': 'கேள்வி',
    'Response': 'பதில்',
    'Remarks': 'குறிப்புகள்',
    'Signage unit': 'பலகை',
    'Indicator': 'குறியீடு',
    'Reason': 'காரணம்',
    'Requires Review': 'மறுஆய்வு தேவை',
    'No Known Obstruction': 'அறியப்பட்ட தடை இல்லை',
    'Blocked / Needs Site Revision': 'தடை / தளத் திருத்தம் தேவை',
    // Values / status
    'Same size': 'ஒரே அளவு',
    'Different sizes': 'வெவ்வேறு அளவுகள்',
    'Yes': 'ஆம்',
    'No': 'இல்லை',
    'DRAFT': 'வரைவு',
    'APPROVED': 'ஒப்புதல்',
    'DRAFT - NOT APPROVED FOR FABRICATION':
        'வரைவு - தயாரிப்புக்கு ஒப்புதல் இல்லை',
    'ADINN SIGNAGE - SITE RECCE REPORT': 'அடின் சைனேஜ் - தள ரெக்கி அறிக்கை',
    'ADINN SIGNAGE – SITE RECCE REPORT': 'அடின் சைனேஜ் – தள ரெக்கி அறிக்கை',
    'DRAFT – NOT APPROVED FOR FABRICATION':
        'வரைவு – தயாரிப்புக்கு ஒப்புதல் அளிக்கப்படவில்லை',
    'Illustrative parametric model and schematic drawings from recorded measurements - not fabrication-certified.':
        'பதிவு செய்த அளவுகளிலிருந்து உருவாக்கிய விளக்கப் படங்கள் - தயாரிப்புச் சான்றிதழ் அல்ல.',
    'Page': 'பக்கம்',
    'Draft - not approved for fabrication.':
        'வரைவு - தயாரிப்புக்கு ஒப்புதல் இல்லை.',
    // Remaining report captions / table headers.
    'Site feasibility by signage unit (operational indicator only)':
        'பலகை வாரியாக தள சாத்தியக்கூறு (செயல்பாட்டுக் குறியீடு மட்டும்)',
    'Group': 'குழு',
    'Dimension': 'அளவு',
    'Measurement': 'அளவீடு',
    'Value': 'மதிப்பு',
    'Source': 'மூலம்',
    'Ground clearance / pole position diagram (not to exact scale)':
        'தரை இடைவெளி / கம்ப நிலை வரைபடம் (சரியான அளவில் இல்லை)',
    'Electrical information (as recorded - not a safety certificate)':
        'மின்சாரத் தகவல் (பதிவு செய்தபடி - பாதுகாப்புச் சான்று அல்ல)',
    'Photo': 'புகைப்படம்',
    'Marker': 'குறி',
    'Notes': 'குறிப்புகள்',
    'Installation details': 'பொருத்தும் விவரங்கள்',
    'Current submission version': 'தற்போதைய சமர்ப்பிப்பு பதிப்பு',
    'Submitted': 'சமர்ப்பிக்கப்பட்டது',
    'Business review': 'வணிக மதிப்பாய்வு',
    'Operations review': 'செயல்பாட்டு மதிப்பாய்வு',
    'Vendor remarks': 'விற்பனையாளர் குறிப்புகள்',
    'Version': 'பதிப்பு',
    'Type': 'வகை',
    'Comment': 'கருத்து',
    'Status': 'நிலை',
    'Reviewer': 'மதிப்பாய்வாளர்',
    'Image not available on this device':
        'இந்தச் சாதனத்தில் படம் கிடைக்கவில்லை',
    'No outstanding review comments.':
        'நிலுவையில் உள்ள மதிப்பாய்வுக் கருத்துகள் இல்லை.',
    'Not Assessed': 'மதிப்பீடு செய்யப்படவில்லை',
    'Ground level': 'தரை நிலை',
    'Not Started': 'தொடங்கவில்லை',
    'In Progress': 'நடைபெறுகிறது',
    'Completed': 'நிறைவடைந்தது',
    'Rejected': 'நிராகரிக்கப்பட்டது',
    'Pending Approval': 'ஒப்புதல் நிலுவையில் உள்ளது',
    'Open': 'திறந்தது',
    'Addressed': 'தீர்க்கப்பட்டது',
    'Verified': 'சரிபார்க்கப்பட்டது',
    'Draft': 'வரைவு',
    'High': 'அதிகம்',
    'Medium': 'நடுத்தரம்',
    'Low': 'குறைவு',
    'ADINN SIGNAGE': 'அடின் சைனேஜ்',
    '2D front elevation': '2D முன்புறத் தோற்றம்',
    '2D side elevation': '2D பக்கத் தோற்றம்',
    '3D opposite-side view': '3D எதிர்ப்பக்கத் தோற்றம்',
    '3D model - Illustrative Model': '3D மாதிரி - விளக்க மாதிரி',
  };

  static const _status = <String, String>{
    'Not Started': 'தொடங்கவில்லை',
    'In Progress': 'நடைபெறுகிறது',
    'Approved': 'ஒப்புதல்',
  };

  /// Fixed status/severity values that are safe to translate in table cells.
  static const fixedStatuses = <String>{
    'Not Started',
    'In Progress',
    'Completed',
    'Approved',
    'Rejected',
    'Pending Approval',
    'Requires Review',
    'Not Assessed',
    'Submitted',
    'Open',
    'Addressed',
    'Verified',
    'Draft',
    'High',
    'Medium',
    'Low',
  };

  static bool isFixedStatus(String value) =>
      fixedStatuses.contains(value.trim());

  /// Tamil wording for [en], or null when it must stay as written.
  static String? tr(String en) {
    final t = en.trim();
    final direct =
        _vocab[t] ??
        _vocab[t.toUpperCase()] ??
        TaCatalog.questions[t] ??
        TaCatalog.options[t] ??
        TaCatalog.media[t] ??
        TaCatalog.installations[t];
    if (direct != null) return direct;
    final grp = RegExp(
      r'^Media group: (.+) - (.+) \(qty (\d+)\)$',
    ).firstMatch(t);
    if (grp != null) {
      final media = TaCatalog.media[grp.group(2)!] ?? grp.group(2)!;
      return 'மீடியா குழு: ${grp.group(1)} - $media '
          '(எண்ணிக்கை ${grp.group(3)})';
    }
    final sheet = RegExp(r'^MEASUREMENT SHEET - (.+)$').firstMatch(t);
    if (sheet != null) {
      return 'அளவீட்டுத் தாள் - ${sheet.group(1)}';
    }
    final cur = RegExp(r'^Current status: (.+)$').firstMatch(t);
    if (cur != null) {
      return 'தற்போதைய நிலை: ${_status[cur.group(1)] ?? cur.group(1)}';
    }
    final pics = RegExp(r'^Photos and drawings - (.+)$').firstMatch(t);
    if (pics != null) {
      return 'புகைப்படங்கள் மற்றும் வரைபடங்கள் - ${pics.group(1)}';
    }
    // Photo captions (data inside is user-entered and stays as written).
    final orig = RegExp(r'^Original site photo [–-] (.+)$').firstMatch(t);
    if (orig != null) return 'அசல் தளப் புகைப்படம் – ${orig.group(1)}';
    final ann = RegExp(r'^Annotated site photo [–-] (.+)$').firstMatch(t);
    if (ann != null) return 'குறியிடப்பட்ட தளப் புகைப்படம் – ${ann.group(1)}';
    final annShort = RegExp(r'^Annotated [–-] (.+)$').firstMatch(t);
    if (annShort != null) return 'குறியிடப்பட்டது – ${annShort.group(1)}';
    if (t == 'whole media group') return 'முழு மீடியா குழு';
    if (t == 'electrical mapping') return 'மின்சார வரைபடம்';
    // Report footer / drawing dimension labels.
    final gen = RegExp(
      r'^Generated (.+) - Adinn Signage Recce \(offline\)\. ?(.*)$',
    ).firstMatch(t);
    if (gen != null) {
      final tail = gen.group(2)!.isEmpty
          ? ''
          : ' ${_vocab[gen.group(2)!.trim()] ?? gen.group(2)!}';
      return 'உருவாக்கப்பட்டது ${gen.group(1)} - அடின் சைனேஜ் ரெக்கி '
          '(ஆஃப்லைன்).$tail';
    }
    final dim = RegExp(
      r'^(W|H|Bottom|Top|Pole spacing|Embedment|Available wall|Overall) (.+)$',
    ).firstMatch(t);
    if (dim != null) {
      const names = {
        'W': 'அகலம்',
        'H': 'உயரம்',
        'Bottom': 'கீழ்',
        'Top': 'மேல்',
        'Pole spacing': 'கம்ப இடைவெளி',
        'Embedment': 'அடித்தள ஆழம்',
        'Available wall': 'கிடைக்கும் சுவர்',
        'Overall': 'மொத்தம்',
      };
      return '${names[dim.group(1)]} ${dim.group(2)}';
    }
    final clear = RegExp(r'^Clearances: (.+)$').firstMatch(t);
    if (clear != null) return 'இடைவெளிகள்: ${clear.group(1)}';
    final checklist = RegExp(r'^Site checklist - (.+)$').firstMatch(t);
    if (checklist != null)
      return 'தள சரிபார்ப்புப் பட்டியல் - ${checklist.group(1)}';
    final rej = RegExp(r'^Rejected v(.+) by (.+) (.+)$').firstMatch(t);
    if (rej != null)
      return 'v${rej.group(1)} ${rej.group(3)} ஆல் நிராகரிக்கப்பட்டது';
    final reasons = RegExp(r'^Reasons: (.+)$').firstMatch(t);
    if (reasons != null) return 'காரணங்கள்: ${reasons.group(1)}';
    final remarksFull = RegExp(r'^Remarks \(full\) - (.+)$').firstMatch(t);
    if (remarksFull != null)
      return 'குறிப்புகள் (முழு) - ${remarksFull.group(1)}';
    final marked = RegExp(r'^Marked on photos: (.+)$').firstMatch(t);
    if (marked != null)
      return 'புகைப்படங்களில் குறிக்கப்பட்டவை: ${marked.group(1)}';
    final perspective = RegExp(
      r'^Perspective placement drawn on: (.+)$',
    ).firstMatch(t);
    if (perspective != null) {
      return 'கோணப் பலகை இடம் வரையப்பட்டது: ${perspective.group(1)}';
    }
    return null;
  }
}
