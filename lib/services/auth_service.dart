import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/membership.dart';
import 'supabase_service.dart';

/// Handles Supabase Auth sign in/up/out and resolving the signed-in user's
/// membership (role + station scope). Replaces the old pattern of reading a
/// flat `user_profiles.role` string -- role is now a `memberships` row
/// (supabase/migrations/0003_memberships.sql), and real enforcement lives in
/// RLS, not in this class. This class only provides UX-level routing info.
class AuthService {
  AuthService(this._supabase);

  final SupabaseService _supabase;

  Stream<AuthState> get authStateChanges => _supabase.client.auth.onAuthStateChange;

  User? get currentUser => _supabase.client.auth.currentUser;

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _supabase.client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({required String email, required String password}) {
    return _supabase.client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() => _supabase.client.auth.signOut();

  /// Returns the current user's active membership, or null if they have none
  /// (e.g. a legacy/unassigned account -- public consumers never have one).
  Future<Membership?> fetchCurrentMembership() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await _supabase.client
        .from('memberships')
        .select()
        .eq('profile_id', user.id)
        .eq('status', 'active')
        .maybeSingle();

    if (row == null) return null;
    return Membership.fromMap(row);
  }

  /// The status of the current user's membership row regardless of whether
  /// it's active (unlike [fetchCurrentMembership], which filters
  /// status = 'active' and so can't distinguish "no membership at all" from
  /// "membership exists but was suspended/revoked by an admin"). Null means
  /// no membership row exists at all.
  Future<String?> fetchRawMembershipStatus() async {
    final user = currentUser;
    if (user == null) return null;

    final rows = await _supabase.client.from('memberships').select('status').eq('profile_id', user.id).limit(1);
    if (rows.isEmpty) return null;
    return rows.first['status'] as String?;
  }

  Future<void> updateProfile({required String fullName, String? phoneNumber}) async {
    final user = currentUser;
    if (user == null) return;
    await _supabase.client.from('profiles').update({
      'full_name': fullName,
      'phone_number': ?phoneNumber,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);
  }
}
