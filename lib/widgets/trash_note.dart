/// How long deleted things wait in the Trash (patch_trash.sql) before a
/// daily job removes them for good.
const trashRetentionDays = 5;

/// Added to every delete confirmation, so nobody is told a delete is final
/// when it isn't -- or left unaware they have days to change their mind.
const trashNote = 'It stays in Trash for $trashRetentionDays days and can be restored from there.';
