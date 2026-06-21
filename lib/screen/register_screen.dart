import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'email_verification_page.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool? _gender;
  bool _isLoading = false;
  bool _obscurePassword = true;

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  static const Color _gold1 = Color(0xFFF6E2A4);
  static const Color _gold2 = Color(0xFFD5B060);
  static const Color _gold3 = Color(0xFF9B7331);
  static const Color _panelBorder = Color(0xCCDFC27A);
  static const Color _panelFill = Color(0xAA1A1F27);
  static const String _logoAsset = 'assets/images/smartstyle_logo.png';
  static const String _backgroundImage =
      'https://images.unsplash.com/photo-1523381210434-271e8be1f52b?auto=format&fit=crop&w=1400&q=80';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _registerUser() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || _gender == null) {
      _showSnackBar("Lütfen tüm alanları doldur.");
      return;
    }

    if (password.length < 6) {
      _showSnackBar("Şifre en az 6 karakter olmalı.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user == null) {
        throw Exception("Kullanıcı oluşturulamadı.");
      }

      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'kullanici_id': user.uid,
        'ad_soyad': name,
        'e_posta': email,
        'cinsiyet': _gender,
      });
      await user.sendEmailVerification();

      if (!mounted) return;
      _showSnackBar("Kayıt başarılı. Doğrulama e-postası gönderildi.");
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      var message = "Kayıt olurken bir hata oluştu.";
      if (e.code == 'email-already-in-use') {
        message = "Bu e-posta adresi zaten kullanımda.";
      } else if (e.code == 'invalid-email') {
        message = "Geçersiz e-posta adresi.";
      } else if (e.code == 'weak-password') {
        message = "Şifre çok zayıf.";
      }
      if (!mounted) return;
      _showSnackBar(message);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Hata: $e");
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(_backgroundImage),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xEA0A0D12),
                  Color(0xCC10151D),
                  Color(0xEA0F1218),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideUp,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Image.asset(
                            _logoAsset,
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            "Hesap Oluştur",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 31,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "SmartStyle ile stilini daha akıllı yönet",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _gold1.withOpacity(0.95),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _buildRegisterCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: _panelFill,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: _panelBorder, width: 1.8),
            boxShadow: [
              BoxShadow(
                color: _gold2.withOpacity(0.14),
                blurRadius: 30,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              _buildTextField(
                controller: _nameController,
                hint: "Ad soyad",
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 14),
              _buildGenderDropdown(),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _emailController,
                hint: "E-posta adresi",
                icon: Icons.mail_outline_rounded,
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _passwordController,
                hint: "Şifre",
                icon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 20),
              _buildGoldButton(
                label: "Kayıt Ol",
                onPressed: _isLoading ? null : _registerUser,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: Text.rich(
                  TextSpan(
                    text: "Zaten hesabın var mı? ",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    children: const [
                      TextSpan(
                        text: "Giriş Yap",
                        style: TextStyle(
                          color: _gold1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoldButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [_gold3, _gold2, _gold1, _gold2],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _gold2.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF16120C),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return DropdownButtonFormField<bool>(
      value: _gender,
      dropdownColor: const Color(0xFF212733),
      iconEnabledColor: Colors.white70,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: "Cinsiyet",
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.72),
          fontSize: 16,
        ),
        prefixIcon: const Icon(
          Icons.wc_rounded,
          color: _gold1,
          size: 21,
        ),
        filled: true,
        fillColor: const Color(0xCC111720),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _gold2.withOpacity(0.7), width: 1.3),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: _gold1, width: 1.6),
        ),
      ),
      items: const [
        DropdownMenuItem(value: true, child: Text("Erkek")),
        DropdownMenuItem(value: false, child: Text("Kadın")),
      ],
      onChanged: (value) {
        setState(() => _gender = value);
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.72),
          fontSize: 16,
        ),
        prefixIcon: Icon(icon, color: _gold1, size: 21),
        suffixIcon: isPassword
            ? IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white70,
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xCC111720),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _gold2.withOpacity(0.7), width: 1.3),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: _gold1, width: 1.6),
        ),
      ),
    );
  }
}
