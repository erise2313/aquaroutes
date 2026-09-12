/// Saving a file from the app itself needs a platform file picker and
/// storage permissions, which the association doesn't need: admin runs in a
/// browser (gentri-wasa-admin.web.app). Returning false lets the caller say
/// so plainly instead of appearing to do nothing.
bool downloadCsv(String filename, String content) => false;
