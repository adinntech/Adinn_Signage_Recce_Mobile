/// Tamil wording of fixed UI strings (dialogs, buttons, tooltips, menus,
/// validation messages, photo angles). Display only: the English text stays
/// the value used by logic; anything unknown (user content, ids) is shown
/// unchanged. Technical terms (GSB, NLB, GST, AR, PDF, 2D, 3D) stay as is.
import 'ta_ui_extra.dart';

class TaUi {
  TaUi._();

  static const _m = <String, String>{
    // Buttons / dialogs
    'Cancel': 'ரத்து செய்',
    'Confirm': 'உறுதிசெய்',
    'Delete': 'நீக்கு',
    'Remove': 'நீக்கு',
    'Discard': 'விடு',
    'Keep editing': 'தொடர்ந்து திருத்து',
    'Apply to all': 'அனைத்திற்கும் பயன்படுத்து',
    'Map': 'இணை',
    'OK': 'சரி',
    'Retry': 'மீண்டும் முயற்சி',
    'Copy': 'நகலெடு',
    'Select': 'தேர்வு',
    'Save': 'சேமி',
    'Save as Draft': 'வரைவாகச் சேமி',
    'Continue': 'தொடரவும்',
    'Back': 'பின்னால்',
    'Discard unsaved changes?': 'சேமிக்காத மாற்றங்களை விடவா?',
    'Discard changes?': 'மாற்றங்களை விடவா?',
    'Your markings on this photo have not been saved.':
        'இந்தப் புகைப்படத்தில் நீங்கள் செய்த குறியீடுகள் சேமிக்கப்படவில்லை.',
    // Photo section
    'Camera': 'கேமரா',
    'Gallery': 'கேலரி',
    'Add sample photo (demo / no camera)':
        'மாதிரிப் புகைப்படம் சேர் (டெமோ / கேமரா இல்லை)',
    'Which angle is this photo?': 'இந்தப் புகைப்படம் எந்தக் கோணம்?',
    'Front view': 'முன்புறத் தோற்றம்',
    'Left angle': 'இடது கோணம்',
    'Right angle': 'வலது கோணம்',
    'Back view': 'பின்புறத் தோற்றம்',
    'Close-up': 'அருகிலிருந்து',
    'Long shot': 'தொலைவிலிருந்து',
    'Surroundings': 'சுற்றுப்புறம்',
    'View full screen': 'முழுத்திரையில் பார்',
    'Live Preview (3D on photo)': 'Live Preview (புகைப்படத்தில் 3D)',
    'Camera AR': 'Camera AR',
    'Before / Proposed comparison': 'முன் / முன்மொழிவு ஒப்பீடு',
    'Reviewer comments on this photo':
        'இந்தப் புகைப்படத்தின் மதிப்பாய்வாளர் கருத்துகள்',
    'Annotate / mark board': 'பலகையைக் குறிக்கவும்',
    'Change angle label': 'கோணப் பெயரை மாற்று',
    'Delete photo': 'புகைப்படத்தை நீக்கு',
    'Annotations saved': 'குறியீடுகள் சேமிக்கப்பட்டன',
    'Storage not available': 'சேமிப்பிடம் கிடைக்கவில்லை',
    'Tap a photo to annotate it, preview the 3D signage on it (Live Preview) or open Camera AR.':
        'புகைப்படத்தைத் தட்டிக் குறிக்கலாம்; Live Preview-இல் 3D பலகையைப் பார்க்கலாம்; அல்லது Camera AR திறக்கலாம்.',
    'No photos yet. Capture front, left and right angles.':
        'இன்னும் புகைப்படங்கள் இல்லை. முன், இடது, வலது கோணங்களை எடுக்கவும்.',
    // Tooltips
    'Save as Draft ': 'வரைவாகச் சேமி',
    '2D drawing': '2D வரைபடம்',
    '3D preview': '3D முன்னோட்டம்',
    '3D view': '3D பார்வை',
    'Fit to screen': 'திரைக்குப் பொருத்து',
    'Save PNG': 'PNG சேமி',
    'Undo': 'செயல்தவிர்',
    'Redo': 'மீண்டும் செய்',
    'Reset zoom': 'பெரிதாக்கத்தை மீட்டமை',
    'Export annotated photo': 'குறியிட்ட புகைப்படத்தை ஏற்றுமதி செய்',
    // Validation / pending messages
    'Select a media type': 'மீடியா வகையைத் தேர்ந்தெடுக்கவும்',
    'Select an installation type': 'பொருத்தும் வகையைத் தேர்ந்தெடுக்கவும்',
    'Enter board width and height': 'பலகையின் அகலம், உயரத்தை உள்ளிடவும்',
    'Capture at least two site photos':
        'குறைந்தது இரண்டு தளப் புகைப்படங்களை எடுக்கவும்',
    'Mark the proposed signage board in at least one photo':
        'குறைந்தது ஒரு புகைப்படத்தில் பலகை பொருத்தும் இடத்தைக் குறிக்கவும்',
    'Add at least one board': 'குறைந்தது ஒரு பலகையைச் சேர்க்கவும்',
    'Capture the shop GPS location': 'கடையின் GPS இடத்தைப் பதிவு செய்யவும்',
    'Shop contact number is missing': 'கடை தொடர்பு எண் இல்லை',
    'Shop address is missing': 'கடை முகவரி இல்லை',
    'Shop name is missing': 'கடை பெயர் இல்லை',
    'Board checklist': 'பலகை சரிபார்ப்புப் பட்டியல்',
    'Suggestions (not blocking)': 'பரிந்துரைகள் (தடையில்லை)',
    'Select media and installation type to load site questions.':
        'தளக் கேள்விகளைப் பெற மீடியா மற்றும் பொருத்தும் வகையைத் தேர்ந்தெடுக்கவும்.',
    'Enter value': 'மதிப்பை உள்ளிடவும்',
    'Not applicable': 'பொருந்தாது',
    'Read only': 'படிக்க மட்டும்',
    // Add media sheet
    'Select the media type': 'மீடியா வகையைத் தேர்ந்தெடுக்கவும்',
    'Select in editor': 'எடிட்டரில் தேர்ந்தெடு',
    'Board not found': 'பலகை கிடைக்கவில்லை',
    'Shop not found': 'கடை கிடைக்கவில்லை',

    // Dashboard (predefined UI only – counts/dates are parameters).
    'Good morning': 'காலை வணக்கம்',
    'Good afternoon': 'மதிய வணக்கம்',
    'Good evening': 'மாலை வணக்கம்',
    'Recce Vendor': 'தள ஆய்வு ஒப்பந்ததாரர்',
    'Search shops, owners, areas, projects':
        'கடைகள், உரிமையாளர்கள், பகுதிகள், திட்டங்களைத் தேடுக',
    'Assigned shops': 'ஒதுக்கப்பட்ட கடைகள்',
    'In progress': 'நடைபெறுகிறது',
    'In Progress': 'நடைபெறுகிறது',
    'Pending approval': 'ஒப்புதல் நிலுவையில்',
    'Pending Approval': 'ஒப்புதல் நிலுவையில்',
    'Approved': 'ஒப்புதல் பெற்றவை',
    'Rejected': 'நிராகரிக்கப்பட்டவை',
    'Projects': 'திட்டங்கள்',
    'Overall progress': 'மொத்த முன்னேற்றம்',
    'Submitted for approval': 'ஒப்புதலுக்குச் சமர்ப்பிக்கப்பட்டவை',
    'Final approved': 'இறுதி ஒப்புதல் பெற்றவை',
    'Awaiting you': 'உங்கள் காத்திருப்பில்',
    'Reviewed by you': 'நீங்கள் மதிப்பாய்வு செய்தவை',
    'Awaiting your approval': 'உங்கள் ஒப்புதலுக்காகக் காத்திருக்கிறது',
    'Needs rework': 'திருத்தம் தேவை',
    'View all': 'அனைத்தையும் காண்க',
    'No pending approvals': 'நிலுவையில் ஒப்புதல்கள் இல்லை',
    'No rejected recces – great work!':
        'நிராகரிக்கப்பட்ட ரெக்கிகள் இல்லை – சிறந்த வேலை!',
    'Continue where you left off': 'நீங்கள் விட்ட இடத்திலிருந்து தொடரவும்',
    'My tasks': 'என் பணிகள்',
    'Recent activity': 'சமீபத்திய செயல்பாடு',
    'Timeline': 'காலவரிசை',

    // Canonical summary/status codes (ProgressSummary.label).
    'No shops yet': 'இன்னும் கடைகள் இல்லை',
    'Completed': 'நிறைவடைந்தது',
    'Action required': 'நடவடிக்கை தேவை',
    'Not Started': 'தொடங்கவில்லை',
    'Not started': 'தொடங்கவில்லை',

    // Projects list / project details.
    'Pending': 'நிலுவையில்',
    'Shop status': 'கடைகளின் நிலை',
    'Total': 'மொத்தம்',
    'Client': 'வாடிக்கையாளர்',
    'Project code': 'திட்டக் குறியீடு',
    'Region': 'பகுதி',
    'Duration': 'கால அளவு',
    'Coordinator': 'ஒருங்கிணைப்பாளர்',
    'Call coordinator ({0})': 'ஒருங்கிணைப்பாளரை அழைக்கவும் ({0})',
    'Recce tasks': 'தள ஆய்வுப் பணிகள்',
    'Due': 'கடைசி நாள்',

    // Recce task details.
    'Low priority': 'குறைந்த முன்னுரிமை',
    'Medium priority': 'நடுத்தர முன்னுரிமை',
    'High priority': 'அதிக முன்னுரிமை',
    'Location': 'இடம்',
    'Due date': 'கடைசி தேதி',
    'Assigned to': 'பொறுப்பாளர்',
    'All': 'அனைத்தும்',
    'To do': 'செய்ய வேண்டியவை',
    'Submitted': 'சமர்ப்பிக்கப்பட்டவை',
    'Board': 'பலகை',
    'Boards': 'பலகைகள்',
    'Instructions': 'அறிவுறுத்தல்கள்',
    'Task not found': 'பணி கிடைக்கவில்லை',
    'No shops in this filter': 'இந்த வடிப்பில் கடைகள் இல்லை',
    'Tap "Add Shop" to start a recce for this location.':
        'இந்த இடத்தில் ரெக்கி தொடங்க "கடையைச் சேர்க்கவும்" என்பதைத் தட்டவும்.',

    // Parameterized templates – only the fixed wording is translated; the
    // inserted counts, dates and status codes keep their canonical values.
    '{0} shop(s) need field work': '{0} கடைகளில் களப்பணி தேவை',
    '{0} recce(s) awaiting your approval':
        '{0} ரெக்கி(கள்) உங்கள் ஒப்புதலுக்காகக் காத்திருக்கிறது',
    '{0}/{1} shops approved': '{1} கடைகளில் {0} கடைகளுக்கு ஒப்புதல்',
    '{0} task(s)': '{0} பணிகள்',
    'Ends {0}': 'முடிவு நாள்: {0}',
    'Due {0}': 'கடைசி நாள்: {0}',
    '1 shop: {0} submitted of {1} • {2}':
        '{1} கடையில் {0} கடைகள் சமர்ப்பிக்கப்பட்டுள்ளன • {2}',
    '{0} shops: {1} submitted • {2}':
        '{0} கடைகளில் {1} கடைகள் சமர்ப்பிக்கப்பட்டுள்ளன • {2}',
    'Overdue since {0}': 'கடைசி நாள் கடந்தது: {0}',
    'Due {0} ({1} day left)': 'கடைசி நாள்: {0} ({1} நாள் உள்ளது)',
    'Due {0} ({1} days left)': 'கடைசி நாள்: {0} ({1} நாட்கள் உள்ளன)',
    'All ({0})': 'அனைத்தும் ({0})',
    'To do ({0})': 'செய்ய வேண்டியவை ({0})',
    'Submitted ({0})': 'சமர்ப்பிக்கப்பட்டவை ({0})',
    'Approved ({0})': 'ஒப்புதல் பெற்றவை ({0})',
    'Rejected ({0})': 'நிராகரிக்கப்பட்டவை ({0})',
    'Add Shop': 'கடையைச் சேர்க்கவும்',
    '{0} board(s)': '{0} பலகை',
    'just now': 'இப்போதுதான்',
    '{0} min ago': '{0} நிமிடங்களுக்கு முன்',
    '{0} h ago': '{0} மணிநேரங்களுக்கு முன்',
    '{0} day ago': '{0} நாளுக்கு முன்',
    '{0} days ago': '{0} நாட்களுக்கு முன்',
    'Submissions': 'சமர்ப்பிப்புகள்',
    'Approvals': 'ஒப்புதல்கள்',
    'Rejections': 'நிராகரிப்புகள்',
    'Edits': 'திருத்தங்கள்',
    'Activity Timeline': 'செயல்பாட்டு வரலாறு',
    'Comment': 'கருத்து',
    'View': 'காண்க',
    'Next': 'அடுத்து',
    'Previous': 'முந்தையது',
    'Type a shop name, owner, area, city or project.':
        'கடை பெயர், உரிமையாளர், பகுதி, நகரம் அல்லது திட்டத்தை உள்ளிடவும்.',
    'No shops match "{0}"': '"{0}" உடன் பொருந்தும் கடைகள் இல்லை',
    'Submitted by {0}': '{0} சமர்ப்பித்தார்',
    'Capture GPS': 'GPS பதிவு செய்',
    'Recapture': 'மீண்டும் பதிவு செய்',
    'SETTINGS': 'அமைப்புகள்',
    'Changes since v{0}': 'பதிப்பு {0} முதல் மாற்றங்கள்',
    'Fix errors to save': 'சேமிக்க பிழைகளைச் சரிசெய்யவும்',
    'Save measurements': 'அளவீடுகளைச் சேமிக்கவும்',
    '{0} Approvals': '{0} ஒப்புதல்கள்',
    'Pending ({0})': 'நிலுவையில் ({0})',
    'Reviewed ({0})': 'மதிப்பாய்வு செய்தவை ({0})',
    'In approval': 'ஒப்புதலில்',
    'Submitted recces and their approval status show here.':
        'சமர்ப்பித்த ரெக்கிகளும் அவற்றின் ஒப்புதல் நிலையும் இங்கே காட்டப்படும்.',
    'Business Team': 'வணிகக் குழு',
    'Recce Operations': 'தள ஆய்வு செயல்பாடுகள்',
    'No recce is waiting for your approval.':
        'உங்கள் ஒப்புதலுக்காகக் காத்திருக்கும் ரெக்கி எதுவும் இல்லை.',
    'Vendor remarks': 'விற்பனையாளர் குறிப்புகள்',
    'Employee / Vendor ID': 'ஊழியர் / விற்பனையாளர் ID',
    'Mobile': 'கைப்பேசி',
    'All local projects, shops, photos, voice notes and history will be '
            'replaced with the original dummy data.':
        'இந்தச் சாதனத்தில் உள்ள திட்டங்கள், கடைகள், புகைப்படங்கள், குரல் பதிவுகள் '
        'மற்றும் வரலாறு அசல் மாதிரி தரவுகளால் மாற்றப்படும்.',
    '{0} version(s)': '{0} பதிப்புகள்',
    'current': 'தற்போது',
    'Name': 'பெயர்',
    'Owner': 'உரிமையாளர்',
    'Phone': 'தொலைபேசி',
    'Address': 'முகவரி',
    'Landmark': 'அடையாளம்',
    'Required': 'கட்டாயம்',
    'Captured': 'பதிவானது',
    'GPS location not captured.': 'GPS இடம் பதிவாகவில்லை.',
    'Stand at the shop front and capture the GPS location. '
            'It is required before submission.':
        'கடையின் முன்புறம் நின்று GPS இடத்தைப் பதிவு செய்யவும். சமர்ப்பிக்கும் முன் இது கட்டாயம்.',
    'Ready for Review': 'மதிப்பாய்வுக்குத் தயார்',
    'Needs Clarification': 'விளக்கம் தேவை',
    'Installation Constraint Identified':
        'பொருத்தும் கட்டுப்பாடு கண்டறியப்பட்டது',
    'Ready': 'தயார்',
    'Needs info': 'தகவல் தேவை',
    'Constraint': 'கட்டுப்பாடு',

    // Shop Details / signage requirements.
    'Site survey & documents': 'தள ஆய்வு மற்றும் ஆவணங்கள்',
    'Not generated yet': 'இன்னும் உருவாக்கப்படவில்லை',
    'No reviewer comments': 'மதிப்பாய்வுக் கருத்துகள் இல்லை',
    'Optional – none imported':
        'விருப்பத்திற்குரியது – எதுவும் இறக்குமதி செய்யப்படவில்லை',
    'Captured at': 'பதிவு செய்யப்பட்ட நேரம்',
    'No saved report': 'சேமித்த அறிக்கை இல்லை',
    'Report generated': 'அறிக்கை உருவாக்கப்பட்டது',
    'Panorama imported': 'பனோரமா இறக்குமதி ஆனது',
    'Panorama unavailable': 'பனோரமா கிடைக்கவில்லை',
    'Recce progress': 'தள ஆய்வு முன்னேற்றம்',
    '{0} of {1} signage unit(s) ready for review':
        '{1} பலகைகளில் {0} பலகைகள் மதிப்பாய்வுக்குத் தயார்',
    'Continue: {0} – {1}': 'தொடரவும்: {0} – {1}',
    'Signage requirements ({0})': 'விளம்பரப் பலகை தேவைகள் ({0})',
    'Mixed ({0})': 'கலப்பு ({0})',
    'Qty {0}': 'எண்ணிக்கை {0}',
    'Varied sizes': 'வெவ்வேறு அளவுகள்',
    'Same size': 'ஒரே அளவு',
    'Sized': 'அளவுகள் பதிவு செய்யப்பட்டன',
    '{0}/{1} sized': '{1}/{0} அளவுகள் பதிவு செய்யப்பட்டன',
    '{0} photos': '{0} புகைப்படங்கள்',
    '{0} photo': '{0} புகைப்படம்',
    '{0} pending': '{0} பணிகள் நிலுவையில்',
    '{0} previews': '{0} முன்னோட்டங்கள்',
    '{0} voice': '{0} குரல் பதிவு',
    '{0} to correct': '{0} திருத்த வேண்டியவை',
    '+{0} more': '+{0} மேலும்',
    'Complete': 'நிறைவடைந்தது',
    'Installation not set': 'பொருத்தும் முறை தேர்வு செய்யப்படவில்லை',
    'Media not set': 'பலகை வகை தேர்வு செய்யப்படவில்லை',
    'Size pending': 'அளவு நிலுவையில்',
    'Installation pending': 'பொருத்தும் முறை நிலுவையில்',
    'Review & SUBMIT': 'சரிபார்த்து சமர்ப்பிக்கவும்',
    'REVIEW & SUBMIT': 'சரிபார்த்து சமர்ப்பிக்கவும்',
    'REVIEW & RESUBMIT (v{0})': 'சரிபார்த்து மீண்டும் சமர்ப்பிக்கவும் (v{0})',
    '{0} report(s) • latest {1}': '{0} அறிக்கை(கள்) • சமீபத்தியது {1}',
    '{0} panorama(s)': '{0} பனோரமா(க்கள்)',
    '{0} open • {1} addressed • {2} verified':
        '{0} திறந்தவை • {1} சரிசெய்யப்பட்டவை • {2} சரிபார்க்கப்பட்டவை',

    // Media tabs / physical-board tabs.
    'Draft': 'வரைவு',
    'Board options': 'பலகை விருப்பங்கள்',
    'View individual units': 'தனிப்பட்ட பலகைகளைக் காண்க',
    'Project': 'திட்டம்',
    'Task': 'பணி',
    'Delete shop?': 'கடையை நீக்கவா?',
    'This removes {0} and all its boards, photos and notes from this device.':
        'இது {0} மற்றும் அதன் பலகைகள், புகைப்படங்கள், குறிப்புகளை இந்தச் சாதனத்திலிருந்து அகற்றும்.',
    'Recce not started': 'தள ஆய்வு தொடங்கவில்லை',
    'Add boards, capture photos and submit for approval.':
        'பலகைகளைச் சேர்த்து, புகைப்படங்கள் எடுத்து ஒப்புதலுக்குச் சமர்ப்பிக்கவும்.',
    'Draft in progress': 'வரைவு நடைபெறுகிறது',
    'Draft in progress (next: v{0})': 'வரைவு நடைபெறுகிறது (அடுத்தது: v{0})',
    'Complete all boards, then submit for Business approval.':
        'அனைத்து பலகைகளையும் முடித்து, வணிகக் குழு ஒப்புதலுக்குச் சமர்ப்பிக்கவும்.',
    'v{0} waiting for Business Team approval':
        'v{0} வணிகக் குழு ஒப்புதலுக்காகக் காத்திருக்கிறது',
    'Submitted {0}': '{0} சமர்ப்பிக்கப்பட்டது',
    'v{0} waiting for Recce Ops approval':
        'v{0} தள ஆய்வு செயல்பாட்டு ஒப்புதலுக்காகக் காத்திருக்கிறது',
    'Business Team approved. Final technical check pending.':
        'வணிகக் குழு ஒப்புதல் அளித்தது. இறுதி தொழில்நுட்ப சரிபார்ப்பு நிலுவையில்.',
    'v{0} final approved': 'v{0} இறுதி ஒப்புதல் பெற்றது',
    'Approved by Business Team and Recce Operations.':
        'வணிகக் குழு மற்றும் தள ஆய்வு செயல்பாட்டால் ஒப்புதல் அளிக்கப்பட்டது.',
    'v{0} rejected by {1}': 'v{0} {1} ஆல் நிராகரிக்கப்பட்டது',
    'reviewer': 'மதிப்பாய்வாளர்',
    'Fix the issues below and resubmit as v{0}.':
        'கீழே உள்ள குறைகளைச் சரிசெய்து v{0} ஆக மீண்டும் சமர்ப்பிக்கவும்.',
    'Photos': 'புகைப்படங்கள்',
    'Preview': 'முன்னோட்டம்',
    'Installation Measurements – {0}': 'பொருத்தும் அளவீடுகள் – {0}',
    '{0} required pending': '{0} கட்டாயப் பதிவுகள் நிலுவையில்',
    'Mixed': 'கலப்பு பொருத்தும் முறைகள்',
    'Add every media type needed at this shop – shop-name board, standees, '
            'glass branding… Each can have its own quantity.':
        'இந்தக் கடையில் தேவையான ஒவ்வொரு பலகை வகையையும் சேர்க்கவும் – கடைப் '
        'பெயர் பலகை, ஸ்டாண்டிகள், கண்ணாடி பிராண்டிங்… ஒவ்வொன்றிற்கும் தனி '
        'எண்ணிக்கை இருக்கலாம்.',
    'already added': 'ஏற்கனவே சேர்க்கப்பட்டது',

    // Media-group photo evidence (new shared-photo rule).
    '1 more valid site photo required':
        'செல்லுபடியாகும் தளப் புகைப்படம் ஒன்று மேலும் தேவை',
    'Signage marking is missing': 'விளம்பரப் பலகைக் குறியீடு இல்லை',
    '{0} signage marking is missing': '{0} பலகைக் குறியீடு இல்லை',
    'Photo evidence complete': 'புகைப்பட ஆதாரம் முழுமையானது',
    'Boards Marked': 'குறியிடப்பட்ட பலகைகள்',
    'Marking required': 'குறியீடு தேவை',
    'Marked': 'குறியிடப்பட்டது',
    'Line thickness': 'கோட்டின் தடிமன்',
    'Site survey': 'தள ஆய்வு',
    'All physical boards marked': 'அனைத்து பலகைகளும் குறியிடப்பட்டன',
    'Photos: {0} / {1} • Boards Marked: {2} / {3}':
        'புகைப்படங்கள்: {0} / {1} • குறியிடப்பட்ட பலகைகள்: {2} / {3}',
  };

  static final _answerQs = RegExp(r'^Answer (\d+) site questions?(.*)$');
  static final _detail = RegExp(r'^Complete (\d+) installation details?(.*)$');
  static final _photosFor = RegExp(
    r'^(Capture at least two site photos|Mark the proposed signage board in at least one photo)( for .+)$',
  );

  /// Tamil for [en] when known (also the generated pending messages).
  static String? tr(String en) {
    final d = _m[en] ?? taUiExtra[en];
    if (d != null) return d;
    final a = _answerQs.firstMatch(en);
    if (a != null) {
      return '${a.group(1)} தள ஆய்வுக் கேள்விகளுக்குப் பதில் அளிக்கவும்${a.group(2)}';
    }
    final i = _detail.firstMatch(en);
    if (i != null) {
      return '${i.group(1)} பொருத்தும் விவரங்களை நிறைவு செய்யவும்${i.group(2)}';
    }
    final p = _photosFor.firstMatch(en);
    if (p != null) {
      return '${_m[p.group(1)]}${p.group(2)}';
    }
    return null;
  }
}
