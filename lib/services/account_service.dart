import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/membership.dart';
import 'supabase_service.dart';

/// A failure worded for the person using the app.
class AccountException implements Exception {
  const AccountException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Same rule as registration and password reset (registration_screen.dart).
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Enter a new password';
  if (password.length < 8) return 'Password must be at least 8 characters';
  return null;
}

enum DeletionMode {
  /// Customers delete their own account straight away.
  selfService,

  /// Station owners, drivers and admins are tied to association records, so
  /// they ask and WASA admin completes it (supabase/functions/delete-account).
  request,
}

DeletionMode deletionModeFor(AppRole? role) =>
    role == null || role == AppRole.publicConsumer ? DeletionMode.selfService : DeletionMode.request;

/// Mirrors `account_deletion_requests` (supabase/patch_account_lifecycle.sql).
class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.id,
    required this.profileId,
    this.reason,
    required this.requestedAt,
    this.fullName,
  });

  final String id;
  final String profileId;
  final String? reason;
  final DateTime requestedAt;

  /// Only filled for the admin list.
  final String? fullName;

  factory AccountDeletionRequest.fromMap(Map<String, dynamic> map) {
    return AccountDeletionRequest(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      reason: map['reason'] as String?,
      requestedAt: DateTime.parse(map['requested_at'] as String),
      fullName: map['profiles']?['full_name'] as String?,
    );
  }
}

/// Password changes and account deletion for the signed-in user.
class AccountService {
  AccountService(this._supabase);

  final SupabaseService _supabase;

  SupabaseClient get _client => _supabase.client;

  /// Confirms [current] by signing in with it before setting [next], so a
  /// phone left unlocked and signed in can't have its password changed.
  Future<void> changePassword({required String current, required String next}) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const AccountException('Sign in again to change your password.');
    if (current == next) throw const AccountException('Choose a password different from your current one.');
    try {
      await _client.auth.signInWithPassword(email: email, password: current);
    } on AuthException {
      throw const AccountException('Your current password is incorrect.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: next));
    } on AuthException catch (e) {
      throw AccountException(e.message);
    }
  }

  Future<void> deleteMyAccount() => _invokeDelete(const {});

  Future<void> deleteAccountAsAdmin(String profileId) => _invokeDelete({'profile_id': profileId});

  Future<void> _invokeDelete(Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke('delete-account', body: body);
    } on FunctionException catch (e) {
      // The function's messages (e.g. "1 order(s) still in progress...") are
      // written to be shown as they are.
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Could not delete the account (error ${e.status}).';
      throw AccountException(message);
    }
  }

  Future<AccountDeletionRequest?> fetchMyPendingRequest() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('account_deletion_requests')
        .select('id, profile_id, reason, requested_at')
        .eq('profile_id', userId)
        .eq('status', 'pending')
        .maybeSingle();
    return row == null ? null : AccountDeletionRequest.fromMap(row);
  }

  Future<void> requestDeletion(String? reason) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AccountException('Sign in again to send the request.');
    final trimmed = reason?.trim();
    await _client.from('account_deletion_requests').insert({
      'profile_id': userId,
      'reason': trimmed == null || trimmed.isEmpty ? null : trimmed,
    });
  }

  /// Withdraws a request -- the requester's own, or an admin declining one.
  Future<void> cancelDeletionRequest(String requestId) {
    return _client.from('account_deletion_requests').update({'status': 'cancelled'}).eq('id', requestId);
  }

  /// Admin: every pending request, oldest first.
  Future<List<AccountDeletionRequest>> fetchPendingRequests() async {
    final rows = await _client
        .from('account_deletion_requests')
        .select('id, profile_id, reason, requested_at, profiles(full_name)')
        .eq('status', 'pending')
        .order('requested_at');
    return List<Map<String, dynamic>>.from(rows).map(AccountDeletionRequest.fromMap).toList();
  }
}
