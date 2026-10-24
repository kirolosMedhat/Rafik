import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  double _todayEarnings = 680.00;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    final earnings = await PersistentStorage.getDriverEarnings();
    if (mounted) {
      setState(() {
        _todayEarnings = earnings;
        _isLoading = false;
      });
    }
  }

  void _requestPayout(String method) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          'Withdraw via $method',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Balance: ${_todayEarnings.toStringAsFixed(2)} LE',
              style: const TextStyle(color: AppTheme.roseGold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Funds will be transferred instantly to your verified Egyptian account with zero platform commission fee.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payout request of ${_todayEarnings.toStringAsFixed(2)} LE initiated via $method!'),
                  backgroundColor: AppTheme.sageSafe,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRM TRANSFER'),
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.roseGold),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Earnings & Wallet (الأرباح والمحفظة)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: PillBadge(
                text: '0% COMMISSION',
                textColor: AppTheme.sageSafe,
                bgColor: Color(0x1F6B8E23),
                borderColor: Color(0x3D6B8E23),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.roseGold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total Earnings Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E121B), Color(0xFF1A0A10)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.roseGold.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TODAY NET EARNINGS',
                              style: TextStyle(
                                color: AppTheme.roseGold,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            PillBadge(
                              text: 'ACTIVE SHIFT',
                              textColor: AppTheme.sageSafe,
                              bgColor: Color(0x1F6B8E23),
                              borderColor: Color(0x3D6B8E23),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _todayEarnings.toStringAsFixed(2),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'LE (EGP)',
                              style: TextStyle(
                                color: AppTheme.roseGold,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'All payouts settled with 0% platform deduction under the graduation project guarantee.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Metrics Grid
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          title: 'COMPLETED TRIPS',
                          value: '4 Trips',
                          subtitle: '100% On-time',
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          title: 'ACCEPTANCE RATE',
                          value: '100%',
                          subtitle: 'Zero cancellations',
                          icon: Icons.speed_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          title: 'SAFETY SCORE',
                          value: '4.96 ★',
                          subtitle: 'Verified Safe Captain',
                          icon: Icons.shield_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          title: 'DISTANCE DRIVEN',
                          value: '68.4 km',
                          subtitle: 'Cairo & Giza routes',
                          icon: Icons.route_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Payout Withdrawal Methods
                  const Text(
                    'INSTANT WITHDRAWAL CHANNELS',
                    style: TextStyle(
                      color: AppTheme.roseGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _payoutChannelCard(
                    title: 'InstaPay IPA Transfer',
                    subtitle: 'Instant direct transfer to your Egyptian bank or Meeza card',
                    badge: 'INSTANT • 0% FEE',
                    icon: Icons.flash_on_rounded,
                    onTap: () => _requestPayout('InstaPay'),
                  ),

                  _payoutChannelCard(
                    title: 'Vodafone Cash / Orange Money',
                    subtitle: 'Transfer directly to your registered Egyptian mobile wallet',
                    badge: 'MOBILE WALLET',
                    icon: Icons.phone_android_rounded,
                    onTap: () => _requestPayout('Vodafone Cash'),
                  ),

                  _payoutChannelCard(
                    title: 'Direct Bank Wire (IBAN)',
                    subtitle: 'National Bank of Egypt (NBE) / CIB / Banque Misr',
                    badge: 'SAME DAY',
                    icon: Icons.account_balance_rounded,
                    onTap: () => _requestPayout('Bank Wire'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.roseGold, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _payoutChannelCard({
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.roseGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.roseGold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      PillBadge(
                        text: badge,
                        textColor: AppTheme.sageSafe,
                        bgColor: const Color(0x1F6B8E23),
                        borderColor: const Color(0x3D6B8E23),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.roseGold, size: 14),
          ],
        ),
      ),
    );
  }
}
