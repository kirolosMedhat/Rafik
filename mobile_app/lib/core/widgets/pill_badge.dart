import 'package:flutter/material.dart';

enum PillBadgeVariant { roseGold, sage, dark }

/// Signature Pill-Badge Widget matching Rafik design specifications
class PillBadge extends StatelessWidget {
  final String? label;
  final String? text;
  final Widget? leadingIcon;
  final PillBadgeVariant variant;
  final Color? textColor;
  final Color? bgColor;
  final Color? borderColor;

  const PillBadge({
    super.key,
    this.label,
    this.text,
    this.leadingIcon,
    this.variant = PillBadgeVariant.roseGold,
    this.textColor,
    this.bgColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color textCol;

    switch (variant) {
      case PillBadgeVariant.sage:
        bg = bgColor ?? const Color(0xFF3E7A54).withValues(alpha: 0.12);
        border = borderColor ?? const Color(0xFF3E7A54);
        textCol = textColor ?? const Color(0xFF88D4A2);
        break;
      case PillBadgeVariant.dark:
        bg = bgColor ?? Colors.black.withValues(alpha: 0.4);
        border = borderColor ?? const Color(0xFFB76E79).withValues(alpha: 0.3);
        textCol = textColor ?? const Color(0xFFE8B4B8);
        break;
      case PillBadgeVariant.roseGold:
        bg = bgColor ?? const Color(0xFFB76E79).withValues(alpha: 0.12);
        border = borderColor ?? const Color(0xFFB76E79);
        textCol = textColor ?? const Color(0xFFFCE4E6);
        break;
    }

    final String displayLabel = (label ?? text ?? '').toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            leadingIcon!,
            const SizedBox(width: 4),
          ],
          Text(
            displayLabel,
            style: TextStyle(
              color: textCol,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
