// Verified Tamil *display* variants for predefined application data.
// Display only: stored ids, codes, names, descriptions and backend values are
// NEVER changed. Custom / user-edited records fall back to their original text.
//
// This is deliberately small and explicit: adding an entry requires a verified
// predefined record or an approved catalog label. It is consulted through the
// single AppStringsX entry point in l10n.dart (no competing localization system).

class TaDisplay {
  TaDisplay._();

  /// Verified predefined projects: id -> (stored name, Tamil display name,
  /// stored description, Tamil display description).
  static const projects = <String, ProjectDisplay>{
    'p_asian': ProjectDisplay(
      name: 'Asian Paints',
      nameTa: 'ஏசியன் பெயிண்ட்ஸ்',
      description:
          'Dealer signage branding drive – GSB, NLB and wall branding for '
          'paint dealers across central Tamil Nadu.',
      descriptionTa:
          'மத்திய தமிழ்நாட்டில் உள்ள பெயிண்ட் விற்பனையாளர்களுக்கான GSB, NLB '
          'மற்றும் சுவர் விளம்பரப் பலகை பிராண்டிங் திட்டம்.',
    ),
    'p_ramco': ProjectDisplay(
      name: 'Ramco Cements',
      nameTa: 'ராம்கோ சிமெண்ட்ஸ்',
      description: 'Dealer board replacement with ACP and rooftop GSB units.',
      descriptionTa:
          'விற்பனையாளர் பலகைகளை ACP மற்றும் மாடியில் பொருத்தப்படும் GSB '
          'பலகைகளுடன் மாற்றும் திட்டம்.',
    ),
    'p_sakthi': ProjectDisplay(
      name: 'Sakthi Masala',
      nameTa: 'சக்தி மசாலா',
      description: 'Retail visibility – flange boards and shutter vinyl.',
      descriptionTa:
          'கடைகளின் விளம்பரத் தெரிவுநிலையை மேம்படுத்த ஃபிளாஞ்ச் பலகைகள் '
          'மற்றும் ஷட்டர் வினைல் பொருத்தும் திட்டம்.',
    ),
  };

  /// Verified predefined shop records. An alias applies ONLY while every
  /// verified stored field still matches – a user edit disables all aliases.
  static const shops = <String, ShopDisplay>{
    's_erode_prov': ShopDisplay(
      name: 'Erode Provision Stores',
      nameTa: 'ஈரோடு புரொவிஷன் ஸ்டோர்ஸ்',
      address: '101, Market Road',
      addressTa: '101, மார்க்கெட் சாலை',
      area: 'Erode Market',
      areaTa: 'ஈரோடு மார்க்கெட்',
      city: 'Erode',
      cityTa: 'ஈரோடு',
      pincode: '638001',
      fullAddress: '101, Market Road, Erode Market, Erode, 638001',
      fullAddressTa: '101, மார்க்கெட் சாலை, ஈரோடு மார்க்கெட், ஈரோடு, 638001',
      ownerName: 'N. Kumarasamy',
      ownerNameTa: 'N. குமாரசாமி',
    ),
  };

  /// Verified predefined task titles.
  static const tasks = <String, TaskDisplay>{
    't_erode': TaskDisplay(
      title: 'Shop Recce – Erode Market',
      titleTa: 'கடைத் தள ஆய்வு – ஈரோடு மார்க்கெட்',
    ),
  };

  /// Verified predefined person display names (initials/numerals preserved).
  static const people = <String, String>{
    'Murugan K': 'முருகன் K',
    'N. Kumarasamy': 'N. குமாரசாமி',
  };

  /// Predefined location components (only verified values are mapped).
  static const locations = <String, String>{
    'Market Road': 'மார்க்கெட் சாலை',
    'Erode Market': 'ஈரோடு மார்க்கெட்',
    'Erode': 'ஈரோடு',
    'Srirangam': 'சிரிரங்கம்',
    'Thillai Nagar': 'தில்லை நகர்',
    'K.K. Nagar': 'கே.கே. நகர்',
    'Tiruchirappalli': 'திருச்சிராப்பள்ளி',
    'Madurai': 'மதுரை',
  };

  /// Predefined region labels. Arbitrary addresses are never translated.
  static const regions = <String, String>{
    'Trichy & Delta': 'திருச்சி மற்றும் டெல்டா',
    'Madurai': 'மதுரை',
    'Erode': 'ஈரோடு',
    'Chennai': 'சென்னை',
    'Coimbatore': 'கோயம்புத்தூர்',
    'Tamil Nadu': 'தமிழ்நாடு',
  };

  /// Canonical media display names used by media tabs, board names, cards
  /// and selectors. Stored codes (GSB_SINGLE, NLB_BOX_FRAME, …) never change.
  static const media = <String, String>{
    'GSB Single': 'GSB ஒற்றைப் பக்கம்',
    'GSB Double': 'GSB இரட்டைப் பக்கம்',
    'GSB Single Side': 'GSB ஒற்றைப் பக்கம்',
    'GSB Double Side': 'GSB இரட்டைப் பக்கம்',
    'NLB Single': 'NLB ஒற்றைச் சட்டகம்',
    'NLB Box': 'NLB பெட்டி வகை',
    'NLB Double': 'NLB பெட்டி வகை',
    'NLB Single Side': 'NLB ஒற்றைச் சட்டகம்',
    'NLB Single Frame': 'NLB ஒற்றைச் சட்டகம்',
    'NLB Double Side': 'NLB பெட்டி வகை',
    'NLB Box Frame': 'NLB பெட்டி வகை',
    'NLB': 'NLB',
    'Acrylic': 'அக்ரிலிக்',
    'Clear Acrylic': 'அக்ரிலிக்',
    'Foam Vinyl': 'ஃபோம் வினைல்',
    'One-Way Vision': 'ஒருவழிப் பார்வை வினைல்',
    'Plain Vinyl': 'சாதாரண வினைல்',
    'MDF': 'MDF',
    'Other': 'மற்ற பலகை வகைகள்',
    'Other Media Type': 'மற்ற பலகை வகைகள்',
    'Board': 'பலகை',
  };

  /// Canonical installation names (predefined choices only).
  static const installations = <String, String>{
    'Shop Fascia': 'கடை முகப்புப் பொருத்தம்',
    'Wall Mount': 'சுவரில் பொருத்துதல்',
    'Double Pole': 'இரட்டைக் கம்பம்',
    'Single Pole': 'ஒற்றைக் கம்பம்',
    'Rooftop': 'மாடிப் பொருத்தம்',
    'Support Pipe': 'ஆதரவுக் குழாய்',
    'Projecting Mount': 'நீட்டிப்புப் பொருத்தம்',
    'Flange Bracket': 'நீட்டிப்புப் பொருத்தம்',
    'Hanging Mount': 'தொங்கும் பொருத்தம்',
    'Floor Mount': 'தரையில் பொருத்துதல்',
    'Free Standing (Ground)': 'தரையில் பொருத்துதல்',
    'Direct on Wall': 'நேரடிச் சுவர்ப் பொருத்தம்',
    'Glass / Shutter Pasting': 'கண்ணாடி / ஷட்டரில் ஒட்டுதல்',
    'Other': 'மற்றவை',
  };

  /// Predefined installation descriptions (never applied to custom text).
  static const installationDescriptions = <String, String>{
    'Projects outwards from a wall.':
        'சுவரிலிருந்து வெளிப்புறமாக நீட்டித்துப் பொருத்தப்படும்.',
    'Supported by two ground-mounted poles.':
        'தரையில் அமைக்கப்பட்ட இரண்டு கம்பங்களால் தாங்கப்படும்.',
    'Supported by one central pole.':
        'நடுவில் அமைக்கப்பட்ட ஒற்றைக் கம்பத்தால் தாங்கப்படும்.',
    'Mounted on a roof or terrace.': 'கூரை அல்லது மாடியில் பொருத்தப்படும்.',
    'Suspended from an overhead structure.':
        'மேல்புற அமைப்பிலிருந்து தொங்கவிடப்படும்.',
    'Fixed on the shop front elevation above the shutter.':
        'ஷட்டருக்கு மேலே உள்ள கடை முகப்பில் பொருத்தப்படும்.',
    'Fixed on a side / compound wall with anchors.':
        'பக்கச் சுவரில் ஆங்கர்கள் கொண்டு பொருத்தப்படும்.',
    'Free-standing board on two MS/GI poles with footing.':
        'அடித்தளத்துடன் கூடிய இரண்டு MS/GI கம்பங்களில் நிறுத்தப்படும்.',
    'Free-standing board on a single central pole.':
        'ஒற்றை மையக் கம்பத்தில் நிறுத்தப்படும்.',
    'MS structure erected on the terrace / roof.':
        'மாடி / கூரையில் MS அமைப்பு எழுப்பப்படும்.',
    'Projecting board on wall brackets.':
        'சுவரில் பொருத்தப்பட்ட தாங்கிகளில் நீட்டித்துப் பொருத்தப்படும்.',
    'Painted / pasted directly on the wall surface.':
        'சுவரில் நேரடியாக வரையப்படும் / ஒட்டப்படும்.',
    'Pasted on glass panels, doors or rolling shutters.':
        'கண்ணாடி, கதவு அல்லது ரோலிங் ஷட்டரில் ஒட்டப்படும்.',
    'Standee placed on the ground outside / inside the shop.':
        'கடைக்கு உள்ளே / வெளியே தரையில் ஸ்டாண்டி வைக்கப்படும்.',
    'Described by the vendor (text or voice).':
        'விற்பனையாளர் உரை அல்லது குரலாக விவரிக்கிறார்.',
    'Board held off the wall / parapet on MS support pipes.':
        'சுவர் / மேல்தட்டில் இருந்து MS குழாய்களால் பிடிக்கப்படும்.',
  };

  /// Verified app-generated board-name prefixes. A custom-renamed board is
  /// never translated (callers guard with SignageCatalog.isAutoBoardName).
  static const generatedNamePrefixes = <String, String>{
    'GSB Single': 'GSB ஒற்றைப் பக்கம்',
    'GSB Double': 'GSB இரட்டைப் பக்கம்',
    'NLB Single': 'NLB ஒற்றைச் சட்டகம்',
    'NLB Double': 'NLB பெட்டி வகை',
    'NLB Box': 'NLB பெட்டி வகை',
    'NLB': 'NLB',
  };
}

class ProjectDisplay {
  const ProjectDisplay({
    required this.name,
    required this.nameTa,
    required this.description,
    required this.descriptionTa,
  });

  final String name;
  final String nameTa;
  final String description;
  final String descriptionTa;
}

class ShopDisplay {
  const ShopDisplay({
    required this.name,
    required this.nameTa,
    required this.address,
    required this.addressTa,
    required this.area,
    required this.areaTa,
    required this.city,
    required this.cityTa,
    required this.pincode,
    required this.fullAddress,
    required this.fullAddressTa,
    required this.ownerName,
    required this.ownerNameTa,
  });

  final String name;
  final String nameTa;
  final String address;
  final String addressTa;
  final String area;
  final String areaTa;
  final String city;
  final String cityTa;
  final String pincode;
  final String fullAddress;
  final String fullAddressTa;
  final String ownerName;
  final String ownerNameTa;

  bool matches({
    required String currentName,
    required String currentAddress,
    required String currentArea,
    required String currentCity,
    required String currentPincode,
    required String currentOwner,
  }) =>
      currentName == name &&
      currentAddress == address &&
      currentArea == area &&
      currentCity == city &&
      currentPincode == pincode &&
      currentOwner == ownerName;
}

class TaskDisplay {
  const TaskDisplay({required this.title, required this.titleTa});
  final String title;
  final String titleTa;
}
