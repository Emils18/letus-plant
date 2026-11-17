import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? email; // Optional: pass email from previous screen

  const ResetPasswordScreen({super.key, this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSuccess = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showSnackBar('Please enter both passwords.', isError: true);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters.', isError: true);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final errorMessage = await _authService.updatePassword(password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (errorMessage != null) {
      _showSnackBar(errorMessage, isError: true);
      return;
    }

    setState(() => _isSuccess = true);
    _showSnackBar('Password updated successfully!');

    // Auto return to login after success
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2F6B3B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E2A1F)), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FAF7), Color(0xFFEEF2ED)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    Container(
                      height: 100,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Image.asset('assets/images/Greenguard.png', fit: BoxFit.contain),
                    ),

                    const SizedBox(height: 24),

                    const Text('Reset Password', style: TextStyle(color: Color(0xFF1E2A1F), fontSize: 32, fontWeight: FontWeight.w900)),
                    const Text('SECURE GREENGUARD ACCESS', style: TextStyle(color: Color(0xFF5DBB63), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),

                    const SizedBox(height: 48),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: _isSuccess
                              ? Column(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2F6B3B), size: 80),
                                    const SizedBox(height: 16),
                                    const Text('Password Updated!', style: TextStyle(color: Color(0xFF1E2A1F), fontSize: 22, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    const Text('You can now login with your new password.', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF757575))),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton(
                                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2F6B3B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                        child: const Text('Go to Login'),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildTextField(controller: _passwordController, hint: 'New Password', isPassword: true),
                                    const SizedBox(height: 16),
                                    _buildTextField(controller: _confirmPasswordController, hint: 'Confirm New Password', isPassword: true),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _updatePassword,
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2F6B3B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                        child: _isLoading ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3) : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        style: const TextStyle(color: Color(0xFF1E2A1F), fontWeight: FontWeight.w600),
        cursorColor: const Color(0xFF2F6B3B),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500),
          prefixIcon: Icon(Icons.lock_rounded, color: const Color(0xFF2F6B3B).withValues(alpha: 0.7)),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.grey),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }
}