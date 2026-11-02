import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_number_utils.dart';
import '../../core/widgets/pill_badge.dart';

/// Rafik (رفيق) — Real Firebase Phone Authentication OTP Verification Sheet
///
/// Features:
/// - Real SMS OTP verification via FirebaseAuth.instance.signInWithCredential
/// - 6-digit individual input fields with auto-advance and backspace handling
/// - 60-second resend countdown using forceResendingToken
/// - Full Egyptian Arabic & English localized error handling
/// - Zero mock/dummy backdoor codes
class OtpVerificationSheet extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final String gender; // 'female' or 'male'
  final bool isArabic;
  final void Function(UserCredential credential) onVerified;

  const OtpVerificationSheet({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.gender = 'female',
    this.isArabic = true,
    required this.onVerified,
  });

  @override
  State<OtpVerificationSheet> createState() => _OtpVerificationSheetState();
}

class _OtpVerificationSheetState extends State<OtpVerificationSheet> {
  final List<TextEditingController> _pinControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  int? _currentResendToken;

  int _resendCountdown = 60;
  Timer? _timer;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _currentResendToken = widget.resendToken;
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendCountdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final enteredPin = _pinControllers.map((c) => c.text).join().trim();
    if (enteredPin.length < 6) {
      setState(() {
        _errorMessage = widget.isArabic
            ? 'يرجى إدخال رمز التحقق المكون من 6 أرقام بالكامل'
            : 'Please enter the complete 6-digit verification code';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      final credential = await FirebaseService().verifyPhoneOtp(
        verificationId: _currentVerificationId,
        smsCode: enteredPin,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onVerified(credential);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[PhoneAuth] verifyOtp FirebaseAuthException: [${e.code}] ${e.message}');
      String msg;
      switch (e.code) {
        case 'invalid-verification-code':
          msg = widget.isArabic
              ? 'رمز التحقق غير صحيح. يرجى التأكد وإعادة المحاولة.'
              : 'Invalid verification code. Please check and try again.';
          break;
        case 'session-expired':
          msg = widget.isArabic
              ? 'انتهت صلاحية رمز التحقق. يرجى طلب رمز جديد.'
              : 'Verification code expired. Please request a new code.';
          break;
        case 'network-request-failed':
          msg = widget.isArabic
              ? 'خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت.'
              : 'Network error. Please check your internet connection.';
          break;
        case 'too-many-requests':
          msg = widget.isArabic
              ? 'تم تجاوز عدد المحاولات المسموح بها. يرجى الانتظار قليلاً.'
              : 'Too many attempts. Please try again later.';
          break;
        default:
          msg = widget.isArabic
              ? 'فشل التحقق من الرمز: ${e.message ?? e.code}'
              : 'Verification failed: ${e.message ?? e.code}';
      }

      if (mounted) {
        setState(() {
          _errorMessage = msg;
          _isVerifying = false;
        });
      }
    } catch (e) {
      debugPrint('[PhoneAuth] verifyOtp generic error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resendCountdown > 0) return;
    setState(() => _errorMessage = null);

    try {
      await FirebaseService().sendPhoneOtp(
        rawPhone: widget.phoneNumber,
        forceResendingToken: _currentResendToken,
        onCodeSent: (newVerificationId, newResendToken) {
          if (mounted) {
            setState(() {
              _currentVerificationId = newVerificationId;
              _currentResendToken = newResendToken;
            });
            _startCountdown();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  widget.isArabic
                      ? 'تم إرسال رمز تحقق جديد عبر رسالة SMS'
                      : 'A new verification code has been dispatched via SMS.',
                ),
                backgroundColor: AppTheme.sageSafe,
              ),
            );
          }
        },
        onVerificationFailed: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = widget.isArabic
                  ? 'فشل إرسال الرسالة: ${e.message}'
                  : 'Failed to send SMS: ${e.message ?? e.code}';
            });
          }
        },
        onVerificationCompleted: (credential) async {
          // Instant auto-retrieval
          try {
            final authCred = await FirebaseService().auth.signInWithCredential(credential);
            if (mounted) {
              Navigator.pop(context);
              widget.onVerified(authCred);
            }
          } catch (_) {}
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMale = widget.gender == 'male';
    final accentColor = isMale ? const Color(0xFF3B82F6) : AppTheme.roseGold;
    final displayPhone = PhoneNumberUtils.formatForDisplay(widget.phoneNumber);

    return Directionality(
      textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF141419),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PillBadge(
                  label: widget.isArabic ? 'التحقق عبر SMS' : 'SMS VERIFICATION',
                  variant: isMale ? PillBadgeVariant.dark : PillBadgeVariant.roseGold,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              widget.isArabic ? 'أدخل رمز التحقق' : 'Enter Verification Code',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isArabic
                  ? 'تم إرسال كود مكوّن من 6 أرقام إلى $displayPhone'
                  : 'We sent a 6-digit verification code to $displayPhone',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),

            const SizedBox(height: 24),

            // PIN Input Fields (6-digit)
            Directionality(
              textDirection: TextDirection.ltr, // Keep digits LTR
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 44,
                    height: 52,
                    child: TextField(
                      controller: _pinControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLength: 1,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFF1E1E26),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: accentColor, width: 2),
                        ),
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty && index < 5) {
                          _focusNodes[index + 1].requestFocus();
                        } else if (val.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        if (index == 5 && val.isNotEmpty) {
                          _verifyOtp();
                        }
                      },
                    ),
                  );
                }),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFE11D48),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Verify Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: isMale ? Colors.white : Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        widget.isArabic ? 'تأكيد ومتابعة' : 'Verify & Continue',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Resend Timer
            Center(
              child: TextButton(
                onPressed: _resendCountdown == 0 ? _resendCode : null,
                child: Text(
                  _resendCountdown > 0
                      ? (widget.isArabic
                          ? 'إعادة إرسال الرمز خلال $_resendCountdown ثانية'
                          : 'Resend code in ${_resendCountdown}s')
                      : (widget.isArabic
                          ? 'إعادة إرسال رمز التحقق'
                          : 'Resend Verification Code'),
                  style: TextStyle(
                    color: _resendCountdown == 0 ? accentColor : Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
