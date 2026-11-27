/// Active vendor question policy (derived from the vendor-reviewed
/// Recce-form.xlsx plus explicit business overrides).
///
/// Question DEFINITIONS are never deleted: this policy only decides which
/// questions are asked for NEW work on the active media types. Stored
/// answers of hidden questions stay untouched, and legacy media types keep
/// every question they had.
class VendorQuestionPolicy {
  VendorQuestionPolicy._();

  /// Media types the policy applies to (the selectable media).
  static const mediaCodes = {
    'GSB',
    'NLB',
    'FOAM_VINYL',
    'ACRYLIC',
    'OWV',
    'PLAIN_VINYL',
    'MDF',
    'OTHER', // custom media: common + remarks only
  };

  /// Site Question ids marked Needed in App (or overridden to stay).
  static const retainedSite = {
    'existing_board',
    'remove_existing',
    'power_available',
    'power_distance',
    'shutter_height',
    'fascia_material',
    'wall_type',
    'terrace_access',
    'pipe_count',
    'pipe_length',
    'panel_count',
  };

  /// Kept TEMPORARILY although the vendor marked them Not Needed: they feed
  /// the 2D / 3D / AR geometry or a site-safety review flag and no
  /// replacement collection point has been approved yet.
  static const reviewRetainedSite = {
    'pole_height',
    'pole_gap',
    'foundation_depth',
    'mount_height',
    'structure_height',
    'building_floors',
    'projection',
    'excavation_permission',
  };

  /// Geometry-only inputs. They are NOT shown in the Site Questions form:
  /// the Installation Type step shows them as "Installation Measurements"
  /// (same answer keys, same measurement mirrors, same 2D / 3D / AR input).
  static const measurementIds = {
    'mount_height',
    'pole_height',
    'pole_gap',
    'foundation_depth',
    'structure_height',
    'building_floors',
    'projection',
  };

  static bool isMeasurement(String? mediaCode, String id) =>
      appliesTo(mediaCode) && measurementIds.contains(id);

  /// Checklist ids (not already a Site Question) that stay.
  static const retainedChecklist = {
    'checklist_remarks',
    'electricity_nearby',
    'visible_wires',
    'support_pipe_required',
    'existing_stickers',
    // Evidence photos are collected in Site Photos & Annotation.
    'site_evidence_photo',
  };

  /// Checklist questions that raise a site-feasibility review flag. The
  /// vendor marked them Not Needed, but they stay in the form (and required)
  /// until the business explicitly approves their removal: hiding them would
  /// make an unassessed site look "No Known Obstruction".
  static const reviewRetainedChecklist = {
    'underground_utilities',
    'pole_excavation_allowed',
    'structure_accessible',
    'fixing_surface_available',
    'ac_or_obstruction',
    'location_approved_by_shop',
    'area_free_of_obstruction',
    'pole_configuration_confirmed',
    'door_opening_clearance',
    'moisture_exposure',
  };

  /// Shown together in a compact "Installation Safety" subsection.
  static const safetyIds = {
    'excavation_permission',
    'underground_utilities',
    'pole_excavation_allowed',
  };

  static bool isSafety(String? mediaCode, String id) =>
      appliesTo(mediaCode) && safetyIds.contains(id);

  static bool appliesTo(String? mediaCode) => mediaCodes.contains(mediaCode);

  static bool siteActive(String? mediaCode, String id) =>
      !appliesTo(mediaCode) ||
      retainedSite.contains(id) ||
      reviewRetainedSite.contains(id);

  static bool checklistActive(String? mediaCode, String id) =>
      !appliesTo(mediaCode) ||
      retainedChecklist.contains(id) ||
      reviewRetainedChecklist.contains(id);
}
