import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _trips = [];

  // Seeded Egyptian rides for instant demo display
  final List<Map<String, dynamic>> _demoTrips = [
    {
      'id': 'RIDE-1743019200',
      'created_at': 'Today, 11:20 AM',
      'pickup_address': 'Zamalek (26th July St)',
      'dropoff_address': 'New Cairo (5th Settlement - AUC)',
      'driver_name': 'Captain Yasmine El-Sayed',
      'vehicle_info': 'Toyota Yaris (س ن ق 1 4 2 9)',
      'distance_km': 28.4,
      'fare_amount': 299.00,
      'status': 'completed',
      'payment_method': 'Cash',
      'rating': 5.0,
    },
    {
      'id': 'RIDE-1742918400',
      'created_at': 'Yesterday, 04:45 PM',
      'pickup_address': 'Korba Square (Heliopolis)',
      'dropoff_address': 'Cairo International Airport (T3)',
      'driver_name': 'Captain Nourhan Fahmy',
      'vehicle_info': 'Hyundai Elantra (ق م د 3 9 1 2)',
      'distance_km': 14.2,
      'fare_amount': 157.00,
      'status': 'completed',
      'payment_method': 'InstaPay IPA',
      'rating': 5.0,
    },
    {
      'id': 'RIDE-1742817600',
      'created_at': '24 Sep, 08:15 PM',
      'pickup_address': 'Degla Square (Maadi)',
      'dropoff_address': 'Tahrir Square (Downtown)',
      'driver_name': 'Captain Dina Mansour',
      'vehicle_info': 'Kia Cerato (ر ف ق 7 4 2 9)',
      'distance_km': 16.7,
      'fare_amount': 182.00,
      'status': 'completed',
      'payment_method': 'Cash',
      'rating': 5.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _isLoading = true);
    final fetched = await SupabaseService().fetchUserTrips();
    setState(() {
      _trips = fetched.isNotEmpty ? fetched : _demoTrips;
      _isLoading = false;
    });
  }

  void _showReceiptDialog(Map<String, dynamic> trip) {
    final fare = (trip['fare_amount'] as num?)?.toDouble() ?? 199.0;
    final base = 15.00;
    final distanceCost = fare - base > 0 ? fare - base : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded, color: AppTheme.roseGold),
            SizedBox(width: 10),
            Text(
              'Official Rafik Receipt',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trip ID: ${trip['id'] ?? "RIDE-XXXX"}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const Divider(color: Colors.white12, height: 20),
            _receiptRow('Base Dispatch Pickup', '${base.toStringAsFixed(2)} LE'),
            _receiptRow('Road Distance (${trip['distance_km'] ?? 18.4} km @ 10 LE/km)', '${distanceCost.toStringAsFixed(2)} LE'),
            _receiptRow('Female Safety Guarantee Fee', '0.00 LE (FREE)'),
            const Divider(color: Colors.white12, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL SETTLED',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${fare.toStringAsFixed(2)} LE',
                  style: const TextStyle(
                    color: AppTheme.roseGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Method: ${trip['payment_method'] ?? "Cash"}',
              style: const TextStyle(color: AppTheme.sageSafe, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('CLOSE RECEIPT'),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
          'My Trips (سجل المشاوير)',
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
                text: 'VERIFIED RIDER',
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _trips.length,
              itemBuilder: (context, index) {
                final trip = _trips[index];
                final fare = (trip['fare_amount'] as num?)?.toDouble() ?? 199.0;

                return GestureDetector(
                  onTap: () => _showReceiptDialog(trip),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              trip['created_at']?.toString() ?? 'Recent Trip',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.roseGold.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.roseGold.withOpacity(0.3)),
                              ),
                              child: Text(
                                '${fare.toStringAsFixed(2)} LE',
                                style: const TextStyle(
                                  color: AppTheme.roseGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Route timeline
                        Row(
                          children: [
                            Column(
                              children: [
                                const Icon(Icons.circle, color: AppTheme.roseGold, size: 10),
                                Container(width: 2, height: 24, color: Colors.white24),
                                const Icon(Icons.square, color: AppTheme.sageSafe, size: 10),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trip['pickup_address']?.toString() ?? 'Pickup Location',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    trip['dropoff_address']?.toString() ?? 'Dropoff Destination',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const Divider(color: Colors.white10, height: 24),

                        // Captain & Vehicle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.verified_user_rounded, color: AppTheme.sageSafe, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  trip['driver_name']?.toString() ?? 'Captain Yasmine',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'VIEW RECEIPT >',
                              style: TextStyle(
                                color: AppTheme.roseGold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
