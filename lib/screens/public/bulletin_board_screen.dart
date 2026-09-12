import 'package:flutter/material.dart';

import 'bulletin_feed.dart';

/// Scaffold wrapper around [BulletinFeed] for the portals -- the "Board" tab
/// in merchant_navigation.dart and the app-bar icon in driver_dashboard.dart.
/// The customer home (public_home_screen.dart) embeds BulletinFeed directly
/// as one of its tabs instead of going through this wrapper.
class BulletinBoardScreen extends StatelessWidget {
  const BulletinBoardScreen({super.key, this.showAppBar = true});

  /// False where the surrounding shell already supplies a header.
  ///
  /// The owner portal's Board tab now sits inside PortalShell, which carries
  /// the branded top bar, so this wrapper's own AppBar stacked a second bar
  /// above the feed -- the same double-chrome fault the Orders tab had. A
  /// pushed entry point (the driver dashboard's icon) still needs one, and
  /// keeps it.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('Association Bulletin Board')) : null,
      body: const BulletinFeed(),
    );
  }
}
