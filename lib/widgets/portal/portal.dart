/// The shared design kit for the station-owner and admin portals.
///
/// One import for the pieces that give both portals the rhythm the public
/// website already has: a page header with an eyebrow and a display-face
/// title, titled sections, one card treatment, stat tiles that count up,
/// status pills and a single empty state -- all reading only
/// `Theme.of(context)`, so they invert correctly under AppTheme and
/// AdminTheme in either mode.
library;

// StatusTint and StatusCallout come with the kit: the tiles, pills and cards
// are built on the tint, and any screen composing them needs the same tint for
// its own icons and banners. Exporting it here saves every screen a second
// import for what is really one vocabulary.
export '../status_callout.dart';
export 'portal_action_row.dart';
export 'portal_card.dart';
export 'portal_density.dart';
export 'portal_empty_state.dart';
export 'portal_page_header.dart';
export 'portal_section.dart';
export 'portal_stat_tile.dart';
export 'status_pill.dart';
