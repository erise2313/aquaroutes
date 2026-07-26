import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math'; // Required for generating the invite code
import '../merchant/merchant_navigation.dart';
import '../customer/customer_navigation.dart';
import '../driver/driver_dashboard.dart'; // Ensure this points to your new Driver file

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final supabase = Supabase.instance.client;

  // Shared Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();

  // Merchant-Specific Controllers
  final _businessNameController = TextEditingController();
  final _stationAddressController = TextEditingController();

  // Driver-Specific Controllers
  final _inviteCodeController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _capacityController = TextEditingController();

  String _selectedRole = 'customer';
  bool _isLoading = false;

  // Generates a random 6-character code for Merchants
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    
    String? assignedStationId;

    try {
      // 1. SECURE DRIVER CHECK: Verify invite code BEFORE creating the Auth account
      if (_selectedRole == 'driver') {
        // Removed the .toUpperCase() so we pass the raw text
        final code = _inviteCodeController.text.trim(); 
        
        final stationMatch = await supabase
            .from('water_stations')
            .select('id')
            // Changed .eq to .ilike for case-insensitive matching
            .ilike('invite_code', code) 
            .maybeSingle();

        if (stationMatch == null) {
          throw Exception("Invalid Station Invite Code! Please ask your boss for the correct key.");
        }
        assignedStationId = stationMatch['id'];
      }

      // 2. Create the base Authentication Account
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = res.user;

      if (user != null) {
        // 3. Upsert into user_profiles with the new driver data
        await supabase.from('user_profiles').upsert({
          'id': user.id, 
          'role': _selectedRole,
          'full_name': _fullNameController.text.trim(),
          
          // Merchant Data
          'business_name': _selectedRole == 'merchant' ? _businessNameController.text.trim() : null,
          'station_address': _selectedRole == 'merchant' ? _stationAddressController.text.trim() : null,
          'kyc_status': _selectedRole == 'merchant' ? 'pending_upload' : null,
          
          // Driver Data
          'assigned_station_id': assignedStationId,
          'vehicle_plate': _selectedRole == 'driver' ? _plateNumberController.text.trim().toUpperCase() : null,
          'jug_capacity': _selectedRole == 'driver' ? int.tryParse(_capacityController.text.trim()) : null,
        });

        // 4. MERCHANT ONLY: Automatically create their water station and generate their invite key
        if (_selectedRole == 'merchant') {
          final newCode = _generateInviteCode();
          await supabase.from('water_stations').insert({
            'owner_id': user.id,
            'station_name': _businessNameController.text.trim(),
            'invite_code': newCode, 
          });
        }

        if (!mounted) return;

        // 5. Route to the correct dashboard
        if (_selectedRole == 'merchant') {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MerchantNavigation()), (route) => false);
        } else if (_selectedRole == 'driver') {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const DriverDashboardScreen()), (route) => false);
        } else {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const CustomerNavigation()), (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Registration Error: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Create an Account",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Join AquaRoutes and manage deliveries instantly.",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              _buildRoleDropdown(),
              const SizedBox(height: 24),

              if (_selectedRole == 'merchant') _buildMerchantFields()
              else if (_selectedRole == 'driver') _buildDriverFields()
              else _buildCustomerFields(),

              const SizedBox(height: 24),

              _buildTextField(
                controller: _emailController,
                label: "Email Address",
                icon: Icons.email_outlined,
                isEmail: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                label: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _signUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "REGISTER",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI BUILDER HELPERS ---

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedRole,
      decoration: InputDecoration(
        labelText: "Account Type",
        prefixIcon: const Icon(Icons.badge_outlined, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'customer', child: Text("Customer (Buying Water)")),
        DropdownMenuItem(value: 'merchant', child: Text("Business Owner (Selling Water)")),
        DropdownMenuItem(value: 'driver', child: Text("Driver (Delivery Personnel)")),
      ],
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedRole = newValue);
        }
      },
    );
  }

  Widget _buildCustomerFields() {
    return Column(
      children: [
        _buildTextField(controller: _fullNameController, label: "Full Name", icon: Icons.person_outline),
      ],
    );
  }

  // PRESERVED YOUR ORIGINAL UI FOR MERCHANTS
  Widget _buildMerchantFields() {
    return Column(
      children: [
        _buildTextField(
          controller: _businessNameController,
          label: "Water Station Name",
          icon: Icons.water_drop_outlined,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _fullNameController,
          label: "Owner Full Name",
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _stationAddressController,
          label: "Station Address (San Francisco, General Trias)", // Kept your local placeholder!
          icon: Icons.store_mall_directory_outlined,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Business Permit / KYC upload will be required after successful registration.",
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // NEW DRIVER UI
  Widget _buildDriverFields() {
    return Column(
      children: [
        _buildTextField(controller: _fullNameController, label: "Driver Full Name", icon: Icons.person_outline),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50, 
            borderRadius: BorderRadius.circular(12), 
            border: Border.all(color: Colors.blue.shade200)
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.vpn_key, color: Colors.blue), 
                  SizedBox(width: 8),
                  Text("Station Link Key", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              const SizedBox(height: 8),
              _buildTextField(controller: _inviteCodeController, label: "Enter Merchant Invite Code", icon: Icons.numbers),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildTextField(controller: _plateNumberController, label: "Plate No.", icon: Icons.directions_car)),
            const SizedBox(width: 12),
            Expanded(child: _buildTextField(controller: _capacityController, label: "Max Jugs", icon: Icons.scale, isNumber: true)),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isEmail = false,
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : (isNumber ? TextInputType.number : TextInputType.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade500),
        filled: true,
        fillColor: Colors.grey.shade50,
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