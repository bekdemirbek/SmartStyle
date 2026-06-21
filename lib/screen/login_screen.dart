import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'email_verification_page.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
      'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=1400&q=80';

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
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Lütfen e-posta ve şifre alanlarını doldur.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await credential.user?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;

      if (user != null && user.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      var message = "Giriş yapılırken bir hata oluştu.";
      if (e.code == 'user-not-found') {
        message = "Bu e-posta ile kayıtlı kullanıcı bulunamadı.";
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = "E-posta veya şifre hatalı.";
      } else if (e.code == 'invalid-email') {
        message = "Geçersiz e-posta adresi.";
      } else if (e.code == 'user-disabled') {
        message = "Bu hesap devre dışı bırakılmış.";
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

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar("Şifre sıfırlama için önce e-posta adresini yaz.");
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _showSnackBar("Şifre sıfırlama bağlantısı e-posta adresine gönderildi.");
    } on FirebaseAuthException catch (e) {
      var message = "Şifre sıfırlama bağlantısı gönderilemedi.";
      if (e.code == 'invalid-email') {
        message = "Geçerli bir e-posta adresi gir.";
      } else if (e.code == 'user-not-found') {
        message = "Bu e-posta ile kayıtlı kullanıcı bulunamadı.";
      }
      if (!mounted) return;
      _showSnackBar(message);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      UserCredential credential;

      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        credential = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleSignIn = GoogleSignIn.instance;
        await googleSignIn.initialize();
        final googleUser = await googleSignIn.authenticate();
        final googleAuth = googleUser.authentication;
        final authCredential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        credential = await FirebaseAuth.instance.signInWithCredential(
          authCredential,
        );
      }

      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Google kullanıcı bilgisi alınamadı.',
        );
      }

      final needsGender = await _saveGoogleUserProfile(user);

      if (!mounted) return;
      if (needsGender) {
        await _promptForGender(user);
        if (!mounted) return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showSnackBar(_googleErrorMessage(e.code));
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnackBar(_firebaseGoogleErrorMessage(e.code));
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Google ile giriş yapılamadı. Lütfen tekrar dene.");
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _saveGoogleUserProfile(User user) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snapshot = await userRef.get();
    final existingGender = snapshot.data()?['cinsiyet'];
    final data = <String, dynamic>{
      'kullanici_id': user.uid,
      'ad_soyad': user.displayName ?? user.email?.split('@').first ?? '',
      'e_posta': user.email ?? '',
      'profile_image_url': user.photoURL,
      'auth_provider': 'google',
      'last_login_at': FieldValue.serverTimestamp(),
    };
    if (!snapshot.exists) {
      data['created_at'] = FieldValue.serverTimestamp();
    }
    await userRef.set(data, SetOptions(merge: true));
    return existingGender == null;
  }

  Future<void> _promptForGender(User user) async {
    bool? selectedGender;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text("Cinsiyet seçimi"),
                content: DropdownButtonFormField<bool>(
                  value: selectedGender,
                  decoration: const InputDecoration(
                    labelText: "Cinsiyet",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: true, child: Text("Erkek")),
                    DropdownMenuItem(value: false, child: Text("Kadın")),
                  ],
                  onChanged: isSaving
                      ? null
                      : (value) {
                          setDialogState(() => selectedGender = value);
                        },
                ),
                actions: [
                  TextButton(
                    onPressed: selectedGender == null || isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .set({
                                  'cinsiyet': selectedGender,
                                }, SetOptions(merge: true));
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Devam et"),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _googleErrorMessage(GoogleSignInExceptionCode code) {
    if (code == GoogleSignInExceptionCode.clientConfigurationError ||
        code == GoogleSignInExceptionCode.providerConfigurationError) {
      return "Google giriş ayarları eksik görünüyor. Firebase Console ayarlarını kontrol et.";
    }
    if (code == GoogleSignInExceptionCode.uiUnavailable) {
      return "Google giriş ekranı açılamadı.";
    }
    return "Google ile giriş yapılamadı. Lütfen tekrar dene.";
  }

  String _firebaseGoogleErrorMessage(String code) {
    if (code == 'account-exists-with-different-credential') {
      return "Bu e-posta farklı bir giriş yöntemiyle kayıtlı.";
    }
    if (code == 'popup-closed-by-user' || code == 'cancelled-popup-request') {
      return "Google giriş penceresi kapatıldı.";
    }
    if (code == 'operation-not-allowed') {
      return "Firebase Console’da Google giriş yöntemi aktif değil.";
    }
    return "Google ile giriş yapılamadı. Lütfen tekrar dene.";
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
                  Color(0xE60A0D12),
                  Color(0xCC10151D),
                  Color(0xE6101218),
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
                          const SizedBox(height: 2),
                          _buildBrand(),
                          const SizedBox(height: 24),
                          _buildLoginCard(),
                          const SizedBox(height: 18),
                          _buildFooter(),
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

  Widget _buildBrand() {
    return Column(
      children: [
        Transform.translate(
          offset: const Offset(0, -14),
          child: Image.asset(
            _logoAsset,
            width: 112,
            height: 112,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "SmartStyle",
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 1.02,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Akıllı Stil Asistanınız",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _gold1.withOpacity(0.95),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.22),
                _panelFill,
                const Color(0xAA252A32),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                controller: _emailController,
                hint: "E-posta adresi",
                icon: Icons.mail_outline_rounded,
              ),
              const SizedBox(height: 18),
              _buildTextField(
                controller: _passwordController,
                hint: "Şifre",
                icon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 24),
              _buildGoldButton(
                label: "Giriş Yap",
                onPressed: _isLoading ? null : _loginUser,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading ? null : _sendPasswordReset,
                child: Text(
                  "Şifremi unuttum",
                  style: TextStyle(
                    color: _gold1.withOpacity(0.95),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildDividerLabel("veya"),
              const SizedBox(height: 18),
              _buildGoogleButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Hesabın yok mu? ",
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
        GestureDetector(
          onTap: _isLoading
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
          child: const Text(
            "Kayıt Ol",
            style: TextStyle(
              color: _gold1,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDividerLabel(String text) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: Colors.white24)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: Colors.white24)),
      ],
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
                  style: TextStyle(
                    color: Color(0xFF16120C),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.15),
              const Color(0xCC1A202A),
              Colors.white.withOpacity(0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: OutlinedButton(
          onPressed: _isLoading ? null : _signInWithGoogle,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _googleBadge(),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  "Google ile devam et",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _googleBadge() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const _GoogleGLogo(size: 23),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.16),
            const Color(0xDD151B25),
            const Color(0xDD0F151E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _gold2.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
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
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _gold2.withOpacity(0.85), width: 1.3),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide(color: _gold1, width: 1.7),
          ),
        ),
      ),
    );
  }
}

class _GoogleGLogo extends StatelessWidget {
  const _GoogleGLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GoogleGLogoPainter(),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.18;
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = strokeWidth;

    void drawArc(Color color, double start, double sweep) {
      paint.color = color;
      canvas.drawArc(arcRect, start, sweep, false, paint);
    }

    drawArc(const Color(0xFF4285F4), -0.18 * math.pi, 0.58 * math.pi);
    drawArc(const Color(0xFF34A853), 0.40 * math.pi, 0.35 * math.pi);
    drawArc(const Color(0xFFFBBC05), 0.75 * math.pi, 0.44 * math.pi);
    drawArc(const Color(0xFFEA4335), 1.19 * math.pi, 0.56 * math.pi);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = strokeWidth;
    final y = size.height * 0.50;
    canvas.drawLine(
      Offset(size.width * 0.52, y),
      Offset(size.width * 0.92, y),
      barPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, y),
      Offset(size.width * 0.74, size.height * 0.67),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
