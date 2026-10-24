import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../driver/driver_onboarding_screen.dart';
import '../driver/driver_radar_screen.dart';
import '../rider/rider_home_screen.dart';
import 'otp_verification_sheet.dart';

/// Rafik (رفيق) — Universal Authentication & Intake Screen
/// Dynamic Male (Midnight Jet Black) vs Female (Rose Obsidian Berry) palettes,
/// Instant English/Arabic language toggle with RTL, OLED Night mode,
/// Log In & Register views with pure Supabase Auth (Phone OTP, Email, Google Sign-In).
class AuthScreen extends StatefulWidget {
  final bool initialIsDriver;
  final String initialRole;

  const AuthScreen({
    super.key,
    this.initialIsDriver = false,
    this.initialRole = 'rider',
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Navigation & Role State
  late bool _isDriver;
  bool _isLoginMode = false; // Toggle between Log In and Register
  bool _isEmailMode = false; // Phone OTP vs Email/Password
  bool _isLoading = false;
  bool _isArabic = false; // English by default, Arabic toggle

  // User Profile Inputs
  String _selectedGender = 'female'; // 'female' or 'male'
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isDriver = widget.initialIsDriver || widget.initialRole == 'driver';
    _loadSavedPreferences();
  }

  Future<void> _loadSavedPreferences() async {
    final lang = await PersistentStorage.getLanguage();
    if (mounted) {
      setState(() {
        _isArabic = (lang == 'ar');
      });
    }
  }

  void _toggleLanguage() async {
    final newLang = !_isArabic;
    setState(() => _isArabic = newLang);
    await PersistentStorage.setLanguage(newLang ? 'ar' : 'en');
  }

  // ================= THEME TOKENS BASED ON GENDER =================
  Color get _currentBg {
    return _selectedGender == 'male'
        ? const Color(0xFF000000) // Pure Midnight Black for Male
        : const Color(0xFF12080C); // Obsidian Berry for Female
  }

  Color get _currentCardBg {
    return _selectedGender == 'male'
        ? const Color(0xFF121212)
        : const Color(0xFF1A0D12);
  }

  Color get _currentBorder {
    return _selectedGender == 'male'
        ? const Color(0xFF262626)
        : const Color(0xFF2C151F);
  }

  Color get _currentAccent {
    return _selectedGender == 'male'
        ? const Color(0xFF3B82F6) // Titanium Ice Blue for Male
        : AppTheme.roseGold; // Rose Gold for Female
  }

  Color get _currentAccentLight {
    return _selectedGender == 'male'
        ? const Color(0xFF93C5FD)
        : AppTheme.roseGoldLight;
  }

  // ================= SUPABASE AUTHENTICATION =================

  /// Formats Egyptian phone number to E.164 (+20...)
  String _formatPhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('01')) {
      p = '+20${p.substring(1)}';
    } else if (p.startsWith('201')) {
      p = '+$p';
    } else if (!p.startsWith('+')) {
      p = '+20$p';
    }
    return p;
  }

  /// Sends Phone OTP via Supabase Auth
  Future<void> _handlePhoneAuth() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      _showSnackbar(_isArabic ? 'يرجى إدخال رقم هاتف مصري صحيح' : 'Please enter a valid Egyptian phone number');
      return;
    }

    final formattedPhone = _formatPhone(phone);
    final name = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Rafik User';
    final role = _isDriver ? 'driver' : 'rider';

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: formattedPhone,
        data: {
          'full_name': name,
          'role': role,
          'gender': _selectedGender,
        },
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => OtpVerificationSheet(
          phoneNumber: formattedPhone,
          userName: name,
          role: role,
          gender: _selectedGender,
          onVerified: _navigateAfterAuth,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackbar('SMS OTP Error: $e');
    }
  }

  /// Email & Password Sign Up / Sign In
  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Rafik User';
    final role = _isDriver ? 'driver' : 'rider';

    if (email.isEmpty || !email.contains('@')) {
      _showSnackbar(_isArabic ? 'يرجى إدخال بريد إلكتروني صحيح' : 'Please enter a valid email address');
      return;
    }
    if (password.length < 6) {
      _showSnackbar(_isArabic ? 'كلمة المرور يجب أن لا تقل عن 6 أحرف' : 'Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      if (_isLoginMode) {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } else {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'role': role,
            'gender': _selectedGender,
          },
        );
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _navigateAfterAuth();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Auth Error: $e');
      }
    }
  }

  /// Google OAuth Sign In
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'rafik://login-callback',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Google Sign-In Notice: $e');
      }
    }
  }

  /// Debug Mode Instant Bypass (Seed Test Account)
  Future<void> _handleDebugBypass() async {
    if (!kDebugMode) return;
    setState(() => _isLoading = true);

    final role = _isDriver ? 'driver' : 'rider';
    final email = '${role}_${_selectedGender}_dev@rafik.internal';

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: 'DevPassword123!',
      );
    } catch (_) {
      // If dev account does not exist, sign up
      try {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: 'DevPassword123!',
          data: {
            'full_name': 'Dev ${role.toUpperCase()}',
            'role': role,
            'gender': _selectedGender,
          },
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _navigateAfterAuth();
    }
  }

  /// Post-Authentication Router
  Future<void> _navigateAfterAuth() async {
    if (!mounted) return;

    if (_isDriver) {
      // Check if driver has an approved or submitted application
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final driverRow = await Supabase.instance.client
            .from('drivers')
            .select('status')
            .eq('user_id', user.id)
            .maybeSingle();

        if (!mounted) return;
        if (driverRow != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverRadarScreen()),
          );
          return;
        }
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOnboardingScreen(
            driverGender: _selectedGender,
            isUperGirlEnrolled: _selectedGender == 'female',
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
      );
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.berryCore,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _currentBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Bar: Brand, Language Toggle & Mode Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PillBadge(
                      label: _isDriver
                          ? (_isArabic ? 'كابتن رَفِيق' : 'RAFIK CAPTAIN')
                          : (_isArabic ? 'رَاكِب رَفِيق' : 'RAFIK RIDER'),
                      variant: _selectedGender == 'male'
                          ? PillBadgeVariant.dark
                          : PillBadgeVariant.roseGold,
                    ),

                    // Language Toggle Button
                    InkWell(
                      onTap: _toggleLanguage,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _currentCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _currentBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.language, size: 16, color: _currentAccentLight),
                            const SizedBox(width: 6),
                            Text(
                              _isArabic ? 'English' : 'عربي',
                              style: TextStyle(
                                color: _currentAccentLight,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Hero Branding Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _currentCardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _currentBorder),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _currentAccent.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: _currentAccent, width: 2),
                        ),
                        child: Center(
                          child: Icon(
                            _isDriver ? Icons.local_taxi : Icons.location_on,
                            color: _currentAccentLight,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'RAFIK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                      Text(
                        _isArabic ? 'المنظومة الذكية للتنقل الآمن في مصر' : 'SMART MOBILITY FOR GREATER CAIRO',
                        style: TextStyle(
                          color: _currentAccentLight,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Gender Toggle (Determines UI Palette & Rafik Girl Eligibility)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedGender = 'female'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedGender == 'female'
                                ? AppTheme.roseGold.withOpacity(0.2)
                                : _currentCardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedGender == 'female'
                                  ? AppTheme.roseGold
                                  : _currentBorder,
                              width: _selectedGender == 'female' ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.female,
                                color: _selectedGender == 'female' ? AppTheme.roseGold : Colors.white54,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isArabic ? 'أنثى (وردي)' : 'Female (Rose)',
                                style: TextStyle(
                                  color: _selectedGender == 'female' ? AppTheme.roseGold : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedGender = 'male'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedGender == 'male'
                                ? const Color(0xFF3B82F6).withOpacity(0.2)
                                : _currentCardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedGender == 'male'
                                  ? const Color(0xFF3B82F6)
                                  : _currentBorder,
                              width: _selectedGender == 'male' ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.male,
                                color: _selectedGender == 'male' ? const Color(0xFF3B82F6) : Colors.white54,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isArabic ? 'ذكر (أسود)' : 'Male (Black)',
                                style: TextStyle(
                                  color: _selectedGender == 'male' ? const Color(0xFF93C5FD) : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Auth Mode Tabs: Log In vs Register
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _currentCardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _currentBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isLoginMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isLoginMode ? _currentAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                _isArabic ? 'إنشاء حساب جديد' : 'Create Account',
                                style: TextStyle(
                                  color: !_isLoginMode ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isLoginMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _isLoginMode ? _currentAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                _isArabic ? 'تسجيل الدخول' : 'Sign In',
                                style: TextStyle(
                                  color: _isLoginMode ? Colors.black : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Input Fields
                if (!_isLoginMode) ...[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _isArabic ? 'الاسم بالكامل' : 'Full Name',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.person_outline, color: _currentAccentLight),
                      filled: true,
                      fillColor: _currentCardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentAccent, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (!_isEmailMode) ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _isArabic ? 'رقم الهاتف (01xxxxxxxxx)' : 'Phone Number (01xxxxxxxxx)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.phone_outlined, color: _currentAccentLight),
                      filled: true,
                      fillColor: _currentCardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentAccent, width: 2)),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _isArabic ? 'البريد الإلكتروني' : 'Email Address',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.email_outlined, color: _currentAccentLight),
                      filled: true,
                      fillColor: _currentCardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentAccent, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _isArabic ? 'كلمة المرور' : 'Password',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.lock_outline, color: _currentAccentLight),
                      filled: true,
                      fillColor: _currentCardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _currentAccent, width: 2)),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Switch between Phone OTP and Email Auth
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _isEmailMode = !_isEmailMode),
                    child: Text(
                      _isEmailMode
                          ? (_isArabic ? 'استخدم رقم الهاتف ورمز التحقق' : 'Use Phone & SMS OTP instead')
                          : (_isArabic ? 'استخدم البريد وكلمة المرور' : 'Use Email & Password instead'),
                      style: TextStyle(color: _currentAccentLight, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Main Action Button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (_isEmailMode ? _handleEmailAuth : _handlePhoneAuth),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(
                            _isLoginMode
                                ? (_isArabic ? 'دخول إلى الحساب' : 'Sign In')
                                : (_isArabic ? 'إرسال رمز التأكيد والمتابعة' : 'Continue with Verification'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Google Sign In Button
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.white),
                    label: Text(
                      _isArabic ? 'المتابعة بحساب Google' : 'Continue with Google',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _currentBorder),
                      backgroundColor: _currentCardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

                // Debug Test Bypass Button (Strictly in kDebugMode)
                if (kDebugMode) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _handleDebugBypass,
                    icon: const Icon(Icons.developer_mode, size: 16, color: Colors.white38),
                    label: Text(
                      'Dev Seed Bypass (${_isDriver ? 'Driver' : 'Rider'} $_selectedGender)',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
