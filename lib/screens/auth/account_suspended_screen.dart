import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';

/// Shown when a signed-in account has a membership row that exists but
/// isn't 'active' (suspended or revoked by a WASA admin, see
/// user_management_screen.dart) -- distinct from NoMembershipScreen, which
/// is for accounts with no membership row at all. AuthGate tells the two
/// apart via rawMembershipStatusProvider (providers/app_state.dart) since
/// the normal currentMembershipProvider filters status = 'active' and can't
/// distinguish "suspended" from "never assigned."
class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Your account access has been suspended by WASA admin.\n\n'
                'If you believe this is a mistake, please contact WASA to resolve it.',
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
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
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
