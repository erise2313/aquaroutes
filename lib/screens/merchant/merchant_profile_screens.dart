import 'package:aquaroute/screens/auth/login_screen.dart';
import 'package:aquaroute/screens/merchant/location_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_screen.dart';

bool _isLoggingOut = false;

Map<String, dynamic> buildProfileUpdatePayload({
  required String fullName,
  required String businessName,
  required String stationAddress,
  required String phoneNumber,
}) {
  return {
    'full_name': fullName.trim(),
    'business_name': businessName.trim(),
    'station_address': stationAddress.trim(),
    'phone_number': phoneNumber.trim(),
  };
}

class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _stationAddressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _businessNameController.dispose();
    _stationAddressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);

    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint("Logout error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _fetchProfileData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("User not authenticated");

      final data = await supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _profileData = data;
          _fullNameController.text = (_profileData?['full_name'] as String?) ?? '';
          _businessNameController.text = (_profileData?['business_name'] as String?) ?? '';
          _stationAddressController.text = (_profileData?['station_address'] as String?) ?? '';
          _phoneController.text = (_profileData?['phone_number'] as String?) ?? '';
          _emailController.text = supabase.auth.currentUser?.email ?? '';
          _latitudeController.text = (_profileData?['latitude'] as double?)?.toString() ?? '';
          _longitudeController.text = (_profileData?['longitude'] as double?)?.toString() ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to load profile data"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLatitude: double.tryParse(_latitudeController.text) ?? 14.0583,
          initialLongitude: double.tryParse(_longitudeController.text) ?? 121.0363,
          initialStationName: _businessNameController.text,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _latitudeController.text = result['latitude'].toString();
        _longitudeController.text = result['longitude'].toString();
        _businessNameController.text = result['station_name'];
      });
    }
  }

  Future<void> _saveProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      final payload = buildProfileUpdatePayload(
        fullName: _fullNameController.text,
        businessName: _businessNameController.text,
        stationAddress: _stationAddressController.text,
        phoneNumber: _phoneController.text,
      );

      double? lat;
      double? lng;

      if (_latitudeController.text.isNotEmpty &&
          _longitudeController.text.isNotEmpty) {
        lat = double.tryParse(_latitudeController.text);
        lng = double.tryParse(_longitudeController.text);
        if (lat != null && lng != null) {
          payload['latitude'] = lat;
          payload['longitude'] = lng;
        }
      }

      // 1. Update user_profiles including phone_number
      await supabase.from('user_profiles').update(payload).eq('id', userId);

      // 2. Also update water_stations using owner_id
      if (lat != null && lng != null) {
        await supabase.from('water_stations').update({
          'station_name': _businessNameController.text.trim(),
          'latitude': lat,
          'longitude': lng,
        }).eq('owner_id', userId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile and station location updated successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Station Profile",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    final String ownerName = _profileData?['full_name'] ?? "Unknown Owner";
    final String businessName = _profileData?['business_name'] ?? "Unnamed Station";
    final String email = supabase.auth.currentUser?.email ?? "";
    final String kycStatus = _profileData?['kyc_status'] ?? "pending_upload";

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.storefront,
                              size: 35,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ownerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$businessName\n$email",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildKycBanner(kycStatus),
                    const SizedBox(height: 24),
                    DefaultTabController(
                      length: 3,
                      initialIndex: _selectedTabIndex,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TabBar(
                            onTap: (index) => setState(() => _selectedTabIndex = index),
                            labelColor: Colors.blue.shade700,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blue.shade700,
                            tabs: const [
                              Tab(text: 'Profile'),
                              Tab(text: 'Station Info'),
                              Tab(text: 'Location'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 380,
                            child: TabBarView(
                              children: [
                                _buildEditableProfileForm(),
                                _buildEditableStationForm(),
                                _buildLocationForm(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
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

  Widget _buildKycBanner(String status) {
    if (status == 'approved') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, color: Colors.green.shade600),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Business Permit Verified. Station is active.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber.shade700,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                "Action Required",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Your station is currently hidden from customers. Upload your Business Permit to activate your account.",
            style: TextStyle(color: Colors.black87),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text(
              "UPLOAD PERMIT",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableProfileForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            _buildInputField(
              controller: _fullNameController,
              label: 'Owner Name',
              hint: 'Enter your full name',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: 'Enter contact phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _businessNameController,
              label: 'Station Name',
              hint: 'Enter station name',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _stationAddressController,
              label: 'Station Address',
              hint: 'Enter station address',
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableStationForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            _buildInputField(
              controller: _businessNameController,
              label: 'Business Name',
              hint: 'Your station name',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _stationAddressController,
              label: 'Station Address',
              hint: 'Full address for customers',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _emailController,
              label: 'Email',
              hint: 'Your contact email',
              readOnly: true,
              backgroundColor: Colors.grey.shade100,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                'Add your station location so customers can find you on the map.',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _latitudeController,
              label: 'Latitude',
              hint: 'e.g., 14.0583',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _longitudeController,
              label: 'Longitude',
              hint: 'e.g., 121.0363',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.location_on),
                label: const Text('Pick from Map'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool readOnly = false,
    Color? backgroundColor,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: readOnly || backgroundColor != null,
        fillColor: backgroundColor ?? Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
        ),
      ),
    );
  }
}