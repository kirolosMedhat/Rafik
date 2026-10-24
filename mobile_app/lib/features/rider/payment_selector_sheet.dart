import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

enum PaymentMethod { cash, instapay, vodafoneCash }

class PaymentMethodOption {
  final PaymentMethod method;
  final String title;
  final String titleAr;
  final String subtitle;
  final IconData icon;
  final String badgeText;

  const PaymentMethodOption({
    required this.method,
    required this.title,
    required this.titleAr,
    required this.subtitle,
    required this.icon,
    required this.badgeText,
  });
}

class PaymentSelectorSheet extends StatefulWidget {
  final PaymentMethod initialMethod;
  final double fareAmount;
  final Function(PaymentMethodOption) onSelect;

  const PaymentSelectorSheet({
    super.key,
    required this.initialMethod,
    required this.fareAmount,
    required this.onSelect,
  });

  @override
  State<PaymentSelectorSheet> createState() => _PaymentSelectorSheetState();
}

class _PaymentSelectorSheetState extends State<PaymentSelectorSheet> {
  late PaymentMethod _selectedMethod;

  final List<PaymentMethodOption> _options = const [
    PaymentMethodOption(
      method: PaymentMethod.cash,
      title: 'Cash Payment',
      titleAr: 'الدفع نقداً للسائقة',
      subtitle: 'Pay directly in Egyptian Pounds upon trip completion',
      icon: Icons.payments_outlined,
      badgeText: 'DIRECT CASH',
    ),
    PaymentMethodOption(
      method: PaymentMethod.instapay,
      title: 'InstaPay IPA Transfer',
      titleAr: 'تحويل انستاباي لحظي',
      subtitle: 'Instant Central Bank of Egypt transfer to driver IPA',
      icon: Icons.flash_on_rounded,
      badgeText: 'ZERO FEES',
    ),
    PaymentMethodOption(
      method: PaymentMethod.vodafoneCash,
      title: 'Smart Mobile Wallet',
      titleAr: 'محفظة إلكترونية (فودافون كاش)',
      subtitle: 'Transfer directly to driver registered mobile wallet',
      icon: Icons.account_balance_wallet_outlined,
      badgeText: 'E-WALLET',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialMethod;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      color: AppTheme.roseGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Select Settlement Mode',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.roseGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.roseGold.withOpacity(0.3)),
                ),
                child: Text(
                  '${widget.fareAmount.toStringAsFixed(2)} LE',
                  style: const TextStyle(
                    color: AppTheme.roseGold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Payment Options
          ..._options.map((opt) {
            final isSelected = opt.method == _selectedMethod;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedMethod = opt.method);
                widget.onSelect(opt);
                Navigator.pop(context);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.roseGold.withOpacity(0.12)
                      : const Color(0xFF1B0E14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.roseGold : Colors.white10,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.roseGold.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        opt.icon,
                        color: isSelected ? AppTheme.roseGold : AppTheme.textSecondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                opt.title,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PillBadge(
                                text: opt.badgeText,
                                textColor: isSelected ? AppTheme.roseGold : AppTheme.textSecondary,
                                bgColor: isSelected ? const Color(0x1FB76E79) : const Color(0x0FFFFFFF),
                                borderColor: isSelected ? const Color(0x3DB76E79) : const Color(0x1FFFFFFF),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opt.titleAr,
                            style: TextStyle(
                              color: AppTheme.roseGold.withOpacity(0.85),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opt.subtitle,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Radio<PaymentMethod>(
                      value: opt.method,
                      groupValue: _selectedMethod,
                      activeColor: AppTheme.roseGold,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedMethod = val);
                          widget.onSelect(opt);
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
