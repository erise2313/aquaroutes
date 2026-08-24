import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/permit.dart';
import '../../models/worker.dart';
import '../../services/photo_service.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../services/worker_service.dart';

/// Driver profile + the Digital WASA Worker QR Badge. Clearance status is
/// read-only here -- it can only change via the worker_incidents review
/// flow (screens/merchant/worker_registry_screen.dart to file, WASA admin
/// to confirm/dismiss) or via credential approval below, never edited
/// directly by the driver.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final supabase = Supabase.instance.client;
  final _workerService = WorkerService(SupabaseService.instance);
  final _credentialService = WorkerCredentialService(SupabaseService.instance);
  final _photoService = PhotoService(SupabaseService.instance);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  Worker? _worker;
  String? _stationName;
  String? _avatarUrl;
  List<WorkerCredential> _credentials = [];

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehiclePlateController = TextEditingController();
  final TextEditingController _jugCapacityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchDriverProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _vehiclePlateController.dispose();
    _jugCapacityController.dispose();
    super.dispose();
  }

  Future<void> _fetchDriverProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await supabase.from('profiles').select('avatar_url').eq('id', userId).maybeSingle();
      final data = await supabase.from('workers').select().eq('profile_id', userId).maybeSingle();

      if (data == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final worker = Worker.fromMap(data);
      final credentials = await _credentialService.fetchWorkerCredentials(worker.id);

      String? stationName;
      if (worker.stationId != null) {
        final station = await supabase.from('water_stations').select('station_name').eq('id', worker.stationId!).maybeSingle();
        stationName = station?['station_name'] as String?;
      }

      if (mounted) {
        setState(() {
          _worker = worker;
          _stationName = stationName;
          _avatarUrl = profile?['avatar_url'] as String?;
          _credentials = credentials;
          _fullNameController.text = worker.fullName;
          _phoneController.text = worker.phoneNumber ?? '';
          _vehiclePlateController.text = worker.vehiclePlate ?? '';
          _jugCapacityController.text = worker.jugCapacity?.toString() ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching driver profile: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_worker == null) return;
    setState(() => _isSaving = true);

    try {
      await supabase.from('workers').update({
        'full_name': _fullNameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'vehicle_plate': _vehiclePlateController.text.trim(),
        'jug_capacity': int.tryParse(_jugCapacityController.text.trim()),
      }).eq('id', _worker!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver profile updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _uploadCredential(WorkerCredential credential) async {
    if (_worker == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'pdf';

    try {
      await _credentialService.uploadCredentialDocument(
        workerId: _worker!.id,
        credentialType: credential.credentialType,
        bytes: picked.bytes!,
        fileExtension: extension,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded -- pending WASA review.')),
        );
      }
      _fetchDriverProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _promptStationCode({required bool isSwitch}) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.driverSurface,
        titleTextStyle: const TextStyle(color: AppColors.driverText, fontSize: 18, fontWeight: FontWeight.bold),
        title: Text(isSwitch ? 'Switch Station' : 'Join a Station'),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.driverText),
          decoration: InputDecoration(
            labelText: 'Station Invite Code',
            labelStyle: TextStyle(color: AppColors.driverText.withValues(alpha: 0.7)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.driverText.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.driverOnDuty),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;

    try {
      await _workerService.switchStation(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Station updated successfully!'), backgroundColor: Colors.green),
        );
      }
      _fetchDriverProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().split(':').last)));
      }
    }
  }

  Future<void> _leaveStation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.driverSurface,
        titleTextStyle: const TextStyle(color: AppColors.driverText, fontSize: 18, fontWeight: FontWeight.bold),
        title: const Text('Leave Station'),
        content: Text(
          'Are you sure you want to leave $_stationName? You can join a new station anytime with an invite code.',
          style: TextStyle(color: AppColors.driverText.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.driverText.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.driverAlert),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _workerService.leaveStation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have left the station.')));
      }
      _fetchDriverProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.driverBackground,
      appBar: AppBar(
        title: const Text('Driver Profile', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.driverText)),
        backgroundColor: AppColors.driverSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: ListView(
                children: [
                  Center(child: _buildAvatar()),
                  const SizedBox(height: 24),
                  if (_worker != null) _buildClearanceBadge(_worker!),
                  const SizedBox(height: 24),
                  if (_worker != null) _buildStationSection(_worker!),
                  const SizedBox(height: 24),
                  if (_worker != null) _buildCredentialsSection(),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _fullNameController,
                    style: const TextStyle(color: AppColors.driverText),
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppColors.driverText),
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'e.g., 09123456789',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _vehiclePlateController,
                    style: const TextStyle(color: AppColors.driverText),
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Plate Number',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _jugCapacityController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.driverText),
                    decoration: const InputDecoration(
                      labelText: 'Jug Capacity',
                      labelStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.water_drop, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.driverSurface,
            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _isUploadingAvatar
                ? const CircularProgressIndicator(color: AppColors.primary)
                : (_avatarUrl == null ? const Icon(Icons.local_shipping, size: 45, color: Colors.grey) : null),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildStationSection(Worker worker) {
    final isLinked = worker.stationId != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.driverSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CURRENT STATION', style: TextStyle(color: Colors.grey, letterSpacing: 1.2, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            isLinked ? (_stationName ?? 'Unknown Station') : 'Not currently linked to a station',
            style: const TextStyle(color: AppColors.driverText, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _promptStationCode(isSwitch: isLinked),
                  child: Text(isLinked ? 'Switch Station' : 'Join a Station'),
                ),
              ),
              if (isLinked) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.flagged),
                    onPressed: _leaveStation,
                    child: const Text('Leave Station'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.driverSurface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MY CREDENTIALS', style: TextStyle(color: Colors.grey, letterSpacing: 1.2, fontSize: 12)),
          const SizedBox(height: 8),
          const Text(
            'Submit these for WASA to review and clear your account.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ..._credentials.map(_buildCredentialTile),
        ],
      ),
    );
  }

  Widget _buildCredentialTile(WorkerCredential credential) {
    final (color, label) = switch (credential.status) {
      PermitStatus.approved => (Colors.green, 'Approved'),
      PermitStatus.pendingReview => (Colors.orange, 'Pending Review'),
      PermitStatus.rejected => (Colors.red, 'Rejected'),
      PermitStatus.missing => (Colors.grey, 'Not Uploaded'),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.description, color: color),
      title: Text(workerCredentialTypeLabel(credential.credentialType), style: const TextStyle(color: AppColors.driverText)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color)),
          if (credential.status == PermitStatus.rejected && credential.rejectionReason != null && credential.rejectionReason!.isNotEmpty)
            Text('Reason: ${credential.rejectionReason}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      trailing: TextButton(
        onPressed: () => _uploadCredential(credential),
        child: Text(credential.status == PermitStatus.missing ? 'Upload' : 'Re-upload'),
      ),
    );
  }

  Widget _buildClearanceBadge(Worker worker) {
    final (color, label) = switch (worker.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING CLEARANCE'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.driverSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          const Text('GENTRI WASA WORKER BADGE', style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: worker.qrPayload ?? worker.workerCode,
              size: 160,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(worker.workerCode, style: const TextStyle(color: AppColors.driverText, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ),
        ],
      ),
    );
  }
}
