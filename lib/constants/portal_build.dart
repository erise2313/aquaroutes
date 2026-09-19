/// Which flavour this build is, decided at compile time.
///
/// Set by `--dart-define=PORTAL=admin` (deploy_admin_web.ps1) for the
/// WASA-admin-only hosting build (site gentri-wasa-admin). Always false in
/// the default web build and in the mobile app, neither of which passes the
/// define -- so behaviour elsewhere is provably unchanged unless this
/// flavour is explicitly built.
///
/// One constant rather than a private copy per file: auth_gate routes on it,
/// main.dart decides the public website on it, and login_screen decides
/// whether registration is offered at all. Three private definitions of one
/// fact is how they drift apart.
const kIsAdminPortalBuild = String.fromEnvironment('PORTAL') == 'admin';
