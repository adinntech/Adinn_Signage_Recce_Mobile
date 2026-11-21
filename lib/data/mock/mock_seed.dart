import '../catalog/signage_catalog.dart';
import '../models/models.dart';

/// Demo credentials shown on the login screen. Login is by 4-digit PIN only,
/// so every user's PIN is unique.
class DemoAccounts {
  DemoAccounts._();

  static const vendorPin = '5678';
  static const businessPin = '1234';
  static const opsPin = '4321';

  /// Seed PIN per user id (used to migrate data saved before PIN login).
  static const seedPins = {
    'u_vendor': vendorPin,
    'u_business': businessPin,
    'u_ops': opsPin,
  };

  /// Dummy OTP for the forgot-PIN flow.
  static const otp = '246810';
}

/// Builds the local dummy dataset used on first launch (and on reset).
AppData buildSeedData([DateTime? clock]) {
  final now = clock ?? DateTime.now();
  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));
  DateTime ahead(int days) => DateTime(now.year, now.month, now.day + days, 18);

  final vendor = AppUser(
    id: 'u_vendor',
    code: 'VEN-5678',
    pin: DemoAccounts.vendorPin,
    name: 'Murugan K',
    role: UserRole.vendor,
    mobile: '9876543210',
    email: 'murugan.vendor@example.com',
    company: 'Sri Vinayaga Signs (Vendor)',
    region: 'Trichy Region',
    designation: 'Recce Executive',
  );
  final business = AppUser(
    id: 'u_business',
    code: 'BIZ01',
    pin: DemoAccounts.businessPin,
    name: 'Priya Shankar',
    role: UserRole.businessTeam,
    mobile: '9840011223',
    email: 'priya.business@example.com',
    company: 'Adinn Advertising',
    region: 'Tamil Nadu',
    designation: 'Business Manager',
  );
  final ops = AppUser(
    id: 'u_ops',
    code: 'OPS01',
    pin: DemoAccounts.opsPin,
    name: 'Karthik Raja',
    role: UserRole.recceOps,
    mobile: '9840044556',
    email: 'karthik.ops@example.com',
    company: 'Adinn Advertising',
    region: 'Tamil Nadu',
    designation: 'Recce Operations Lead',
  );

  final projects = [
    Project(
      id: 'p_asian',
      code: 'AP-TN-2026',
      name: 'Asian Paints',
      client: 'Asian Paints Ltd.',
      description:
          'Dealer signage branding drive – GSB, NLB and wall branding for '
          'paint dealers across central Tamil Nadu.',
      region: 'Trichy & Delta',
      startDate: ago(days: 20),
      endDate: ahead(40),
      coordinatorName: 'Priya Shankar',
      coordinatorPhone: '9840011223',
    ),
    Project(
      id: 'p_ramco',
      code: 'RC-MDU-2026',
      name: 'Ramco Cements',
      client: 'The Ramco Cements Ltd.',
      description: 'Dealer board replacement with ACP and rooftop GSB units.',
      region: 'Madurai',
      startDate: ago(days: 35),
      endDate: ahead(25),
      coordinatorName: 'Priya Shankar',
      coordinatorPhone: '9840011223',
    ),
    Project(
      id: 'p_sakthi',
      code: 'SM-ERD-2026',
      name: 'Sakthi Masala',
      client: 'Sakthi Masala Pvt. Ltd.',
      description: 'Retail visibility – flange boards and shutter vinyl.',
      region: 'Erode',
      startDate: ago(days: 5),
      endDate: ahead(60),
      coordinatorName: 'Priya Shankar',
      coordinatorPhone: '9840011223',
    ),
  ];

  final tasks = [
    RecceTask(
      id: 't_srirangam',
      projectId: 'p_asian',
      title: 'Shop Recce – Srirangam',
      location: 'Srirangam',
      city: 'Tiruchirappalli',
      dueDate: ahead(5),
      assignedVendorId: vendor.id,
      priority: 'High',
      instructions:
          'Capture front, left and right photos for every board. Mark the '
          'board area on the front photo and record exact W × H.',
    ),
    RecceTask(
      id: 't_thillai',
      projectId: 'p_asian',
      title: 'Shop Recce – Thillai Nagar',
      location: 'Thillai Nagar',
      city: 'Tiruchirappalli',
      dueDate: ahead(9),
      assignedVendorId: vendor.id,
      instructions: 'Wall mount boards only where wall condition is good.',
    ),
    RecceTask(
      id: 't_kknagar',
      projectId: 'p_ramco',
      title: 'Shop Recce – K.K. Nagar',
      location: 'K.K. Nagar',
      city: 'Madurai',
      dueDate: ahead(3),
      assignedVendorId: vendor.id,
      priority: 'High',
      instructions: 'Rooftop units need building NOC photo.',
    ),
    RecceTask(
      id: 't_erode',
      projectId: 'p_sakthi',
      title: 'Shop Recce – Erode Market',
      location: 'Market Road',
      city: 'Erode',
      dueDate: ahead(14),
      assignedVendorId: vendor.id,
      priority: 'Low',
    ),
  ];

  GeoFix fix(double lat, double lng, {double accuracy = 6}) => GeoFix(
    latitude: lat,
    longitude: lng,
    accuracyM: accuracy,
    capturedAt: ago(days: 2),
  );

  SitePhoto demoPhoto(
    String id,
    int seed,
    String label, {
    Annotation? mark,
    GeoFix? geo,
  }) => SitePhoto(
    id: id,
    path: '${SitePhoto.demoPrefix}$seed',
    label: label,
    capturedAt: ago(days: 2),
    width: 1200,
    height: 900,
    annotations: mark == null ? [] : [mark],
    geo: geo,
  );

  Annotation mark(String id, double w, double h, {String label = 'Board 1'}) =>
      Annotation(
        id: id,
        type: AnnotationType.rectangle,
        x: 600,
        y: 300,
        w: 640,
        h: 210,
        label: label,
        measureW: w,
        measureH: h,
      );

  // --- Srirangam -----------------------------------------------------------
  final s1 = Shop(
    id: 's_sriranga',
    projectId: 'p_asian',
    taskId: 't_srirangam',
    name: 'Sri Ranga Paints & Hardwares',
    ownerName: 'R. Venkatesan',
    phone: '9443012345',
    address: '42, North Chithirai Street',
    area: 'Srirangam',
    city: 'Tiruchirappalli',
    pincode: '620006',
    landmark: 'Near Rajagopuram',
    status: RecceStatus.inProgress,
    createdAt: ago(days: 3),
    updatedAt: ago(hours: 5),
    boards: [
      Board(
        id: 'b_sriranga_1',
        name: 'Main Board',
        mediaCode: SignageCatalog.gsb,
        installationCode: SignageCatalog.doublePole,
        width: 10,
        height: 4,
        answers: {
          'pole_height': 9,
          'pole_gap': 7,
          'ground_type': 'Concrete',
          'foundation_depth': 3,
          'pole_material': 'MS pipe',
          'power_available': true,
          'light_type': 'LED modules',
        },
        photos: [
          demoPhoto('ph_s1_1', 1, 'Front view', mark: mark('a_s1_1', 10, 4)),
        ],
        textNote: 'Shop owner prefers the board facing the main road.',
        updatedAt: ago(hours: 5),
      ),
    ],
  );

  final s2 = Shop(
    id: 's_lakshmi',
    projectId: 'p_asian',
    taskId: 't_srirangam',
    name: 'Lakshmi Hardware Stores',
    ownerName: 'S. Lakshmi Narayanan',
    phone: '9443098765',
    address: '7, Amma Mandapam Road',
    area: 'Srirangam',
    city: 'Tiruchirappalli',
    pincode: '620006',
    landmark: 'Opp. Amma Mandapam',
    createdAt: ago(days: 3),
    updatedAt: ago(days: 3),
  );

  final s3 = Shop(
    id: 's_amma',
    projectId: 'p_asian',
    taskId: 't_srirangam',
    name: 'Amma Paint House',
    ownerName: 'K. Selvi',
    phone: '9500011122',
    address: '15, East Uthira Street',
    area: 'Srirangam',
    city: 'Tiruchirappalli',
    pincode: '620006',
    geo: fix(10.86402, 78.69351),
    status: RecceStatus.pendingBusiness,
    createdAt: ago(days: 4),
    updatedAt: ago(hours: 20),
    boards: [
      Board(
        id: 'b_amma_1',
        name: 'Fascia Board',
        mediaCode: SignageCatalog.gsb,
        installationCode: SignageCatalog.shopFascia,
        width: 12,
        height: 3,
        answers: {
          'fascia_material': 'Concrete',
          'shutter_height': 9,
          'neighbour_clearance': true,
          'power_available': true,
          'light_type': 'LED strip',
          'existing_board': true,
          'remove_existing': true,
          'access_method': 'Ladder',
          'owner_permission': true,
        },
        photos: [
          demoPhoto(
            'ph_s3_1',
            2,
            'Front view',
            mark: mark('a_s3_1', 12, 3),
            geo: fix(10.86409, 78.69347),
          ),
        ],
        updatedAt: ago(hours: 20),
      ),
    ],
  );
  s3.submissions.add(
    Submission(
      version: 1,
      submittedAt: ago(hours: 20),
      submittedById: vendor.id,
      submittedByName: vendor.name,
      snapshot: s3.toSnapshotJson(),
      vendorRemarks: 'Existing old board to be removed by shop owner.',
    ),
  );

  // --- Thillai Nagar --------------------------------------------------------
  final s4 = Shop(
    id: 's_royal',
    projectId: 'p_asian',
    taskId: 't_thillai',
    name: 'Royal Paints Centre',
    ownerName: 'M. Abdul Rahman',
    phone: '9790012345',
    address: '3rd Cross, 10th Main Road',
    area: 'Thillai Nagar',
    city: 'Tiruchirappalli',
    pincode: '620018',
    geo: fix(10.82681, 78.68123, accuracy: 14),
    status: RecceStatus.rejectedBusiness,
    createdAt: ago(days: 6),
    updatedAt: ago(days: 1),
    boards: [
      Board(
        id: 'b_royal_1',
        name: 'Side Wall Board',
        mediaCode: SignageCatalog.nlb,
        installationCode: SignageCatalog.wallMount,
        width: 8,
        height: 4,
        answers: {
          'wall_type': 'Brick',
          'wall_condition': 'Average',
          'mount_height': 7,
          'front_light': false,
          'frame_material': 'MS square tube',
          'existing_board': false,
          'access_method': 'Ladder',
          'owner_permission': true,
        },
        photos: [
          demoPhoto(
            'ph_s4_1',
            3,
            'Front view',
            geo: fix(10.82688, 78.68131, accuracy: 14),
          ),
        ],
        updatedAt: ago(days: 2),
      ),
    ],
  );
  s4.submissions.add(
    Submission(
      version: 1,
      submittedAt: ago(days: 2),
      submittedById: vendor.id,
      submittedByName: vendor.name,
      snapshot: (s4.toSnapshotJson()..['status'] = 'pendingBusiness'),
      reviews: [
        ReviewRecord(
          stage: ReviewStage.business,
          decision: ReviewDecision.rejected,
          reviewerId: business.id,
          reviewerName: business.name,
          remarks:
              'Board area is not marked on the photo and the wall looks '
              'damp. Please re-check wall condition and add close-up photos.',
          reasons: ['Photos unclear / insufficient', 'Missing site details'],
          at: ago(days: 1),
        ),
      ],
    ),
  );

  final s5 = Shop(
    id: 's_thillai_colour',
    projectId: 'p_asian',
    taskId: 't_thillai',
    name: 'Thillai Colour World',
    ownerName: 'P. Ganesan',
    phone: '9787654321',
    address: '22, Shastri Road',
    area: 'Thillai Nagar',
    city: 'Tiruchirappalli',
    pincode: '620018',
    geo: fix(10.82552, 78.68584),
    status: RecceStatus.pendingOps,
    createdAt: ago(days: 7),
    updatedAt: ago(hours: 30),
    boards: [
      Board(
        id: 'b_tc_1',
        name: 'Wall Branding',
        mediaCode: SignageCatalog.wallPainting,
        installationCode: SignageCatalog.directWall,
        width: 20,
        height: 8,
        answers: {
          'mount_height': 2,
          'wall_obstruction': true,
          'wall_surface': 'Plastered',
          'primer_required': true,
          'existing_board': false,
          'access_method': 'Scaffolding',
          'owner_permission': true,
        },
        photos: [
          demoPhoto(
            'ph_s5_1',
            4,
            'Long shot',
            mark: mark('a_s5_1', 20, 8, label: 'Wall area'),
            geo: fix(10.82547, 78.68590),
          ),
        ],
        updatedAt: ago(days: 2),
      ),
    ],
  );
  s5.submissions.add(
    Submission(
      version: 1,
      submittedAt: ago(days: 2),
      submittedById: vendor.id,
      submittedByName: vendor.name,
      snapshot: (s5.toSnapshotJson()..['status'] = 'pendingBusiness'),
      reviews: [
        ReviewRecord(
          stage: ReviewStage.business,
          decision: ReviewDecision.approved,
          reviewerId: business.id,
          reviewerName: business.name,
          remarks: 'Good location with high visibility. Approved.',
          at: ago(hours: 30),
        ),
      ],
    ),
  );

  // --- Madurai --------------------------------------------------------------
  final s6 = Shop(
    id: 's_meenakshi',
    projectId: 'p_ramco',
    taskId: 't_kknagar',
    name: 'Meenakshi Cement Agency',
    ownerName: 'T. Pandian',
    phone: '9442233445',
    address: '88, 80 Feet Road',
    area: 'K.K. Nagar',
    city: 'Madurai',
    pincode: '625020',
    geo: fix(9.93031, 78.14152, accuracy: 9),
    status: RecceStatus.approved,
    createdAt: ago(days: 12),
    updatedAt: ago(days: 4),
    boards: [
      Board(
        id: 'b_mn_1',
        name: 'Rooftop Unit',
        mediaCode: SignageCatalog.gsb,
        installationCode: SignageCatalog.rooftop,
        width: 16,
        height: 6,
        answers: {
          'building_floors': 2,
          'roof_type': 'RCC slab',
          'structure_height': 4,
          'terrace_access': true,
          'wind_exposure': 'Medium',
          'building_noc': true,
          'power_available': true,
          'light_type': 'LED modules',
          'existing_board': false,
          'access_method': 'Crane / Hydra',
          'owner_permission': true,
        },
        photos: [
          demoPhoto(
            'ph_s6_1',
            5,
            'Long shot',
            mark: mark('a_s6_1', 16, 6),
            geo: fix(9.93040, 78.14160, accuracy: 9),
          ),
        ],
        updatedAt: ago(days: 6),
      ),
    ],
  );
  s6.submissions.add(
    Submission(
      version: 1,
      submittedAt: ago(days: 6),
      submittedById: vendor.id,
      submittedByName: vendor.name,
      snapshot: (s6.toSnapshotJson()..['status'] = 'pendingBusiness'),
      reviews: [
        ReviewRecord(
          stage: ReviewStage.business,
          decision: ReviewDecision.approved,
          reviewerId: business.id,
          reviewerName: business.name,
          remarks: 'Approved for fabrication budget.',
          at: ago(days: 5),
        ),
        ReviewRecord(
          stage: ReviewStage.ops,
          decision: ReviewDecision.approved,
          reviewerId: ops.id,
          reviewerName: ops.name,
          remarks: 'Structure feasible. Proceed to fabrication.',
          at: ago(days: 4),
        ),
      ],
    ),
  );

  final s7 = Shop(
    id: 's_vaigai',
    projectId: 'p_ramco',
    taskId: 't_kknagar',
    name: 'Vaigai Building Materials',
    ownerName: 'A. Murugesan',
    phone: '9443355667',
    address: '5, Anna Main Road',
    area: 'K.K. Nagar',
    city: 'Madurai',
    pincode: '625020',
    createdAt: ago(days: 12),
    updatedAt: ago(days: 12),
  );

  // --- Erode ----------------------------------------------------------------
  final s8 = Shop(
    id: 's_erode_prov',
    projectId: 'p_sakthi',
    taskId: 't_erode',
    name: 'Erode Provision Stores',
    ownerName: 'N. Kumarasamy',
    phone: '9865012345',
    address: '101, Market Road',
    area: 'Erode Market',
    city: 'Erode',
    pincode: '638001',
    createdAt: ago(days: 2),
    updatedAt: ago(days: 2),
  );

  ActivityEvent ev(
    String id,
    String kind,
    String title,
    String message,
    AppUser actor,
    DateTime at, {
    String? shopId,
    String? projectId,
    String? taskId,
    int? version,
  }) => ActivityEvent(
    id: id,
    kind: kind,
    title: title,
    message: message,
    actorName: actor.name,
    actorRole: actor.role,
    at: at,
    shopId: shopId,
    projectId: projectId,
    taskId: taskId,
    version: version,
  );

  final activities = [
    ev(
      'e1',
      'submitted',
      'Recce submitted (v1)',
      'Meenakshi Cement Agency sent for Business approval.',
      vendor,
      ago(days: 6),
      shopId: s6.id,
      projectId: s6.projectId,
      taskId: s6.taskId,
      version: 1,
    ),
    ev(
      'e2',
      'approved',
      'Business approved (v1)',
      'Approved for fabrication budget.',
      business,
      ago(days: 5),
      shopId: s6.id,
      projectId: s6.projectId,
      taskId: s6.taskId,
      version: 1,
    ),
    ev(
      'e3',
      'approved',
      'Ops approved (v1) – Final',
      'Structure feasible. Proceed to fabrication.',
      ops,
      ago(days: 4),
      shopId: s6.id,
      projectId: s6.projectId,
      taskId: s6.taskId,
      version: 1,
    ),
    ev(
      'e4',
      'submitted',
      'Recce submitted (v1)',
      'Royal Paints Centre sent for Business approval.',
      vendor,
      ago(days: 2),
      shopId: s4.id,
      projectId: s4.projectId,
      taskId: s4.taskId,
      version: 1,
    ),
    ev(
      'e5',
      'submitted',
      'Recce submitted (v1)',
      'Thillai Colour World sent for Business approval.',
      vendor,
      ago(days: 2),
      shopId: s5.id,
      projectId: s5.projectId,
      taskId: s5.taskId,
      version: 1,
    ),
    ev(
      'e6',
      'rejected',
      'Business rejected (v1)',
      'Board area is not marked on the photo and the wall looks damp.',
      business,
      ago(days: 1),
      shopId: s4.id,
      projectId: s4.projectId,
      taskId: s4.taskId,
      version: 1,
    ),
    ev(
      'e7',
      'approved',
      'Business approved (v1)',
      'Good location with high visibility. Approved.',
      business,
      ago(hours: 30),
      shopId: s5.id,
      projectId: s5.projectId,
      taskId: s5.taskId,
      version: 1,
    ),
    ev(
      'e8',
      'submitted',
      'Recce submitted (v1)',
      'Amma Paint House sent for Business approval.',
      vendor,
      ago(hours: 20),
      shopId: s3.id,
      projectId: s3.projectId,
      taskId: s3.taskId,
      version: 1,
    ),
    ev(
      'e9',
      'updated',
      'Board updated',
      'Main Board (GSB · Double Pole) measurements captured.',
      vendor,
      ago(hours: 5),
      shopId: s1.id,
      projectId: s1.projectId,
      taskId: s1.taskId,
    ),
  ];

  return AppData(
    users: [vendor, business, ops],
    projects: projects,
    tasks: tasks,
    shops: [s1, s2, s3, s4, s5, s6, s7, s8],
    activities: activities,
  );
}
