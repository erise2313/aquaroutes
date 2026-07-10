import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aquaroute/screens/auth/login_screen.dart'; // Adjust this path if your login screen is in a different folder!;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _jugWeightController = TextEditingController(text: "19");
  final _velocityLimitController = TextEditingController(text: "20");
  bool _isLoggingOut = false;

  // 🛡️ The Secure Supabase Logout Function
  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);

    try {
      // 1. Tell Supabase to kill the session and invalidate the JWT
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // We catch the error, but we intentionally do NOT stop the function.
      // If the user is offline, the server call fails, but we still want to
      // kick them out of the local app interface for security.
      debugPrint("Server logout failed (likely offline): $e");
    } finally {
      // 2. The Async Context Check
      if (mounted) {
        // 3. The Navigation Nuke - Destroys all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "System Configuration",
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Dynamic Payload Math Engine",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            _buildFlatTextField(
              controller: _jugWeightController,
              label: "Weight per 5-Gallon Jug (kg)",
              icon: Icons.monitor_weight_outlined,
            ),
            const SizedBox(height: 16),

            _buildFlatTextField(
              controller: _velocityLimitController,
              label: "Safety Velocity Limit (kph)",
              icon: Icons.speed,
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                // Logic to save to Supabase will go here later
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Settings Updated"),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Save Configuration",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            const SizedBox(height: 48),
            const Divider(),
            const SizedBox(height: 24),

            // The Destructive Action Button
            OutlinedButton.icon(
              onPressed: _isLoggingOut ? null : _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isLoggingOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.redAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.logout),
              label: const Text(
                "SECURE LOGOUT",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget maintaining the modern flat design system
  Widget _buildFlatTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade500),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}
