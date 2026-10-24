import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class SafetyShieldSheet extends StatefulWidget {
  final String? activeRideId;
  final String? driverName;
  final String? vehicleInfo;
  final String? pickupName;
  final String? dropoffName;
  final String? safetyPin;

  const SafetyShieldSheet({
    super.key,
    this.activeRideId,
    this.driverName,
    this.vehicleInfo,
    this.pickupName,
    this.dropoffName,
    this.safetyPin,
  });

  @override
  State<SafetyShieldSheet> createState() => _SafetyShieldSheetState();
}

class _SafetyShieldSheetState extends State<SafetyShieldSheet> {
  final List<Map<String, String>> _contacts = [
    {'name': 'Nabila (Mother)', 'phone': '01012345678', 'relation': 'Mother'},
    {'name': 'Salma (Sister)', 'phone': '01298765432', 'relation': 'Sister'},
  ];

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
  }

  Future<void> _loadEmergencyContacts() async {
    final fetched = await SupabaseService().getEmergencyContacts();
    if (fetched.isNotEmpty && mounted) {
      setState(() {
        _contacts.clear();
        for (final c in fetched) {
          _contacts.add({
            'name': c['contact_name']?.toString() ?? 'Contact',
            'phone': c['contact_phone']?.toString() ?? '',
            'relation': c['relationship']?.toString() ?? 'Family',
          });
        }
      });
    }
  }

  Future<void> _shareTripWhatsApp() async {
    HapticFeedback.mediumImpact();
    final text = 'Rafik Safe Ride Alert (رِفـــقَــة):\n'
        'I am on my way home with verified female Captain ${widget.driverName ?? "Rafik Captain"} '
        '(${widget.vehicleInfo ?? "Toyota Yaris"}).\n'
        'From: ${widget.pickupName ?? "Zamalek"}\n'
        'To: ${widget.dropoffName ?? "New Cairo"}\n'
        'Safety Handshake PIN: ${widget.safetyPin ?? "7429"}\n'
        'Track my live ride: https://rafik.app/track/${widget.activeRideId ?? "demo"}';

    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      }
    }
  }

  void _callPolice122() async {
    HapticFeedback.heavyImpact();
    final uri = Uri.parse('tel:122');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relationCtrl = TextEditingController(text: 'Sister');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          'Add Trusted Safety Contact',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Egyptian Phone (e.g. 010xxxxxxxx)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Relationship (Mother / Sister / Husband)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                setState(() {
                  _contacts.add({
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'relation': relationCtrl.text.trim(),
                  });
                });
                await SupabaseService().addEmergencyContact(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  relationship: relationCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('SAVE CONTACT'),
          ),
        ],
      ),
    );
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
          // Drag Handle
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RAFIK SAFETY SHIELD',
                    style: TextStyle(
                      color: AppTheme.roseGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Passenger Safety Controls',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              PillBadge(
                text: '24/7 MONITORED',
                textColor: AppTheme.sageSafe,
                bgColor: Color(0x1F6B8E23),
                borderColor: Color(0x3D6B8E23),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Action 1: Share Live Trip
          GestureDetector(
            onTap: _shareTripWhatsApp,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.roseGold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.roseGold.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.roseGold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.share_location_rounded, color: AppTheme.roseGold),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Live Ride with Family',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'مشاركة مسار الرحلة وبيانات الكابتن عبر الواتساب',
                          style: TextStyle(
                            color: AppTheme.roseGold,
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sends route link, car plate & driver name instantly',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.roseGold, size: 16),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Action 2: Emergency 122 Police Call
          GestureDetector(
            onTap: _callPolice122,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.alertSos.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.alertSos.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.alertSos.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.emergency_rounded, color: AppTheme.alertSos),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Assistance (Police 122)',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'طوارئ الشرطة المصرية 122 وخدمة التدخل السريع',
                          style: TextStyle(
                            color: AppTheme.alertSos,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PillBadge(
                    text: 'SOS 122',
                    textColor: AppTheme.alertSos,
                    bgColor: Color(0x1FE53935),
                    borderColor: Color(0x3DE53935),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Trusted Contacts Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRUSTED EMERGENCY CONTACTS',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              TextButton.icon(
                onPressed: _showAddContactDialog,
                icon: const Icon(Icons.add_rounded, color: AppTheme.roseGold, size: 16),
                label: const Text(
                  'ADD',
                  style: TextStyle(color: AppTheme.roseGold, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          ..._contacts.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF190C12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppTheme.sageSafe, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['name']!,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${c['relation']!} • ${c['phone']!}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const PillBadge(
                      text: 'ACTIVE NOTIFIER',
                      textColor: AppTheme.sageSafe,
                      bgColor: Color(0x1F6B8E23),
                      borderColor: Color(0x3D6B8E23),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
