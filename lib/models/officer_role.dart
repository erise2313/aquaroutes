/// What an officer may change (supabase/patch_officer_roles.sql).
///
/// Every officer can read everything; the role limits which areas they can
/// change, and the database enforces it on every write. These labels and
/// descriptions are what super admins see when choosing a role.
enum OfficerRole {
  superadmin,
  officer,
  compliance,
  workforce,
  content,
  viewer;

  /// The value the database stores (memberships.officer_role), or
  /// 'superadmin' for a super admin.
  String get key => name;

  String get label => switch (this) {
        OfficerRole.superadmin => 'Super admin',
        OfficerRole.officer => 'Officer (full)',
        OfficerRole.compliance => 'Compliance officer',
        OfficerRole.workforce => 'Workforce officer',
        OfficerRole.content => 'Content editor',
        OfficerRole.viewer => 'Viewer (auditor)',
      };

  String get description => switch (this) {
        OfficerRole.superadmin =>
          'Everything, plus officers, association settings and station ownership transfers. Keep this to two people.',
        OfficerRole.officer => 'Everything except managing officers and association settings.',
        OfficerRole.compliance => 'Stations, permits, notices, cases and customer reports.',
        OfficerRole.workforce => 'Workers, incidents, credentials and appeals.',
        OfficerRole.content => 'Bulletin, floor prices, containers, events, resources, website content and reviews.',
        OfficerRole.viewer => 'Sees everything and can export, but changes nothing.',
      };

  /// From a memberships row: its app role and officer_role.
  static OfficerRole? fromMembership(String? role, String? officerRole) {
    if (role == 'wasa_superadmin') return OfficerRole.superadmin;
    if (role != 'wasa_admin') return null;
    return OfficerRole.values.firstWhere(
      (r) => r.key == officerRole && r != OfficerRole.superadmin,
      orElse: () => OfficerRole.officer,
    );
  }
}
