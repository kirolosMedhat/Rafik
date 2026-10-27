import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../driver/driver_radar_screen.dart';
import '../rider/rider_home_screen.dart';

/// Rafik (رفيق) — Modern Authentication & Onboarding
/// Features:
/// 1. Primary Log In page: Username or Mobile + Password.
/// 2. "Register Now" modal prompt: Captain or Client selection.
/// 3. Direct registration flows for Client and Captain.
/// 4. Pure Firebase Auth + Cloud Firestore real-time integration.
/// 5. Dynamic Jet Black (Male) vs Obsidian Berry (Female) themes with 1-tap Arabic toggle.
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
  bool _isArabic = false; // English default, instant Arabic switch
  bool _obscurePassword = true;

  // Selected Gender (Controls Theme)
  String _selectedGender = 'female';

  // Login Controllers
  final TextEditingController _loginIdentifierController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  // Registration Controllers
  final TextEditingController _regNameController = TextEditingController();
  final TextEditingController _regPhoneController = TextEditingController();
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();

  // Captain Specific Controllers
  final TextEditingController _regNationalIdController = TextEditingController();
  final TextEditingController _regVehiclePlateController = TextEditingController();
  final TextEditingController _regVehicleModelController = TextEditingController();
  final TextEditingController _regVehicleYearController = TextEditingController(text: '2022');
  final TextEditingController _regVehicleColorController = TextEditingController();
  final TextEditingController _regLicenseController = TextEditingController();

  @override
  void initState() {
    super.initState();
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

  // ================= LOGIN ACTION =================
  Future<void> _handleLogin() async {
    final identifier = _loginIdentifierController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showErrorSnackBar(
        _isArabic
            ? 'يرجى إدخال اسم المستخدم أو رقم الموبايل وكلمة المرور'
            : 'Please enter your username/mobile and password',
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      final credential = await FirebaseService().signInWithUsernameOrMobile(
        identifier: identifier,
        password: password,
      );

      final uid = credential.user?.uid;
      if (uid == null) throw Exception('Authentication failed');

      // Check profile to route to correct experience
      final profile = await FirebaseService().getCurrentUserProfile();
      final role = profile?['role']?.toString() ?? 'rider';

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      if (role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverRadarScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[Login Error] $e');
      String msg = _isArabic ? 'بيانات تسجيل الدخول غير صحيحة' : 'Invalid login credentials';
      if (e.toString().contains('user-not-found')) {
        msg = _isArabic ? 'الحساب غير موجود، يرجى التسجيل أولاً' : 'User account not found. Please register.';
      } else if (e.toString().contains('wrong-password')) {
        msg = _isArabic ? 'كلمة المرور غير صحيحة' : 'Incorrect password.';
      }
      _showErrorSnackBar(msg);
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
                      ? 'احجز مشاوير آمنة مع رفيق ستاندرد أو رفيق جيرل'
                      : 'Book safe rides with Rafik Standard or Rafik Girl',
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
                      ? 'انضم للأسطول وقد سيارتك مع 0% عمولة وأرباح 100%'
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
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

  // ================= CLIENT REGISTRATION =================
  Future<void> _handleRegisterClient() async {
    final name = _regNameController.text.trim();
    final phone = _regPhoneController.text.trim();
    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();

    if (name.isEmpty || phone.isEmpty || username.isEmpty || password.isEmpty) {
      _showErrorSnackBar(_isArabic ? 'يرجى إكمال جميع الحقول المطلوبة' : 'Please fill all fields');
      return;
    }

    if (password.length < 6) {
      _showErrorSnackBar(_isArabic ? 'كلمة المرور يجب أن لا تقل عن 6 أحرف' : 'Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseService().registerClient(
        name: name,
        phone: phone,
        username: username,
        password: password,
        gender: _selectedGender,
        isUperGirl: _selectedGender == 'female',
      );

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= CAPTAIN REGISTRATION =================
  Future<void> _handleRegisterCaptain() async {
    final name = _regNameController.text.trim();
    final phone = _regPhoneController.text.trim();
    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();
    final nationalId = _regNationalIdController.text.trim();
    final vehiclePlate = _regVehiclePlateController.text.trim();
    final vehicleModel = _regVehicleModelController.text.trim();
    final vehicleColor = _regVehicleColorController.text.trim();
    final licenseNumber = _regLicenseController.text.trim();
    final year = int.tryParse(_regVehicleYearController.text.trim()) ?? 2022;

    if (name.isEmpty || phone.isEmpty || username.isEmpty || password.isEmpty ||
        nationalId.isEmpty || vehiclePlate.isEmpty || vehicleModel.isEmpty) {
      _showErrorSnackBar(_isArabic ? 'يرجى إكمال جميع بيانات الكابتن والمركبة' : 'Please complete all driver & vehicle fields');
      return;
    }

    if (nationalId.length != 14) {
      _showErrorSnackBar(_isArabic ? 'الرقم القومي يجب أن يتكون من 14 رقماً' : 'National ID must be exactly 14 digits');
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await FirebaseService().registerCaptain(
        name: name,
        phone: phone,
        username: username,
        password: password,
        gender: _selectedGender,
        nationalId: nationalId,
        vehiclePlate: vehiclePlate,
        vehicleModel: vehicleModel,
        vehicleYear: year,
        vehicleColor: vehicleColor.isNotEmpty ? vehicleColor : 'White',
        licenseNumber: licenseNumber.isNotEmpty ? licenseNumber : 'LIC-$nationalId',
      );

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverRadarScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Captain registration failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                              colors: [_currentAccent, _currentAccent.withOpacity(0.6)],
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
                              _isArabic ? 'رَفِيق' : 'RAFIK',
                              style: TextStyle(
                                color: _currentAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              _selectedGender == 'female'
                                  ? (_isArabic ? 'شبكة رفيق جيرل الآمنة' : 'Rafik Girl Network')
                                  : (_isArabic ? 'منصة النقل الذكي' : 'Smart Cairo Mobility'),
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
              ? 'سجل دخولك باستخدام اسم المستخدم أو رقم الموبايل'
              : 'Sign in with your username or mobile number to continue',
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
        const SizedBox(height: 32),

        // Identifier Field (Username or Mobile)
        _buildInputField(
          controller: _loginIdentifierController,
          label: _isArabic ? 'اسم المستخدم أو الموبايل' : 'Username or Mobile',
          hint: _isArabic ? 'مثال: 01012345678 أو kiro_99' : 'e.g. 01012345678 or ahmed_99',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 18),

        // Password Field
        _buildInputField(
          controller: _loginPasswordController,
          label: _isArabic ? 'كلمة المرور' : 'Password',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          obscureText: _obscurePassword,
          onTogglePassword: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        const SizedBox(height: 28),

        // Log In Button
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentAccent,
            foregroundColor: _selectedGender == 'male' ? Colors.white : Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
          ),
          onPressed: _isLoading ? null : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _isArabic ? 'تسجيل الدخول ➔' : 'Log In ➔',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 24),

        // Under Login: "Register Now" with prompt
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
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isArabic ? 'تخصيص المظهر: ' : 'Appearance Theme: ',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(_isArabic ? 'أنثى' : 'Female'),
                  selected: _selectedGender == 'female',
                  selectedColor: AppTheme.roseGold.withOpacity(0.3),
                  onSelected: (val) => setState(() => _selectedGender = 'female'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(_isArabic ? 'ذكر' : 'Male'),
                  selected: _selectedGender == 'male',
                  selectedColor: const Color(0xFF3B82F6).withOpacity(0.3),
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
              onPressed: () => setState(() => _isLogin = true),
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
          label: _isArabic ? 'الاسم بالكامل' : 'Full Name',
          hint: _isArabic ? 'الاسم كما في بطاقة الرقم القومي' : 'Full legal name',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regPhoneController,
          label: _isArabic ? 'رقم الموبايل' : 'Mobile Number',
          hint: '010XXXXXXXX',
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regUsernameController,
          label: _isArabic ? 'اسم المستخدم' : 'Username',
          hint: 'user123',
          icon: Icons.alternate_email_rounded,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _regPasswordController,
          label: _isArabic ? 'كلمة المرور' : 'Password',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          obscureText: _obscurePassword,
          onTogglePassword: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
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
                _isArabic ? 'النوع / الجنس:' : 'Gender Profile:',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(_isArabic ? 'أنثى' : 'Female'),
                    selected: _selectedGender == 'female',
                    selectedColor: AppTheme.roseGold.withOpacity(0.3),
                    onSelected: (val) => setState(() => _selectedGender = 'female'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(_isArabic ? 'ذكر' : 'Male'),
                    selected: _selectedGender == 'male',
                    selectedColor: const Color(0xFF3B82F6).withOpacity(0.3),
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
            label: _isArabic ? 'الرقم القومي (14 رقم)' : 'Egyptian National ID (14 digits)',
            hint: '2980XXXXXXXXXX',
            icon: Icons.credit_card_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),

          _buildInputField(
            controller: _regVehicleModelController,
            label: _isArabic ? 'موديل السيارة' : 'Vehicle Make & Model',
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
                  hint: 'White / Black',
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
          onPressed: _isLoading
              ? null
              : (isCaptain ? _handleRegisterCaptain : _handleRegisterClient),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  isCaptain
                      ? (_isArabic ? 'تسجيل ككابتن الآن ➔' : 'Complete Captain Signup ➔')
                      : (_isArabic ? 'إنشاء حساب عميل ➔' : 'Create Client Account ➔'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),

        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _isLogin = true),
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
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
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
            obscureText: isPassword && obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
              prefixIcon: Icon(icon, color: _currentAccent, size: 20),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                        size: 20,
                      ),
                      onPressed: onTogglePassword,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
