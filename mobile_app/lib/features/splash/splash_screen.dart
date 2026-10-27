import 'package:flutter/material.dart';

/// Go Safe (جو سيف) — Native 60fps Animated Splash Intro
/// Features a smooth physics-based Shield & Chevron navigation beacon,
/// followed by the expansion of the brand wordmark and Arabic typography.
/// All rights reserved to Go Safe 2026.
class GoSafeSplashScreen extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const GoSafeSplashScreen({
    super.key,
    required this.onAnimationComplete,
  });

  @override
  State<GoSafeSplashScreen> createState() => _GoSafeSplashScreenState();
}

typedef RafikSplashScreen = GoSafeSplashScreen;

class _GoSafeSplashScreenState extends State<GoSafeSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pinDropAnimation;
  late Animation<double> _rScaleAnimation;
  late Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 1. Beacon Drop / Glide: 0ms to 700ms with elastic bounce
    _pinDropAnimation = Tween<double>(begin: -80.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.bounceOut),
      ),
    );

    // 2. Shield & Arrow Expansion: 300ms to 900ms
    _rScaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Typography Reveal: 700ms to 1400ms
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.85, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onAnimationComplete();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF12080C);
    const roseGold = Color(0xFFB76E79);
    const softRose = Color(0xFFE8B4B8);
    const sageSafe = Color(0xFF80ED99);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Animated Go Safe Emblem
                  Transform.scale(
                    scale: _rScaleAnimation.value,
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Vector Shield & Chevron
                          CustomPaint(
                            size: const Size(140, 140),
                            painter: GoSafeLogoPainter(color: roseGold),
                          ),
                          // Dropping Emerald Safe Beacon
                          Transform.translate(
                            offset: Offset(26, _pinDropAnimation.value),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: sageSafe,
                                boxShadow: [
                                  BoxShadow(
                                    color: sageSafe,
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Fading Brand Typography
                  Opacity(
                    opacity: _textFadeAnimation.value,
                    child: Column(
                      children: [
                        const Text(
                          'GO SAFE',
                          style: TextStyle(
                            color: Color(0xFFFCE4E6),
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'جو سِـــيف',
                          style: TextStyle(
                            color: softRose,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'VERIFIED • SECURE • REAL-TIME MOBILITY',
                          style: TextStyle(
                            color: roseGold.withValues(alpha: 0.85),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Copyright Footer
                  Opacity(
                    opacity: _textFadeAnimation.value,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Column(
                        children: [
                          const Text(
                            'All rights reserved to Go Safe 2026',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'جميع الحقوق محفوظة لـ جو سيف 2026',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Custom Vector Painter for the Go Safe Shield & Chevron Emblem
class GoSafeLogoPainter extends CustomPainter {
  final Color color;

  GoSafeLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final sx = size.width / 512;
    final sy = size.height / 512;

    // Protective Shield
    final shieldPath = Path()
      ..moveTo(256 * sx, 70 * sy)
      ..cubicTo(335 * sx, 70 * sy, 395 * sx, 110 * sy, 410 * sx, 180 * sy)
      ..cubicTo(410 * sx, 300 * sy, 345 * sx, 380 * sy, 256 * sx, 435 * sy)
      ..cubicTo(167 * sx, 380 * sy, 102 * sx, 300 * sy, 102 * sx, 180 * sy)
      ..cubicTo(117 * sx, 110 * sy, 177 * sx, 70 * sy, 256 * sx, 70 * sy)
      ..close();

    canvas.drawPath(shieldPath, fillPaint);
    canvas.drawPath(shieldPath, strokePaint);

    // Forward "Go" Chevron
    final chevronPath = Path()
      ..moveTo(195 * sx, 180 * sy)
      ..lineTo(290 * sx, 248 * sy)
      ..lineTo(195 * sx, 316 * sy);

    final chevronPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(chevronPath, chevronPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

typedef RafikLogoPainter = GoSafeLogoPainter;
