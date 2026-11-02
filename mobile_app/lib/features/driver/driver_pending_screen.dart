import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../auth/auth_screen.dart';
import 'driver_radar_screen.dart';
import 'driver_rejected_screen.dart';

/// Rafik Captain — Dedicated Driver Pending Review Screen
///
/// Displayed when a newly registered or re-submitted captain account has `status == 'pending'`.
/// Listens to real-time Firestore updates so that when an administrator approves or rejects
/// the application, the UI transitions automatically without requiring an app restart.
class DriverPendingScreen extends StatefulWidget {
  const DriverPendingScreen({super.key});

  @override
  State<DriverPendingScreen> createState() => _DriverPendingScreenState();
}

class _DriverPendingScreenState extends State<DriverPendingScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _listenToApprovalStatus();
  }

  void _listenToApprovalStatus() {
    final uid = FirebaseService().currentUser?.uid;
    if (uid == null) return;

    _statusSubscription = FirebaseService().streamDriverProfile(uid).listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
      final status = data?['status']?.toString().toLowerCase();

      if (status == 'approved') {
        HapticFeedback.heavyImpact();
        _statusSubscription?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('مبروك! تمت الموافقة على حسابك بنجاح. مرحباً بك في أسطول رفيق.'),
              backgroundColor: AppTheme.sageSafe,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DriverRadarScreen()),
            (route) => false,
          );
        }
      } else if (status == 'rejected') {
        _statusSubscription?.cancel();
        if (mounted) {
          final reason = data?['rejection_reason']?.toString() ??
              'لم تستوفِ بعض المستندات شروط التوثيق المعتمدة.';
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => DriverRejectedScreen(rejectionReason: reason),
            ),
            (route) => false,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleSignOut() async {
    setState(() => _isSigningOut = true);
    try {
      await FirebaseService().signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const AuthScreen(initialRole: 'driver', initialIsDriver: true),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse('tel:19999');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService().currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F080D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'حالة الطلب',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: _isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                : const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: _isSigningOut ? null : _handleSignOut,
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid.isNotEmpty ? FirebaseService().streamDriverProfile(uid) : null,
          builder: (context, snapshot) {
            final driverData = snapshot.data?.data() ?? {};
            final documents = (driverData['documents'] as Map<String, dynamic>?) ?? {};

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  // Animated Pulsing Hourglass Icon
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppTheme.roseGold.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.roseGold.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          color: AppTheme.roseGold,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title & Subtitle
                  const Center(
                    child: PillBadge(
                      label: 'طلب الانضمام قيد المراجعة',
                      variant: PillBadgeVariant.roseGold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'طلبك قيد المراجعة والتدقيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'يقوم فريق عمليات رفيق بفحص بياناتك ومستنداتك للتأكد من مطابقتها لأعلى معايير الأمان والسلامة.\nتستغرق المراجعة عادة بين ساعتين إلى 4 ساعات عمل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Submitted Documents Checklist Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF190D14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF2E1724),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: AppTheme.roseGold,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'مستندات التوثيق الستة المرفوعة',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildDocItem(
                          title: 'بطاقة الرقم القومي (الوجه الأمامي)',
                          subtitle: 'National ID (Front)',
                          isUploaded: documents['national_id_front'] != null ||
                              driverData['national_id_number'] != null,
                        ),
                        const Divider(color: Color(0xFF2E1724), height: 20),
                        _buildDocItem(
                          title: 'بطاقة الرقم القومي (الوجه الخلفي)',
                          subtitle: 'National ID (Back)',
                          isUploaded: documents['national_id_back'] != null,
                        ),
                        const Divider(color: Color(0xFF2E1724), height: 20),
                        _buildDocItem(
                          title: 'رخصة القيادة (الوجه الأمامي)',
                          subtitle: 'Driver License (Front)',
                          isUploaded: documents['driver_license_front'] != null ||
                              driverData['license_number'] != null,
                        ),
                        const Divider(color: Color(0xFF2E1724), height: 20),
                        _buildDocItem(
                          title: 'رخصة القيادة (الوجه الخلفي)',
                          subtitle: 'Driver License (Back)',
                          isUploaded: documents['driver_license_back'] != null,
                        ),
                        const Divider(color: Color(0xFF2E1724), height: 20),
                        _buildDocItem(
                          title: 'رخصة تسيير المركبة (الوجه الأمامي)',
                          subtitle: 'Vehicle Registration (Front)',
                          isUploaded: documents['vehicle_reg_front'] != null ||
                              driverData['vehicle_plate'] != null,
                        ),
                        const Divider(color: Color(0xFF2E1724), height: 20),
                        _buildDocItem(
                          title: 'رخصة تسيير المركبة (الوجه الخلفي)',
                          subtitle: 'Vehicle Registration (Back)',
                          isUploaded: documents['vehicle_reg_back'] != null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Commission Feature Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.roseGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.roseGold.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.roseGold.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.monetization_on_outlined,
                            color: AppTheme.roseGold,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '0% عمولة للمنصة — أرباحك 100% لك',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'فور اعتماد حسابك، ستبدأ باستقبال المشاوير مباشرة والاحتفاظ بكامل الأجرة.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Contact Support Button
                  OutlinedButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.headset_mic_outlined, size: 20),
                    label: const Text('تواصل مع فريق الدعم والمساعدة'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF381B2B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sign Out Link
                  TextButton(
                    onPressed: _isSigningOut ? null : _handleSignOut,
                    child: const Text(
                      'تسجيل الخروج والعودة لاحقاً',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDocItem({
    required String title,
    required String subtitle,
    required bool isUploaded,
  }) {
    return Row(
      children: [
        Icon(
          isUploaded ? Icons.check_circle_rounded : Icons.pending_outlined,
          color: isUploaded ? AppTheme.sageSafe : AppTheme.roseGold,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isUploaded
                ? AppTheme.sageSafe.withValues(alpha: 0.15)
                : AppTheme.roseGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            isUploaded ? 'تم الاستلام' : 'قيد الفحص',
            style: TextStyle(
              color: isUploaded ? AppTheme.sageSafe : AppTheme.roseGold,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
