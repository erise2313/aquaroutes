import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../merchant/merchant_navigation.dart';
import '../customer/customer_navigation.dart';

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

  String _selectedRole = 'customer';
  bool _isLoading = false;

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      // 1. Create the base Authentication Account First
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = res.user;

      if (user != null) {
        // 2. Client-Side Provisioning: Explicitly push data into the table
        await supabase.from('user_profiles').upsert({
          'id': user.id, // Links directly to the Auth account
          'role': _selectedRole,
          'full_name': _fullNameController.text.trim(),
          // Only save these if they are a merchant, otherwise leave them null
          'business_name': _selectedRole == 'merchant'
              ? _businessNameController.text.trim()
              : null,
          'station_address': _selectedRole == 'merchant'
              ? _stationAddressController.text.trim()
              : null,
          'kyc_status': _selectedRole == 'merchant' ? 'pending_upload' : null,
        });

        if (!mounted) return;

        // 3. Route to the correct dashboard
        if (_selectedRole == 'merchant') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MerchantNavigation()),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const CustomerNavigation()),
            (route) => false,
          );
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

              if (_selectedRole == 'merchant')
                _buildMerchantFields()
              else
                _buildCustomerFields(),

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
        DropdownMenuItem(
          value: 'customer',
          child: Text("Customer (Buying Water)"),
        ),
        DropdownMenuItem(
          value: 'merchant',
          child: Text("Business Owner (Selling Water)"),
        ),
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
        _buildTextField(
          controller: _fullNameController,
          label: "Full Name",
          icon: Icons.person_outline,
        ),
      ],
    );
  }

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
          label: "Station Address (Tanza, Cavite)",
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isEmail = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
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
