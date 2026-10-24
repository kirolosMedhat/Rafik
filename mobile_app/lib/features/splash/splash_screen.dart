import 'package:flutter/material.dart';

/// Rafik (رفيق) — Native 60fps Animated Splash Intro
/// Features a smooth physics-based Pin drop into the counter gap of the letter 'R',
/// followed by the expansion of the brand wordmark and Arabic typography.
/// All rights reserved to Rafik 2026.
class RafikSplashScreen extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const RafikSplashScreen({
    super.key,
    required this.onAnimationComplete,
  });

  @override
  State<RafikSplashScreen> createState() => _RafikSplashScreenState();
}

class _RafikSplashScreenState extends State<RafikSplashScreen>
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
      duration: const Duration(milliseconds: 2400),
    );

    // 1. Pin Drop: 0ms to 900ms with elastic bounce
    _pinDropAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.bounceOut),
      ),
    );

    // 2. Letter 'R' Expansion: 400ms to 1200ms
    _rScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Typography Reveal: 1000ms to 1800ms
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 0.85, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
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

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              children: [
                const Spacer(),
                // Animated Pin-in-R Monogram
                Transform.scale(
                  scale: _rScaleAnimation.value,
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Static Letter R Silhouette
                        CustomPaint(
                          size: const Size(140, 140),
                          painter: RafikLogoPainter(color: roseGold),
                        ),
                        // Dropping Location Pin
                        Transform.translate(
                          offset: Offset(0, _pinDropAnimation.value),
                          child: Container(
                            width: 32,
                            height: 42,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: softRose,
                            ),
                            child: const Center(
                              child: CircleAvatar(
                                radius: 5,
                                backgroundColor: bgColor,
                              ),
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
                        'RAFIK',
                        style: TextStyle(
                          color: Color(0xFFFCE4E6),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'رَفِـــيــق',
                        style: TextStyle(
                          color: softRose,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'SMART & SAFE MOBILITY',
                        style: TextStyle(
                          color: roseGold.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.5,
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
                          'All rights reserved to Rafik 2026',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'جميع الحقوق محفوظة لـ رفيق 2026',
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
    );
  }
}

/// Custom Vector Painter for the Rafik Pin-in-R Monogram
class RafikLogoPainter extends CustomPainter {
  final Color color;

  RafikLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Scale factors from 512x512 vector coordinates
    final sx = size.width / 512;
    final sy = size.height / 512;

    final path = Path()
      ..moveTo(130 * sx, 110 * sy)
      ..lineTo(280 * sx, 110 * sy)
      ..cubicTo(360 * sx, 110 * sy, 410 * sx, 155 * sy, 410 * sx, 230 * sy)
      ..cubicTo(410 * sx, 290 * sy, 368 * sx, 332 * sy, 310 * sx, 342 * sy)
      ..lineTo(410 * sx, 430 * sy)
      ..lineTo(340 * sx, 430 * sy)
      ..lineTo(248 * sx, 344 * sy)
      ..lineTo(196 * sx, 344 * sy)
      ..lineTo(196 * sx, 430 * sy)
      ..lineTo(130 * sx, 430 * sy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
