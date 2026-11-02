import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/national_id_utils.dart';
import '../../core/widgets/pill_badge.dart';
import '../biometrics/id_ocr_service.dart';
import 'driver_pending_screen.dart';

/// Rafik Driver Intake & Two-Faced (6-Sided) Document Vault
///
/// Features:
/// - Captures all 6 required document sides (National ID, Driver License, Vehicle Registration)
/// - Uploads actual binary image bytes to Firebase Storage (`driver_documents/{uid}/{docType}.jpg`)
/// - Tracks real-time upload progress (1 of 6 ... 6 of 6)
/// - Validates file size (max 5MB) and formats
/// - Validates 14-digit Egyptian National ID & gender parity
/// - Enforces initial driver status: 'pending' (client never self-approves)
/// - Navigates directly to DriverPendingScreen upon completion
class DriverOnboardingScreen extends StatefulWidget {
  final String? driverId;
  final String driverGender; // 'female' or 'male'
  final bool isUperGirlEnrolled;

  const DriverOnboardingScreen({
    super.key,
    this.driverId,
    this.driverGender = 'female',
    this.isUperGirlEnrolled = true,
  });

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  int _currentStep = 0; // 0: Vehicle Details, 1: 6-Sided Document Vault
  bool _isSubmitting = false;
  String _uploadProgressText = '';
  double _uploadProgressPercent = 0.0;

  // Form Controllers
  final _nationalIdController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleYearController = TextEditingController(text: '2022');
  final _plateNumberController = TextEditingController();
  final _vehicleColorController = TextEditingController();

  // Picked Document Files
  final Map<String, File> _docFiles = {};

  // Document Upload State (6 Sides)
  final Map<String, bool> _uploadedDocs = {
    'national_id_front': false,
    'national_id_back': false,
    'driver_license_front': false,
    'driver_license_back': false,
    'vehicle_reg_front': false,
    'vehicle_reg_back': false,
  };

  @override
  void initState() {
    super.initState();
    _loadExistingProfileData();
  }

  Future<void> _loadExistingProfileData() async {
    final uid = widget.driverId ?? FirebaseService().currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await FirebaseService().getUserProfile(uid);
      if (profile != null && mounted) {
        setState(() {
          if (profile['national_id_number'] != null) {
            _nationalIdController.text = profile['national_id_number'].toString();
          }
          if (profile['license_number'] != null) {
            _licenseNumberController.text = profile['license_number'].toString();
          }
          if (profile['vehicle_make'] != null) {
            _vehicleMakeController.text = profile['vehicle_make'].toString();
          }
          if (profile['vehicle_model'] != null) {
            _vehicleModelController.text = profile['vehicle_model'].toString();
          }
          if (profile['vehicle_year'] != null) {
            _vehicleYearController.text = profile['vehicle_year'].toString();
          }
          if (profile['vehicle_plate'] != null) {
            _plateNumberController.text = profile['vehicle_plate'].toString();
          }
          if (profile['vehicle_color'] != null) {
            _vehicleColorController.text = profile['vehicle_color'].toString();
          }

          // Pre-populate any documents that were already safely uploaded
          final docs = profile['documents'] as Map<String, dynamic>?;
          if (docs != null) {
            for (final key in _uploadedDocs.keys) {
              if (docs[key] != null && docs[key]['storage_path'] != null) {
                _uploadedDocs[key] = true;
              }
            }
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nationalIdController.dispose();
    _licenseNumberController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleYearController.dispose();
    _plateNumberController.dispose();
    _vehicleColorController.dispose();
    super.dispose();
  }

  Future<void> _captureDocument(String key, String title) async {
    HapticFeedback.lightImpact();

    // Show source picker (Camera or Gallery)
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1E141B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.roseGold),
                title: const Text('التقاط بالكاميرا (Camera)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppTheme.roseGold),
                title: const Text('اختيار من المعرض (Gallery)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final file = File(photo.path);
        final sizeBytes = await file.length();
        if (sizeBytes > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('حجم الصورة كبير جداً. الحد الأقصى المسموح 5 ميجابايت.'),
                backgroundColor: AppTheme.berryCore,
              ),
            );
          }
          return;
        }

        _docFiles[key] = file;
        setState(() {
          _uploadedDocs[key] = true;
        });

        // Optional OCR check for National ID
        if (key == 'national_id_front' || key == 'national_id_back') {
          try {
            final ocrResult = await IdOcrService.verifyNationalId(photo.path);
            if (widget.isUperGirlEnrolled && widget.driverGender == 'female' && !ocrResult.isFemale) {
              if (mounted) {
                HapticFeedback.vibrate();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ocrResult.message ?? 'تنبيه: خدمة رفيق هير مخصصة للسيدات وتتطلب بطاقة رقم قومي مؤكدة لإناث.'),
                    backgroundColor: AppTheme.alertSos,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          } catch (_) {}
        }

        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم التقاط $title بنجاح.'),
              backgroundColor: AppTheme.sageSafe,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Camera/Picker notice] $e');
    }
  }

  Future<void> _submitApplication() async {
    final allUploaded = _uploadedDocs.values.every((uploaded) => uploaded);
    if (!allUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى التقاط وتصوير جميع المستندات الستة المطلوبة قبل الإرسال.'),
          backgroundColor: AppTheme.berryCore,
        ),
      );
      return;
    }

    final nationalId = _nationalIdController.text.trim();
    try {
      NationalIdUtils.validate(nationalId);
      if (!NationalIdUtils.matchesGender(nationalId, widget.driverGender)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الرقم القومي غير متطابق مع جنس الحساب المسجل.'),
            backgroundColor: AppTheme.berryCore,
          ),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.berryCore,
        ),
      );
      return;
    }

    final user = FirebaseService().currentUser;
    final uid = widget.driverId ?? user?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جلسة الدخول غير صالحة. يرجى تسجيل الدخول أولاً.'),
          backgroundColor: AppTheme.berryCore,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgressText = 'بدء معالجة ورفع المستندات...';
      _uploadProgressPercent = 0.0;
    });

    try {
      final totalDocs = _docFiles.length;
      int currentDocIndex = 0;

      // 1. Upload each real file to Firebase Storage
      for (final entry in _docFiles.entries) {
        currentDocIndex++;
        setState(() {
          _uploadProgressText = 'جاري رفع المستند ($currentDocIndex من $totalDocs): ${_docTitle(entry.key)}...';
          _uploadProgressPercent = currentDocIndex / totalDocs;
        });

        await FirebaseService().uploadDriverDocument(
          driverId: uid,
          docType: entry.key,
          file: entry.value,
          onProgress: (p) {
            // Sub-progress for individual large files
          },
        );
      }

      // 2. Update driver profile in Firestore with vehicle and identification data
      final licenseNum = _licenseNumberController.text.trim().isNotEmpty
          ? _licenseNumberController.text.trim()
          : 'LIC-$nationalId';
      final vehicleMake = _vehicleMakeController.text.trim();
      final vehicleModel = _vehicleModelController.text.trim();
      final vehicleYear = int.tryParse(_vehicleYearController.text.trim()) ?? 2022;
      final vehiclePlate = _plateNumberController.text.trim();
      final vehicleColor = _vehicleColorController.text.trim().isNotEmpty
          ? _vehicleColorController.text.trim()
          : (widget.driverGender == 'female' ? 'Pearl Rose' : 'Midnight Black');

      await FirebaseService().firestore.collection('drivers').doc(uid).set({
        'national_id_number': nationalId,
        'license_number': licenseNum,
        'vehicle_make': vehicleMake,
        'vehicle_model': vehicleModel,
        'vehicle_year': vehicleYear,
        'vehicle_plate': vehiclePlate,
        'vehicle_color': vehicleColor,
        'status': 'pending', // Re-verify status remains strictly pending
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء رفع المستندات: $e'),
            backgroundColor: AppTheme.alertSos,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _docTitle(String key) {
    switch (key) {
      case 'national_id_front':
        return 'بطاقة الرقم القومي (الوجه الأمامي)';
      case 'national_id_back':
        return 'بطاقة الرقم القومي (الوجه الخلفي)';
      case 'driver_license_front':
        return 'رخصة القيادة (الوجه الأمامي)';
      case 'driver_license_back':
        return 'رخصة القيادة (الوجه الخلفي)';
      case 'vehicle_reg_front':
        return 'رخصة المركبة (الوجه الأمامي)';
      case 'vehicle_reg_back':
        return 'رخصة المركبة (الوجه الخلفي)';
      default:
        return key;
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.sageSafe.withValues(alpha: 0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: AppTheme.sageSafe, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'تم إرسال المستندات بنجاح',
                style: TextStyle(
                  color: Color(0xFFFCE4E6),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PillBadge(
              label: 'تم الحفظ في الخزنة المشفرة لرفيق',
              variant: PillBadgeVariant.sage,
            ),
            const SizedBox(height: 14),
            Text(
              'تم استلام بيانات مركبتك والمستندات الستة في الخزنة السحابية المشفرة.\n\nيقوم مسؤولو التدقيق والتحقق بفحص الطلب وسنوافيك بالرد خلال ساعتين إلى 4 ساعات.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              // Navigate directly to the pending approval gate
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const DriverPendingScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('متابعة حالة الطلب', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.roseGold.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Text(
              'Rafik | كابتن رفيق',
              style: TextStyle(
                color: Color(0xFFFCE4E6),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step Progress Indicator
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  _buildStepIndicator(0, 'بيانات المركبة'),
                  Container(
                    width: 24,
                    height: 1,
                    color: _currentStep >= 1 ? AppTheme.roseGold : Colors.white24,
                  ),
                  _buildStepIndicator(1, 'خزنة المستندات الـ6'),
                ],
              ),
            ),

            if (_isSubmitting) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgressPercent,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.roseGold),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploadProgressText,
                      style: const TextStyle(color: AppTheme.roseGoldLight, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _currentStep == 0 ? _buildVehicleForm() : _buildDocumentVault(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Center(
                child: Text(
                  'All rights reserved to Rafik 2026 • جميع الحقوق محفوظة لـ رفيق 2026',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 8.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? AppTheme.sageSafe
                  : (isActive ? AppTheme.roseGold : Colors.transparent),
              border: Border.all(
                color: isDone || isActive ? Colors.transparent : Colors.white24,
              ),
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.white54,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PillBadge(
          label: 'توثيق الكابتن — المرحلة الأولى',
          variant: PillBadgeVariant.roseGold,
        ),
        const SizedBox(height: 12),
        const Text(
          'بيانات المركبة ورخصة القيادة',
          style: TextStyle(
            color: Color(0xFFFCE4E6),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'أدخل بيانات السيارة المقيدة باسمك أو بعقد إيجار رسمي.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _vehicleMakeController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'ماركة السيارة (Make)',
            hintText: 'مثال: هيونداي، تويوتا، كيا، نيسان',
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _vehicleModelController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'موديل السيارة (Model)',
            hintText: 'مثال: إلنترا، ياريس، سيراتو، صني',
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              flex: 1,
              child: TextField(
                controller: _vehicleYearController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'سنة الصنع',
                  hintText: '2022',
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _plateNumberController,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'رقم اللوحة المعدنية',
                  hintText: 'س ن ق 1 4 2 9',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _vehicleColorController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'لون السيارة',
            hintText: 'أبيض / لؤلؤي / أسود / فضي',
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _nationalIdController,
          keyboardType: TextInputType.number,
          maxLength: 14,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'الرقم القومي المصري (14 رقماً)',
            hintText: '2990101XXXXXXXXX',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _licenseNumberController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'رقم رخصة القيادة',
            hintText: 'رقم الرخصة القومية',
          ),
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (_vehicleMakeController.text.trim().isEmpty ||
                  _vehicleModelController.text.trim().isEmpty ||
                  _plateNumberController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى ملء جميع بيانات المركبة المطلوبة.'),
                    backgroundColor: AppTheme.berryCore,
                  ),
                );
                return;
              }
              setState(() => _currentStep = 1);
            },
            child: const Text('المتابعة إلى خزنة المستندات الـ6 ➔'),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentVault() {
    final completedCount = _uploadedDocs.values.where((v) => v).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const PillBadge(
              label: 'خزنة التوثيق الثنائية الوجه',
              variant: PillBadgeVariant.sage,
            ),
            Text(
              '$completedCount / 6 أوجه مكتملة',
              style: const TextStyle(
                color: AppTheme.roseGoldLight,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'تصوير المستندات الرسمية',
          style: TextStyle(
            color: Color(0xFFFCE4E6),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'طبقاً لمعايير الأمان الوطنية المصرية، يرجى تصوير الوجهين الأمامي والخلفي بوضوح تام.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
        ),
        const SizedBox(height: 20),

        // Section 1: Egyptian National ID (Front + Back)
        _buildDocCategoryHeader('1. بطاقة الرقم القومي (National ID Card)'),
        Row(
          children: [
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الأمامي',
                subtitle: 'الصورة والرقم القومي',
                docKey: 'national_id_front',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الخلفي',
                subtitle: 'الجنس والمهنة',
                docKey: 'national_id_back',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Section 2: Driver's License (Front + Back)
        _buildDocCategoryHeader('2. رخصة القيادة الخاصة (Driver License)'),
        Row(
          children: [
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الأمامي',
                subtitle: 'تاريخ السريان والدرجة',
                docKey: 'driver_license_front',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الخلفي',
                subtitle: 'وحدة المرور والتأشيرات',
                docKey: 'driver_license_back',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Section 3: Vehicle Registration (Front + Back)
        _buildDocCategoryHeader('3. رخصة تسيير المركبة - الملكية (Vehicle Reg)'),
        Row(
          children: [
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الأمامي',
                subtitle: 'بيانات الشاسيه والموتور',
                docKey: 'vehicle_reg_front',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDocUploadCard(
                title: 'الوجه الخلفي',
                subtitle: 'الفحص والضريبة',
                docKey: 'vehicle_reg_back',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Action Buttons
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 0),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitApplication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: completedCount == 6 ? AppTheme.sageSafe : AppTheme.roseGold,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('إرسال وتأكيد التوثيق الـ6 ➔', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDocCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.roseGoldLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDocUploadCard({
    required String title,
    required String subtitle,
    required String docKey,
  }) {
    final isUploaded = _uploadedDocs[docKey] ?? false;

    return GestureDetector(
      onTap: () => _captureDocument(docKey, title),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUploaded
              ? AppTheme.sageSafe.withValues(alpha: 0.12)
              : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUploaded
                ? AppTheme.sageSafe
                : AppTheme.roseGold.withValues(alpha: 0.25),
            width: isUploaded ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isUploaded ? Icons.check_circle_outline : Icons.document_scanner_outlined,
              color: isUploaded ? AppTheme.sageSafe : AppTheme.roseGold,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isUploaded ? AppTheme.sageSafe : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isUploaded
                    ? AppTheme.sageSafe.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isUploaded ? 'تم الالتقاط' : 'اضغط للتصوير',
                style: TextStyle(
                  color: isUploaded ? AppTheme.sageSafe : AppTheme.roseGoldLight,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
