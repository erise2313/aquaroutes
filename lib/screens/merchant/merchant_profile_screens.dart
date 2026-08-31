import 'package:aquaroute/screens/merchant/location_picker_screen.dart';
import 'package:aquaroute/screens/merchant/permit_vault_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/photo_service.dart';
import '../../services/supabase_service.dart';

/// Builds the `profiles` table update payload (trimmed). Split from
/// [buildStationPayload] since profile identity and station business data
/// now live in separate tables (profiles vs. water_stations).
Map<String, dynamic> buildProfilePayload({required String fullName, required String phoneNumber}) {
  return {
    'full_name': fullName.trim(),
    'phone_number': phoneNumber.trim(),
  };
}

/// Builds the `water_stations` table update payload (trimmed).
Map<String, dynamic> buildStationPayload({required String stationName, required String stationAddress}) {
  return {
    'station_name': stationName.trim(),
    'station_address': stationAddress.trim(),
  };
}

class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  final supabase = Supabase.instance.client;
  final _photoService = PhotoService(SupabaseService.instance);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLoggingOut = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingStationPhoto = false;
  String? _stationId;
  String? _avatarUrl;
  String? _stationPhotoUrl;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _stationData;
  bool _isAcceptingOrders = true;
  final Set<String> _offeredJugTypes = {};
  bool _offersJugExchange = false;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _stationNameController = TextEditingController();
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
    _stationNameController.dispose();
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
        // AuthGate (the app's root widget) reacts to the resulting
        // auth-state change and shows LoginScreen itself -- just pop back
        // to reveal it, don't push a new LoginScreen route on top of it.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _fetchProfileData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("User not authenticated");

      final profile = await supabase.from('profiles').select().eq('id', userId).maybeSingle();
      final station = await supabase.from('water_stations').select().eq('owner_profile_id', userId).maybeSingle();

      if (mounted) {
        setState(() {
          _profileData = profile;
          _stationData = station;
          _stationId = station?['id'] as String?;
          _avatarUrl = profile?['avatar_url'] as String?;
          _stationPhotoUrl = station?['photo_url'] as String?;
          _fullNameController.text = (profile?['full_name'] as String?) ?? '';
          _phoneController.text = (profile?['phone_number'] as String?) ?? '';
          _stationNameController.text = (station?['station_name'] as String?) ?? '';
          _stationAddressController.text = (station?['station_address'] as String?) ?? '';
          _emailController.text = supabase.auth.currentUser?.email ?? '';
          _latitudeController.text = (station?['latitude'] as num?)?.toString() ?? '';
          _longitudeController.text = (station?['longitude'] as num?)?.toString() ?? '';
          _isAcceptingOrders = station?['accepts_new_orders'] as bool? ?? true;
          _offeredJugTypes
            ..clear()
            ..addAll(List<String>.from(station?['offered_jug_types'] as List? ?? const []));
          _offersJugExchange = station?['offers_jug_exchange'] as bool? ?? false;
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
          initialLatitude: double.tryParse(_latitudeController.text) ?? 14.3868,
          initialLongitude: double.tryParse(_longitudeController.text) ?? 120.8817,
          initialStationName: _stationNameController.text,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _latitudeController.text = result['latitude'].toString();
        _longitudeController.text = result['longitude'].toString();
        _stationNameController.text = result['station_name'];
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'jpg';

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await _photoService.uploadAvatar(profileId: userId, bytes: picked.bytes!, fileExtension: extension);
      await supabase.from('profiles').update({'avatar_url': url, 'updated_at': DateTime.now().toIso8601String()}).eq('id', userId);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _pickAndUploadStationPhoto() async {
    if (_stationId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'jpg';

    setState(() => _isUploadingStationPhoto = true);
    try {
      final url = await _photoService.uploadStationPhoto(stationId: _stationId!, bytes: picked.bytes!, fileExtension: extension);
      await supabase.from('water_stations').update({'photo_url': url}).eq('id', _stationId!);
      if (mounted) setState(() => _stationPhotoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingStationPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || _stationId == null) return;

    setState(() => _isSaving = true);

    try {
      await supabase.from('profiles').update({
        ...buildProfilePayload(fullName: _fullNameController.text, phoneNumber: _phoneController.text),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      final stationPayload = buildStationPayload(
        stationName: _stationNameController.text,
        stationAddress: _stationAddressController.text,
      );

      final lat = double.tryParse(_latitudeController.text);
      final lng = double.tryParse(_longitudeController.text);
      if (lat != null && lng != null) {
        stationPayload['latitude'] = lat;
        stationPayload['longitude'] = lng;
      }
      stationPayload['accepts_new_orders'] = _isAcceptingOrders;
      stationPayload['offered_jug_types'] = _offeredJugTypes.toList();
      stationPayload['offers_jug_exchange'] = _offersJugExchange;

      await supabase.from('water_stations').update(stationPayload).eq('id', _stationId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile and station details updated successfully!')),
        );
      }
      await _fetchProfileData();
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
      appBar: AppBar(
        title: Text(
          "Station Profile",
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        ),
        elevation: 0,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    final String ownerName = _profileData?['full_name'] ?? "Unknown Owner";
    final String stationName = _stationData?['station_name'] ?? "Unnamed Station";
    final String email = supabase.auth.currentUser?.email ?? "";
    final bool isAccredited = _stationData?['is_accredited'] as bool? ?? false;

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
                          GestureDetector(
                            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                                  child: _isUploadingAvatar
                                      ? const CircularProgressIndicator()
                                      : (_avatarUrl == null ? const Icon(Icons.storefront, size: 35, color: Colors.blue) : null),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                                ),
                              ],
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
                                  "$stationName\n$email",
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
                    _buildAccreditationBanner(isAccredited),
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

  Widget _buildAccreditationBanner(bool isAccredited) {
    if (isAccredited) {
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
                "WASA Accredited. Your station is visible to the public.",
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
            "Your station isn't accredited yet. Upload your permits so WASA can review them.",
            style: TextStyle(color: Colors.black87),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PermitVaultScreen())),
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
              "OPEN PERMIT VAULT",
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: _isUploadingStationPhoto ? null : _pickAndUploadStationPhoto,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  image: _stationPhotoUrl != null
                      ? DecorationImage(image: NetworkImage(_stationPhotoUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: _isUploadingStationPhoto
                    ? const Center(child: CircularProgressIndicator())
                    : (_stationPhotoUrl == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade700),
                                const SizedBox(height: 4),
                                Text('Add Station Photo', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                              ],
                            ),
                          )
                        : Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          )),
              ),
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _stationNameController,
              label: 'Station Name',
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isAcceptingOrders,
              onChanged: (v) => setState(() => _isAcceptingOrders = v),
              title: const Text('Accepting Orders', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Turn off when closed -- customers will see this station as closed and can\'t order.', style: TextStyle(fontSize: 12)),
            ),
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Container Options', style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Slim 5-gal'),
                  selected: _offeredJugTypes.contains('slim_5gal'),
                  onSelected: (v) => setState(() => v ? _offeredJugTypes.add('slim_5gal') : _offeredJugTypes.remove('slim_5gal')),
                ),
                FilterChip(
                  label: const Text('Round 5-gal'),
                  selected: _offeredJugTypes.contains('round_5gal'),
                  onSelected: (v) => setState(() => v ? _offeredJugTypes.add('round_5gal') : _offeredJugTypes.remove('round_5gal')),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _offersJugExchange,
              onChanged: (v) => setState(() => _offersJugExchange = v),
              title: const Text('Accepts Jug Exchange', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Customers can bring an empty jug of any brand and swap it for a full one.', style: TextStyle(fontSize: 12)),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
              hint: 'e.g., 14.3868',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _longitudeController,
              label: 'Longitude',
              hint: 'e.g., 120.8817',
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
