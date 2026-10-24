import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class OtpVerificationSheet extends StatefulWidget {
  final String phoneNumber;
  final String userName;
  final String role; // 'rider' or 'driver'
  final String gender; // 'female' or 'male'
  final VoidCallback onVerified;

  const OtpVerificationSheet({
    super.key,
    required this.phoneNumber,
    required this.userName,
    required this.role,
    this.gender = 'female',
    required this.onVerified,
  });

  @override
  State<OtpVerificationSheet> createState() => _OtpVerificationSheetState();
}

class _OtpVerificationSheetState extends State<OtpVerificationSheet> {
  final List<TextEditingController> _pinControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _resendCountdown = 60;
  Timer? _timer;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
    if (enteredPin.length < 4) {
      setState(() {
        _errorMessage = 'Please enter the complete verification code';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      final supabase = Supabase.instance.client;

      // Verify OTP through official Supabase Auth
      final response = await supabase.auth.verifyOTP(
        type: OtpType.sms,
        token: enteredPin,
        phone: widget.phoneNumber,
      );

      if (response.session != null && mounted) {
        Navigator.pop(context);
        widget.onVerified();
        return;
      }
    } catch (e) {
      debugPrint('[Auth] verifyOTP notice: $e');

      // Debug mode fallback for local testing with dummy/test phone numbers
      if (kDebugMode && (enteredPin == '1234' || enteredPin == '123456')) {
        try {
          // In debug mode, sign in with seeded test account
          final testEmail = '${widget.role}_${widget.gender}_test@rafik.internal';
          final authRes = await Supabase.instance.client.auth.signInWithPassword(
            email: testEmail,
            password: 'TestPassword123!',
          );
          if (authRes.session != null && mounted) {
            Navigator.pop(context);
            widget.onVerified();
            return;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid verification code. Please check and try again.';
          _isVerifying = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendCountdown > 0) return;
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: widget.phoneNumber,
      );
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new verification code has been dispatched via SMS.'),
            backgroundColor: AppTheme.sageSafe,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend SMS: $e'),
            backgroundColor: AppTheme.berryCore,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMale = widget.gender == 'male';
    final accentColor = isMale ? const Color(0xFF3B82F6) : AppTheme.roseGold;

    return Container(
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PillBadge(
                label: 'SMS VERIFICATION',
                variant: isMale ? PillBadgeVariant.dark : PillBadgeVariant.roseGold,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Text(
            'Enter Verification Code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'We sent a 6-digit verification code to ${widget.phoneNumber}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),

          const SizedBox(height: 24),

          // PIN Input Fields (6-digit)
          Row(
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
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE11D48), fontSize: 12, fontWeight: FontWeight.w600),
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
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text(
                      'Verify & Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    ? 'Resend code in ${_resendCountdown}s'
                    : 'Resend Verification Code',
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
    );
  }
}
