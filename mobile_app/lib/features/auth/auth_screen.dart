import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/national_id_utils.dart';
import '../../core/utils/phone_number_utils.dart';
import '../driver/driver_onboarding_screen.dart';
import '../driver/driver_pending_screen.dart';
import '../driver/driver_radar_screen.dart';
import '../driver/driver_rejected_screen.dart';
import '../rider/rider_home_screen.dart';
import 'otp_verification_sheet.dart';

/// Rafik (رفيق) — Modern Authentication & Onboarding
///
/// Features:
/// 1. Real Firebase Phone Authentication with SMS OTP (+20 E.164 normalization).
/// 2. Strict separation of Login and Registration workflows:
///    - Login never silently creates a profile. Unregistered numbers are directed to registration.
///    - Registration verifies OTP before creating profile documents in Firestore.
/// 3. Role enforcement (Rider cannot access Driver app; Driver cannot access Rider app).
/// 4. Driver approval gating:
///    - Pending drivers routed to DriverPendingScreen.
///    - Rejected drivers routed to DriverRejectedScreen.
///    - Approved drivers enter DriverRadarScreen.
/// 5. 1-Tap Arabic / English toggle & Dynamic Obsidian Berry vs Midnight Black themes.
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
  // Navigation & Screen State
  bool _isLogin = true; // Default view is Log In
  String? _registerRole; // 'client' or 'captain'
  bool _isLoading = false;
  bool _isArabic = true; // Arabic default for Egyptian market

  // Selected Gender (Controls Theme)
  String _selectedGender = 'female';

  // Login Controller
  final TextEditingController _loginPhoneController = TextEditingController();

  // Registration Controllers
  final TextEditingController _regNameController = TextEditingController();
  final TextEditingController _regPhoneController = TextEditingController();
  final TextEditingController _regUsernameController = TextEditingController();

  // Captain Specific Controllers
  final TextEditingController _regNationalIdController = TextEditingController();
  final TextEditingController _regVehiclePlateController = TextEditingController();
  final TextEditingController _regVehicleModelController = TextEditingController();
  final TextEditingController _regVehicleMakeController = TextEditingController();
  final TextEditingController _regVehicleYearController = TextEditingController(text: '2022');
  final TextEditingController _regVehicleColorController = TextEditingController();
  final TextEditingController _regLicenseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialIsDriver || widget.initialRole == 'driver') {
      _registerRole = 'captain';
    } else {
      _registerRole = 'client';
    }
    _loadSavedPreferences();
  }

  @override
  void dispose() {
    _loginPhoneController.dispose();
    _regNameController.dispose();
    _regPhoneController.dispose();
    _regUsernameController.dispose();
    _regNationalIdController.dispose();
    _regVehiclePlateController.dispose();
    _regVehicleModelController.dispose();
    _regVehicleMakeController.dispose();
    _regVehicleYearController.dispose();
    _regVehicleColorController.dispose();
    _regLicenseController.dispose();
    super.dispose();
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

  // ================= THEME DYNAMICS =================
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
        ? const Color(0xFF3B82F6) // Titanium Ice Blue
        : AppTheme.roseGold; // Egyptian Rose Gold
  }

  // ================= 1. LOGIN FLOW VIA PHONE OTP =================
  Future<void> _handleLoginPhone() async {
    final rawPhone = _loginPhoneController.text.trim();

    if (rawPhone.isEmpty) {
      _showErrorSnackBar(
        _isArabic ? 'يرجى إدخال رقم الموبايل' : 'Please enter your mobile phone number',
      );
      return;
    }

    String normalizedPhone;
    try {
      normalizedPhone = PhoneNumberUtils.normalizeEgyptianPhone(rawPhone);
    } catch (e) {
      _showErrorSnackBar(e.toString());
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseService().sendPhoneOtp(
        rawPhone: normalizedPhone,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);

          // Open 6-digit OTP verification sheet
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => OtpVerificationSheet(
              phoneNumber: normalizedPhone,
              verificationId: verificationId,
              resendToken: resendToken,
              gender: _selectedGender,
              isArabic: _isArabic,
              onVerified: (UserCredential credential) {
                _onLoginOtpVerified(credential);
              },
            ),
          );
        },
        onVerificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showErrorSnackBar(
            _isArabic
                ? 'فشل إرسال كود التحقق: ${e.message ?? e.code}'
                : 'Failed to send verification SMS: ${e.message ?? e.code}',
          );
        },
        onVerificationCompleted: (PhoneAuthCredential credential) async {
          // Instant verification (Android auto-retrieval)
          try {
            final authCred = await FirebaseService().auth.signInWithCredential(credential);
            if (mounted) {
              _onLoginOtpVerified(authCred);
            }
          } catch (_) {}
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.toString());
      }
    }
  }

  /// Evaluates account status and navigates to the appropriate screen after OTP is verified.
  Future<void> _onLoginOtpVerified(UserCredential credential) async {
    final user = credential.user;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final profile = await FirebaseService().getUserProfile(user.uid);

      // CRITICAL: Never silently create an account on login!
      if (profile == null) {
        await FirebaseService().signOut();
        if (!mounted) return;
        _showErrorSnackBar(
          _isArabic
              ? 'هذا الرقم غير مسجل في رفيق. يرجى إنشاء حساب جديد أولاً.'
              : 'This phone number is not registered yet. Please create an account.',
        );
        setState(() {
          _isLogin = false;
          _regPhoneController.text = _loginPhoneController.text;
        });
        return;
      }

      // Check account active status
      if (profile['is_active'] == false) {
        await FirebaseService().signOut();
        if (!mounted) return;
        _showErrorSnackBar(
          _isArabic
              ? 'تم تعطيل هذا الحساب. يرجى التواصل مع فريق الدعم.'
              : 'This account has been deactivated. Please contact support.',
        );
        return;
      }

      // Enforce Role Separation
      final role = profile['role']?.toString().toLowerCase() ?? 'rider';
      final expectedRole = widget.initialRole;

      if (expectedRole == 'driver' && role != 'driver') {
        await FirebaseService().signOut();
        if (!mounted) return;
        _showErrorSnackBar(
          _isArabic
              ? 'هذا الحساب مسجل كعميل. يرجى استخدام تطبيق رفيق للركاب.'
              : 'This account is registered as a Client. Please use the Rafik Rider application.',
        );
        return;
      }

      if (expectedRole == 'rider' && role != 'rider') {
        await FirebaseService().signOut();
        if (!mounted) return;
        _showErrorSnackBar(
          _isArabic
              ? 'هذا الحساب مسجل ككابتن. يرجى استخدام تطبيق كابتن رفيق.'
              : 'This account is registered as a Captain. Please use the Rafik Captain application.',
        );
        return;
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      // Route based on role and driver approval state
      if (role == 'driver') {
        final status = profile['status']?.toString().toLowerCase() ?? 'pending';
        if (status == 'approved') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DriverRadarScreen()),
            (route) => false,
          );
        } else if (status == 'rejected') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => DriverRejectedScreen(
                rejectionReason: profile['rejection_reason']?.toString(),
              ),
            ),
            (route) => false,
          );
        } else {
          // Status is 'pending' or newly submitted
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
            (route) => false,
          );
        }
      } else {
        // Rider
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Login Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= 2. REGISTRATION FLOW VIA PHONE OTP =================
  Future<void> _handleStartRegistration() async {
    final isCaptain = _registerRole == 'captain';
    final name = _regNameController.text.trim();
    final rawPhone = _regPhoneController.text.trim();

    if (name.isEmpty || rawPhone.isEmpty) {
      _showErrorSnackBar(
        _isArabic ? 'يرجى إدخال الاسم ورقم الموبايل' : 'Please enter your name and phone number',
      );
      return;
    }

    String normalizedPhone;
    try {
      normalizedPhone = PhoneNumberUtils.normalizeEgyptianPhone(rawPhone);
    } catch (e) {
      _showErrorSnackBar(e.toString());
      return;
    }

    // Driver specific validations
    if (isCaptain) {
      final nationalId = _regNationalIdController.text.trim();
      final vehiclePlate = _regVehiclePlateController.text.trim();
      final vehicleModel = _regVehicleModelController.text.trim();

      if (nationalId.isEmpty || vehiclePlate.isEmpty || vehicleModel.isEmpty) {
        _showErrorSnackBar(
          _isArabic
              ? 'يرجى إكمال بيانات الرقم القومي والسيارة'
              : 'Please complete all driver & vehicle fields',
        );
        return;
      }

      try {
        NationalIdUtils.validate(nationalId);
        if (!NationalIdUtils.matchesGender(nationalId, _selectedGender)) {
          _showErrorSnackBar(
            _isArabic
                ? 'الرقم القومي غير متطابق مع الجنس المحدد'
                : 'National ID gender does not match selected gender',
          );
          return;
        }
      } catch (e) {
        _showErrorSnackBar(e.toString());
        return;
      }
    }

    // If user is already authenticated with this verified phone number, retry profile creation directly
    final currentUser = FirebaseService().currentUser;
    if (currentUser != null && currentUser.phoneNumber == normalizedPhone) {
      debugPrint('[PhoneAuth] User already authenticated with verified phone $normalizedPhone. Retrying profile creation directly.');
      await _onRegistrationUserVerified(currentUser, normalizedPhone);
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseService().sendPhoneOtp(
        rawPhone: normalizedPhone,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => OtpVerificationSheet(
              phoneNumber: normalizedPhone,
              verificationId: verificationId,
              resendToken: resendToken,
              gender: _selectedGender,
              isArabic: _isArabic,
              onVerified: (UserCredential credential) {
                if (credential.user != null) {
                  _onRegistrationUserVerified(credential.user!, normalizedPhone);
                }
              },
            ),
          );
        },
        onVerificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showErrorSnackBar(
            _isArabic
                ? 'فشل إرسال كود التحقق: ${e.message ?? e.code}'
                : 'Failed to send SMS OTP: ${e.message ?? e.code}',
          );
        },
        onVerificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final authCred = await FirebaseService().auth.signInWithCredential(credential);
            if (mounted && authCred.user != null) {
              _onRegistrationUserVerified(authCred.user!, normalizedPhone);
            }
          } catch (_) {}
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.toString());
      }
    }
  }

  /// After SMS OTP verification, creates the profile in Firestore and routes to next step.
  Future<void> _onRegistrationUserVerified(User user, String phone) async {
    setState(() => _isLoading = true);
    try {
      // 1. Check if user already exists
      final existingProfile = await FirebaseService().getUserProfile(user.uid);
      if (existingProfile != null) {
        if (!mounted) return;
        _showErrorSnackBar(
          _isArabic
              ? 'هذا الرقم مسجل بالفعل في رفيق. جاري تحويلك لتسجيل الدخول.'
              : 'This phone is already registered. Redirecting to login.',
        );
        setState(() {
          _isLogin = true;
          _loginPhoneController.text = phone;
        });
        return;
      }

      final isCaptain = _registerRole == 'captain';
      final name = _regNameController.text.trim();
      final username = _regUsernameController.text.trim();

      if (isCaptain) {
        // Register Captain
        final nationalId = _regNationalIdController.text.trim();
        final vehiclePlate = _regVehiclePlateController.text.trim();
        final vehicleModel = _regVehicleModelController.text.trim();
        final vehicleMake = _regVehicleMakeController.text.trim().isNotEmpty
            ? _regVehicleMakeController.text.trim()
            : vehicleModel.split(' ').first;
        final vehicleColor = _regVehicleColorController.text.trim().isNotEmpty
            ? _regVehicleColorController.text.trim()
            : (_selectedGender == 'female' ? 'Pearl Rose' : 'Midnight Black');
        final licenseNumber = _regLicenseController.text.trim().isNotEmpty
            ? _regLicenseController.text.trim()
            : 'LIC-$nationalId';
        final vehicleYear = int.tryParse(_regVehicleYearController.text.trim()) ?? 2022;

        await FirebaseService().registerDriverProfile(
          uid: user.uid,
          fullName: name,
          phone: phone,
          gender: _selectedGender,
          nationalId: nationalId,
          licenseNumber: licenseNumber,
          vehicleMake: vehicleMake,
          vehicleModel: vehicleModel,
          vehicleYear: vehicleYear,
          vehiclePlate: vehiclePlate,
          vehicleColor: vehicleColor,
          username: username.isNotEmpty ? username : null,
        );

        if (!mounted) return;
        HapticFeedback.heavyImpact();

        // Direct to 6-Sided KYC Document Vault
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverOnboardingScreen(
              driverId: user.uid,
              driverGender: _selectedGender,
              isUperGirlEnrolled: _selectedGender == 'female',
            ),
          ),
        );
      } else {
        // Register Client / Rider
        await FirebaseService().registerRiderProfile(
          uid: user.uid,
          fullName: name,
          phone: phone,
          gender: _selectedGender,
          username: username.isNotEmpty ? username : null,
        );

        if (!mounted) return;
        HapticFeedback.heavyImpact();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Registration Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= ROLE SELECTION MODAL =================
  void _openRoleSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _currentCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isArabic ? 'اختر نوع الحساب للتسجيل' : 'Choose Account Type',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'هل تريد حجز مشاوير كعميل أو الانضمام للأسطول ككابتن؟'
                      : 'Do you want to book rides as a Client or drive as a Captain?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Option 1: Client / Rider
                _buildRoleOptionCard(
                  title: _isArabic ? 'عميل / راكب' : 'Client / Passenger',
                  subtitle: _isArabic
                      ? 'احجز مشاوير آمنة مع جو سيف ستاندرد أو جو سيف هير'
                      : 'Book safe rides with Go Safe Standard or Go Safe Her',
                  icon: Icons.person_rounded,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _isLogin = false;
                      _registerRole = 'client';
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Option 2: Captain / Driver
                _buildRoleOptionCard(
                  title: _isArabic ? 'كابتن / سائق' : 'Captain / Driver',
                  subtitle: _isArabic
                      ? 'انضم للأسطول مع 0% عمولة واحتفظ بـ 100% من أرباحك'
                      : 'Drive with 0% platform commission & keep 100% earnings',
                  icon: Icons.drive_eta_rounded,
                  color: AppTheme.roseGold,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _isLogin = false;
                      _registerRole = 'captain';
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              _isArabic ? Icons.arrow_back_ios_rounded : Icons.arrow_forward_ios_rounded,
              color: color,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE11D48),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ================= UI BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _currentBg,
      body: Directionality(
        textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar with Logo and Language Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_currentAccent, _currentAccent.withValues(alpha: 0.6)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'R',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isArabic ? 'جـو سِـيف رَفِيق' : 'RAFIK GO SAFE',
                              style: TextStyle(
                                color: _currentAccent,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Text(
                              _selectedGender == 'female'
                                  ? (_isArabic ? 'شبكة رفيق هير الآمنة للسيدات' : 'Rafik Her Women-Only Network')
                                  : (_isArabic ? 'منصة التنقل الآمن والذكي' : 'Verified Safe Mobility Network'),
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Language Switcher
                    GestureDetector(
                      onTap: _toggleLanguage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.language, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _isArabic ? 'EN' : 'عربي',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Form Body
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: _isLogin ? _buildLoginForm() : _buildRegistrationForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 1. LOG IN VIEW =================
  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          _isArabic ? 'تسجيل الدخول' : 'Welcome Back',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isArabic
              ? 'أدخل رقم الموبايل لتلقي كود التحقق الآمن عبر SMS'
              : 'Enter your mobile number to receive a secure SMS verification code',
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 32),

        // Mobile Field
        _buildInputField(
          controller: _loginPhoneController,
          label: _isArabic ? 'رقم الموبايل المصري' : 'Egyptian Mobile Number',
          hint: '010XXXXXXXX / 011XXXXXXXX',
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 28),

        // Send OTP Button
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentAccent,
            foregroundColor: _selectedGender == 'male' ? Colors.white : Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
          ),
          onPressed: _isLoading ? null : _handleLoginPhone,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _isArabic ? 'إرسال كود التحقق (SMS) ➔' : 'Send Verification Code (SMS) ➔',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 24),

        // "Register Now" Prompt
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isArabic ? 'ليس لديك حساب؟ ' : "Don't have an account? ",
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
              GestureDetector(
                onTap: _openRoleSelectionModal,
                child: Text(
                  _isArabic ? 'سجل الآن' : 'Register Now',
                  style: TextStyle(
                    color: _currentAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Gender theme toggle preview
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isArabic ? 'طابع الخدمة: ' : 'Service Theme: ',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(_isArabic ? 'رفيق هير (سيدات)' : 'Rafik Her (Women)'),
                  selected: _selectedGender == 'female',
                  selectedColor: AppTheme.roseGold.withValues(alpha: 0.3),
                  onSelected: (val) => setState(() => _selectedGender = 'female'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(_isArabic ? 'رفيق ستاندرد' : 'Rafik Standard'),
                  selected: _selectedGender == 'male',
                  selectedColor: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                  onSelected: (val) => setState(() => _selectedGender = 'male'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================= 2. REGISTRATION VIEW =================
  Widget _buildRegistrationForm() {
    final isCaptain = _registerRole == 'captain';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                await FirebaseService().signOut();
                setState(() => _isLogin = true);
              },
            ),
            const SizedBox(width: 8),
            Text(
              isCaptain
                  ? (_isArabic ? 'تسجيل كابتن جديد' : 'New Captain Registration')
                  : (_isArabic ? 'تسجيل عميل جديد' : 'New Client Registration'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Basic Profile Info
        _buildInputField(
          controller: _regNameController,
          label: _isArabic ? 'الاسم بالكامل' : 'Full Legal Name',
          hint: _isArabic ? 'الاسم كما هو مدون في البطاقة' : 'As written on National ID',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regPhoneController,
          label: _isArabic ? 'رقم الموبايل المصري' : 'Mobile Number',
          hint: '010XXXXXXXX / 011XXXXXXXX',
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regUsernameController,
          label: _isArabic ? 'اسم المستخدم (اختياري)' : 'Username (Optional)',
          hint: 'e.g. rafik_user',
          icon: Icons.alternate_email_rounded,
        ),
        const SizedBox(height: 14),

        // Gender selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _currentCardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _currentBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isArabic ? 'النوع / الجنس:' : 'Gender:',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(_isArabic ? 'أنثى' : 'Female'),
                    selected: _selectedGender == 'female',
                    selectedColor: AppTheme.roseGold.withValues(alpha: 0.3),
                    onSelected: (val) => setState(() => _selectedGender = 'female'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(_isArabic ? 'ذكر' : 'Male'),
                    selected: _selectedGender == 'male',
                    selectedColor: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                    onSelected: (val) => setState(() => _selectedGender = 'male'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Extra fields for Captain
        if (isCaptain) ...[
          const SizedBox(height: 18),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          Text(
            _isArabic ? 'بيانات الكابتن والمركبة' : 'Captain & Vehicle Details',
            style: TextStyle(color: _currentAccent, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 14),

          _buildInputField(
            controller: _regNationalIdController,
            label: _isArabic ? 'الرقم القومي المصري (14 رقم)' : 'National ID (14 digits)',
            hint: '2980XXXXXXXXXX',
            icon: Icons.credit_card_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),

          _buildInputField(
            controller: _regVehicleModelController,
            label: _isArabic ? 'موديل وماركة السيارة' : 'Vehicle Model & Make',
            hint: 'Toyota Corolla / Hyundai Elantra',
            icon: Icons.directions_car_rounded,
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _regVehiclePlateController,
                  label: _isArabic ? 'رقم اللوحة' : 'Plate Number',
                  hint: 'أ ب ج 1234',
                  icon: Icons.numbers_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _regVehicleColorController,
                  label: _isArabic ? 'اللون' : 'Color',
                  hint: 'أبيض / أسود',
                  icon: Icons.palette_outlined,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 28),

        // Submit Button
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentAccent,
            foregroundColor: _selectedGender == 'male' ? Colors.white : Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _isLoading ? null : _handleStartRegistration,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  isCaptain
                      ? (_isArabic ? 'المتابعة وتأكيد الموبايل (SMS) ➔' : 'Verify Mobile via SMS ➔')
                      : (_isArabic ? 'تأكيد الحساب عبر (SMS) ➔' : 'Verify Account via SMS ➔'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),

        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () async {
              await FirebaseService().signOut();
              setState(() => _isLogin = true);
            },
            child: Text(
              _isArabic ? 'لديك حساب بالفعل؟ تسجيل الدخول' : 'Already have an account? Log In',
              style: TextStyle(color: _currentAccent),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ================= INPUT FIELD BUILDER =================
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _currentCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _currentBorder),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
              prefixIcon: Icon(icon, color: _currentAccent, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
