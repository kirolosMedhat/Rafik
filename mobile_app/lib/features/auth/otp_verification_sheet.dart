import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class OtpVerificationSheet extends StatefulWidget {
  final String phoneNumber;
  final String userName;
  final String role; // 'rider' or 'driver'
  final String gender; // 'female' or 'male'
  final bool uperGirlEnabled;
  final VoidCallback onVerified;

  const OtpVerificationSheet({
    super.key,
    required this.phoneNumber,
    required this.userName,
    required this.role,
    this.gender = 'female',
    this.uperGirlEnabled = true,
    required this.onVerified,
  });

  @override
  State<OtpVerificationSheet> createState() => _OtpVerificationSheetState();
}

class _OtpVerificationSheetState extends State<OtpVerificationSheet> {
  final List<TextEditingController> _pinControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  int _resendCountdown = 30;
  Timer? _timer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendCountdown = 30);
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
    final enteredPin = _pinControllers.map((c) => c.text).join();
    if (enteredPin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 4-digit verification code.'),
          backgroundColor: AppTheme.berryCore,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);
    HapticFeedback.mediumImpact();

    // Committee Demo Bypass: Any 4-digit code (e.g. 1234 or entered PIN) passes
    await Future.delayed(const Duration(milliseconds: 600));

    // Save persistent user session
    await PersistentStorage.saveUserSession(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      name: widget.userName,
      phone: widget.phoneNumber,
      role: widget.role,
      gender: widget.gender,
      uperGirlEnabled: widget.uperGirlEnabled,
    );

    if (mounted) {
      Navigator.pop(context);
      widget.onVerified();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header Badge
          const PillBadge(
            text: 'SECURE PHONE AUTHENTICATION',
            textColor: AppTheme.roseGold,
            bgColor: Color(0x1FB76E79),
            borderColor: Color(0x3DB76E79),
          ),
          const SizedBox(height: 12),

          const Text(
            'Enter SMS Verification Code',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We sent a 4-digit OTP to +20 ${widget.phoneNumber}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '(Demo bypass code: 1234)',
            style: TextStyle(color: AppTheme.sageSafe, fontSize: 11, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 24),

          // 4-Digit Input Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return Container(
                width: 54,
                height: 58,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: TextField(
                  controller: _pinControllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF1B0E14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.roseGold, width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && index < 3) {
                      _focusNodes[index + 1].requestFocus();
                    } else if (val.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                    if (index == 3 && val.isNotEmpty) {
                      _verifyOtp();
                    }
                  },
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          // Resend or Timer
          _resendCountdown > 0
              ? Text(
                  'Resend code in $_resendCountdown seconds',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                )
              : TextButton(
                  onPressed: _startCountdown,
                  child: const Text(
                    'RESEND CODE NOW',
                    style: TextStyle(
                      color: AppTheme.roseGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

          const SizedBox(height: 20),

          // Verify Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isVerifying ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.roseGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                    )
                  : const Text(
                      'VERIFY & CONTINUE',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
