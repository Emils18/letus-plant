import 'package:supabase_flutter/supabase_flutter.dart';

class AuthResult {
  final String? error;
  final String? role;

  const AuthResult({this.error, this.role});

  bool get success => error == null;
}

class AuthService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );

      if (response.user == null) {
        return const AuthResult(error: 'Invalid email or password.');
      }

      final role = await getCurrentUserRole();
      if (role == null) {
        await supabase.auth.signOut();
        return const AuthResult(error: 'Profile not found. Contact admin.');
      }

      final normalizedRole = role.toLowerCase();
      if (!['buyer', 'farmer', 'admin'].contains(normalizedRole)) {
        await supabase.auth.signOut();
        return const AuthResult(error: 'Invalid role. Contact admin.');
      }

      return AuthResult(role: normalizedRole);
    } on AuthException catch (e) {
      return AuthResult(error: _friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult(error: 'Unexpected error. Try again.');
    }
  }

  Future<String?> registerBuyer({
    required String fullName,
    required String email,
    required String password,
  }) async {
    return registerUser(fullName: fullName, email: email, password: password, role: 'buyer');
  }

  Future<String?> registerFarmer({
    required String fullName,
    required String email,
    required String password,
  }) async {
    return registerUser(fullName: fullName, email: email, password: password, role: 'farmer');
  }

  Future<String?> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    final cleanName = fullName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    final cleanRole = role.trim().toLowerCase();

    if (!['buyer', 'farmer'].contains(cleanRole)) return 'Invalid role.';
    if (cleanName.isEmpty) return 'Full name required.';
    if (!cleanEmail.contains('@')) return 'Valid email required.';
    if (cleanPassword.length < 6) return 'Password too short.';

    try {
      final response = await supabase.auth.signUp(
        email: cleanEmail,
        password: cleanPassword,
        data: {'full_name': cleanName, 'role': cleanRole},
      );

      if (response.user == null) return 'Registration failed.';

      await supabase.from('users').upsert({
        'id': response.user!.id,
        'full_name': cleanName,
        'email': cleanEmail,
        'role': cleanRole,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');

      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } on PostgrestException catch (e) {
      return 'Database error: ${e.message}';
    } catch (e) {
      return 'Unexpected registration error.';
    }
  }

  Future<String?> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim();
    try {
      await supabase.auth.resetPasswordForEmail(cleanEmail);
      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } catch (e) {
      return 'Unexpected password reset error.';
    }
  }

  Future<String?> getCurrentUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final profile = await supabase
        .from('users')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['role']?.toString().toLowerCase();
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    return await supabase
        .from('users')
        .select('id, full_name, email, role, created_at')
        .eq('id', user.id)
        .maybeSingle();
  }

  Future<void> signOut() async {
    await supabase.auth.signOut(scope: SignOutScope.local);
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) return 'Invalid email or password.';
    if (lower.contains('already registered')) return 'Email already registered.';
    return message;
  }
}