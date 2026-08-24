import 'package:flutter/material.dart';

import 'bulletin_feed.dart';

/// Thin Scaffold wrapper around [BulletinFeed] with a title bar -- used when
/// navigating here from within an authenticated portal (see the "Board" tab
/// in merchant_navigation.dart and the app-bar icon in driver_dashboard.dart).
/// The guest home (public_home_screen.dart) embeds BulletinFeed directly as
/// one of its bottom-nav tabs instead of through this wrapper.
class BulletinBoardScreen extends StatelessWidget {
  const BulletinBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Association Bulletin Board')),
      body: const BulletinFeed(),
    );
  }
}
