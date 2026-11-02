import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../auth/auth_screen.dart';
import 'driver_onboarding_screen.dart';

/// Rafik Captain — Dedicated Driver Application Rejection Screen
///
/// Displayed when an administrator rejects a captain's intake application.
/// Shows the specific reason for rejection and provides an immediate path
/// to rectify and resubmit documentation.
class DriverRejectedScreen extends StatefulWidget {
  final String? rejectionReason;

  const DriverRejectedScreen({
    super.key,
    this.rejectionReason,
  });

  @override
  State<DriverRejectedScreen> createState() => _DriverRejectedScreenState();
}

class _DriverRejectedScreenState extends State<DriverRejectedScreen> {
  bool _isSigningOut = false;

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

  void _resubmitDocuments() {
    final uid = FirebaseService().currentUser?.uid;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverOnboardingScreen(
          driverId: uid,
          driverGender: 'female',
          isUperGirlEnrolled: true,
        ),
      ),
    );
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
    final reasonText = widget.rejectionReason?.trim().isNotEmpty == true
        ? widget.rejectionReason!
        : 'لم تستوفِ بعض المستندات أو البيانات المقدمة شروط التوثيق المعتمدة لمنصة رفيق.';

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Alert Hexagon / Warning Icon
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFE11D48),
                      size: 46,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Rejection Badge
              const Center(
                child: PillBadge(
                  label: 'تم رفض طلب الانضمام',
                  variant: PillBadgeVariant.dark,
                  borderColor: Color(0xFFE11D48),
                  textColor: Color(0xFFE11D48),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'يتطلب طلبك تعديل بعض المستندات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'راجع سبب الرفض الموضح أدناه، ويمكنك إعادة تصوير المستندات المطلوبة وإرسالها للمراجعة الفورية مجدداً.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),

              // Reason Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF210E15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.assignment_late_outlined,
                          color: Color(0xFFE11D48),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'ملاحظات مسؤول المراجعة والتدقيق',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      reasonText,
                      style: const TextStyle(
                        color: Color(0xFFFCE4E6),
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Action 1: Resubmit Documents Button
              ElevatedButton.icon(
                onPressed: _resubmitDocuments,
                icon: const Icon(Icons.upload_file_rounded, size: 20),
                label: const Text(
                  'إعادة رفع وتصوير المستندات',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.roseGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(height: 14),

              // Action 2: Contact Support
              OutlinedButton.icon(
                onPressed: _contactSupport,
                icon: const Icon(Icons.headset_mic_outlined, size: 18),
                label: const Text('التحدث مع مسؤول التوثيق'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF381B2B)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Action 3: Sign Out
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
        ),
      ),
    );
  }
}
