import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../driver/driver_onboarding_screen.dart';
import '../driver/driver_radar_screen.dart';
import '../rider/rider_home_screen.dart';

/// Rafik (رفيق) — Universal Authentication & Intake Screen
/// Supports dynamic Male (Black) vs Female (Rose Obsidian) color palettes,
/// Instant English/Arabic language toggle, OLED Night/Dark mode,
/// Dedicated Log In & Register views, 1-Tap Google Sign-In, and instant Bypass.
class AuthScreen extends StatefulWidget {
  final bool initialIsDriver;
  const AuthScreen({super.key, this.initialIsDriver = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Navigation & Role State
  late bool _isDriver;
  bool _isLoginMode = false; // Toggle between Log In and Register
  bool _isLoading = false;
  bool _isArabic = false; // English by default, Arabic toggle

  // User Profile Inputs
  String _selectedGender = 'female'; // 'female' or 'male'
  bool _uperGirlOption = true; // Rafik Girl safe ride option
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _loginPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isDriver = widget.initialIsDriver;
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
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

  // ================= DATABASE PERSISTENCE HELPER =================
  Future<void> _saveUserToDatabase({
    required String name,
    required String phone,
    required String role,
    required String gender,
    required bool uperGirl,
  }) async {
    final userId = 'usr-${DateTime.now().millisecondsSinceEpoch}';

    // 1. Local persistent storage
    await PersistentStorage.saveUserSession(
      id: userId,
      name: name,
      phone: phone,
      role: role,
      gender: gender,
      uperGirlEnabled: uperGirl,
    );

    // 2. Post to backend server database (persists in backend/data/database.json)
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse('http://192.168.1.13:5000/api/register'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'name': name,
        'phone': phone,
        'role': role,
        'gender': gender,
        'uperGirlOption': uperGirl,
      }));
      final res = await req.close().timeout(const Duration(seconds: 2));
      debugPrint('[Rafik Database] Registered with status: ${res.statusCode}');
    } catch (e) {
      debugPrint('[Rafik Database Notice] LAN server offline, cached locally: $e');
    }

    // 3. Post to Supabase Cloud if project is active
    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        'full_name': name,
        'phone': phone,
        'role': role,
        'gender': gender,
        'uper_girl_certified': uperGirl,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('[Rafik Supabase] Profile synced to cloud database: $userId');
    } catch (e) {
      debugPrint('[Rafik Supabase Notice] Cloud sync deferred (project sleeping or offline): $e');
    }
  }

  // ================= 1-TAP DEMO BYPASS =================
  Future<void> _handleInstantBypass() async {
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    final isFemale = _selectedGender == 'female';
    final name = _isDriver
        ? (isFemale ? 'Captain Salma Ahmed' : 'Captain Tarek Mansour')
        : (isFemale ? 'Nourhan Kamel' : 'Karim Fahmy');
    final phone = isFemale ? '+20 109 888 7766' : '+20 102 333 4455';

    await _saveUserToDatabase(
      name: name,
      phone: phone,
      role: _isDriver ? 'driver' : 'rider',
      gender: _selectedGender,
      uperGirl: _uperGirlOption && isFemale,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _navigateAfterAuth();
  }

  // ================= 1-TAP GOOGLE SIGN-IN =================
  Future<void> _handleGoogleSignIn() async {
    HapticFeedback.lightImpact();

    final isFemale = _selectedGender == 'female';
    final defaultGoogleName = isFemale ? 'Salma Ahmed' : 'Ahmed Mahmoud';
    final defaultGoogleEmail = isFemale ? 'salma.ahmed@gmail.com' : 'ahmed.m@gmail.com';

    // Show Google Account Selector Dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: const Center(
                child: Text('G', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _isArabic ? 'تسجيل الدخول عبر Google' : 'Sign in with Google',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isArabic ? 'اختر حساباً للمتابعة إلى رفيق:' : 'Choose an account to continue to Rafik:',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _currentAccent,
                child: Text(defaultGoogleName[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(defaultGoogleName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: Text(defaultGoogleEmail, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);

                await _saveUserToDatabase(
                  name: defaultGoogleName,
                  phone: '+20 100 123 4567',
                  role: _isDriver ? 'driver' : 'rider',
                  gender: _selectedGender,
                  uperGirl: _uperGirlOption && isFemale,
                );

                if (mounted) {
                  setState(() => _isLoading = false);
                  _navigateAfterAuth();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================= REGISTER SUBMISSION =================
  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isArabic ? 'يرجى إدخال الاسم ورقم الهاتف' : 'Please enter your full name and phone number.'),
          backgroundColor: AppTheme.alertSos,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    await _saveUserToDatabase(
      name: name,
      phone: phone,
      role: _isDriver ? 'driver' : 'rider',
      gender: _selectedGender,
      uperGirl: _uperGirlOption && (_selectedGender == 'female'),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _navigateAfterAuth();
  }

  // ================= LOG IN SUBMISSION =================
  Future<void> _handleLogin() async {
    final phone = _loginPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isArabic ? 'يرجى إدخال رقم الهاتف' : 'Please enter your registered phone number.'),
          backgroundColor: AppTheme.alertSos,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    await _saveUserToDatabase(
      name: _selectedGender == 'female' ? 'Mona Kamel' : 'Karim Fahmy',
      phone: phone,
      role: _isDriver ? 'driver' : 'rider',
      gender: _selectedGender,
      uperGirl: _selectedGender == 'female',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    _navigateAfterAuth();
  }

  void _navigateAfterAuth() {
    if (_isDriver) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverOnboardingScreen(
            driverGender: _selectedGender,
            isUperGirlEnrolled: _uperGirlOption && (_selectedGender == 'female'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _currentBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ================= TOP BAR (LANG & MODE) =================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Status Badge
                          PillBadge(
                            label: _selectedGender == 'male' ? 'TITANIUM BLACK' : 'ROSE OBSIDIAN',
                            variant: _selectedGender == 'male' ? PillBadgeVariant.dark : PillBadgeVariant.roseGold,
                          ),

                          // Language Toggle Button (EN | عربي)
                          InkWell(
                            onTap: _toggleLanguage,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _currentCardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _currentAccent.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.language, size: 14, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isArabic ? 'English (EN)' : 'عربي (AR)',
                                    style: TextStyle(
                                      color: _currentAccentLight,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ================= LOGO =================
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: _currentCardBg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _currentAccent.withValues(alpha: 0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
                      ),

                      const SizedBox(height: 12),

                      // Brand Titles
                      const Text(
                        'RAFIK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isArabic ? 'رَفِـــيــق | رفيق جيرل' : 'RAFIK | SMART MOBILITY',
                        style: TextStyle(
                          color: _currentAccentLight,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ================= 1-TAP DEMO BYPASS BUTTON =================
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleInstantBypass,
                          icon: const Icon(Icons.flash_on, color: Colors.amber, size: 18),
                          label: Text(
                            _isArabic
                                ? '⚡ دخول تجريبي فوري مباشر (بدون انتظار)'
                                : '⚡ 1-TAP INSTANT DEMO BYPASS',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E1A23),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.amber, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ================= AUTH TABS: [LOG IN] vs [REGISTER] =================
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
                                      _isArabic ? 'إنشاء حساب جديد' : 'Register Account',
                                      style: TextStyle(
                                        color: !_isLoginMode ? Colors.white : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
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
                                      _isArabic ? 'تسجيل الدخول' : 'Log In',
                                      style: TextStyle(
                                        color: _isLoginMode ? Colors.white : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ================= DYNAMIC FORM CONTAINER =================
                      if (!_isLoginMode) ...[
                        // -------- REGISTER VIEW --------
                        // 1. Role Toggle (Rider vs Driver)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: _currentCardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _currentBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _isDriver = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: !_isDriver ? _currentAccent.withValues(alpha: 0.3) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _isArabic ? 'راكب (Passenger)' : 'Passenger / Rider',
                                        style: TextStyle(
                                          color: !_isDriver ? Colors.white : Colors.white60,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _isDriver = true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _isDriver ? AppTheme.sageSafe.withValues(alpha: 0.4) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _isArabic ? 'كابتن (Driver Partner)' : 'Captain / Driver',
                                        style: TextStyle(
                                          color: _isDriver ? Colors.white : Colors.white60,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 2. Gender Selection (Changes background color!)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _isArabic ? 'تحديد الجنس (يحدد لون الخلفية)' : 'SELECT GENDER (SETS APP THEME):',
                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _selectedGender = 'female';
                                  _uperGirlOption = true;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'female'
                                        ? const Color(0xFFB76E79).withValues(alpha: 0.25)
                                        : _currentCardBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedGender == 'female' ? const Color(0xFFB76E79) : _currentBorder,
                                      width: _selectedGender == 'female' ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.female, color: Color(0xFFE8B4B8), size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isArabic ? 'أنثى (Rose Obsidian)' : 'Female (Rose Theme)',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _selectedGender = 'male';
                                  _uperGirlOption = false;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _selectedGender == 'male'
                                        ? const Color(0xFF3B82F6).withValues(alpha: 0.25)
                                        : _currentCardBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedGender == 'male' ? const Color(0xFF3B82F6) : _currentBorder,
                                      width: _selectedGender == 'male' ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.male, color: Color(0xFF93C5FD), size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isArabic ? 'ذكر (Pure Black)' : 'Male (Black Theme)',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // 3. Rafik Girl Option (Only for females)
                        if (_selectedGender == 'female')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _uperGirlOption ? AppTheme.roseGold.withValues(alpha: 0.12) : _currentCardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _uperGirlOption ? AppTheme.roseGold : _currentBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.shield_outlined, color: AppTheme.roseGoldLight, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _isDriver
                                        ? (_isArabic ? 'كابتن رفيق جيرل (سيدات فقط)' : 'Rafik Girl Fleet (Female Riders Only)')
                                        : (_isArabic ? 'خيار رفيق جيرل (رحلات آمنة مع سائقات)' : 'Rafik Girl (Pair with Female Captains)'),
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Switch(
                                  value: _uperGirlOption,
                                  activeColor: AppTheme.roseGold,
                                  onChanged: (val) => setState(() => _uperGirlOption = val),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 12),

                        // 4. Full Name Input
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: _isArabic ? 'الاسم الكامل الرسمي' : 'Full Legal Name',
                            hintText: _isDriver ? 'e.g. Salma Ahmed' : 'e.g. Mona Kamel',
                            filled: true,
                            fillColor: _currentCardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _currentBorder)),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 5. Mobile Phone Input
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            labelText: _isArabic ? 'رقم الهاتف المحمول' : 'Mobile Phone',
                            hintText: '010 1234 5678',
                            prefixText: '+20  ',
                            filled: true,
                            fillColor: _currentCardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _currentBorder)),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 6. Create Account Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isDriver ? AppTheme.sageSafe : _currentAccent,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text(
                                    _isDriver
                                        ? (_isArabic ? 'متابعة إلى رفع المستندات ➔' : 'CONTINUE TO DOCUMENT UPLOADS ➔')
                                        : (_isArabic ? 'إنشاء حساب راكب ➔' : 'CREATE RIDER ACCOUNT ➔'),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ] else ...[
                        // -------- LOG IN VIEW --------
                        const SizedBox(height: 10),
                        TextField(
                          controller: _loginPhoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            labelText: _isArabic ? 'رقم الهاتف المسجل' : 'Registered Mobile Phone',
                            hintText: '010 1234 5678',
                            prefixText: '+20  ',
                            filled: true,
                            fillColor: _currentCardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _currentBorder)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _currentAccent,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text(
                                    _isArabic ? 'تسجيل الدخول الآن ➔' : 'LOG IN NOW ➔',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Google Sign In Option
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _currentCardBg,
                            side: BorderSide(color: _currentAccent.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                child: const Center(
                                  child: Text('G', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue, fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _isArabic ? 'المتابعة بحساب Google' : 'Continue with Google',
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // ================= TOGGLE LINK AT BOTTOM =================
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                          child: Text(
                            _isLoginMode
                                ? (_isArabic ? 'ليس لديك حساب؟ إنشاء حساب جديد' : "Don't have an account? Register here")
                                : (_isArabic ? 'لديك حساب بالفعل؟ تسجيل الدخول' : "Already registered? Log in here"),
                            style: TextStyle(
                              color: _currentAccentLight,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Copyright
                      Text(
                        _isArabic ? 'جميع الحقوق محفوظة لـ رفيق 2026' : 'All rights reserved to Rafik 2026',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
