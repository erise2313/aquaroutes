import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'org_home_screen.dart';

/// Shown when a driver or customer account is used to log into the
/// website build. Those two roles are intentionally mobile-app-only (GPS
/// tracking, on-the-go dispatch, casual ordering) -- the website is the
/// organization/business side (station owner + WASA admin). Rather than
/// routing them into screens built assuming a phone (camera capture,
/// location permissions), tell them plainly to use the app instead.
class MobileOnlyScreen extends StatelessWidget {
  const MobileOnlyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_android, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'This account type is only available on the GenTri: WASA mobile app.\n\n'
                'The website is for station owners and WASA admin. Download the app to order water or manage deliveries.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const OrgHomeScreen()),
                      (route) => false,
                    );
                  }
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
