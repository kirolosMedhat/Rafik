import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../chat/in_ride_chat_sheet.dart';
import '../auth/auth_screen.dart';
import 'payment_selector_sheet.dart';
import 'rating_dialog.dart';
import 'safety_shield_sheet.dart';
import 'trip_history_screen.dart';

enum RideState { idle, searching, driverAssigned, inTrip }
enum RideTier { rafikStandard, rafikGirl }

/// Egyptian Places Model for Cairo & Giza Destinations
class CairoPlace {
  final String name;
  final String nameAr;
  final String area;
  final LatLng location;

  const CairoPlace({
    required this.name,
    required this.nameAr,
    required this.area,
    required this.location,
  });
}

/// Catalog of Cairo & Giza Destinations
const List<CairoPlace> cairoPlacesCatalog = [
  CairoPlace(
    name: 'Zamalek (26th July St)',
    nameAr: 'الزمالك - شارع 26 يوليو',
    area: 'Central Cairo',
    location: LatLng(30.0571, 31.2215),
  ),
  CairoPlace(
    name: 'Tahrir Square (Downtown)',
    nameAr: 'ميدان التحرير - وسط البلد',
    area: 'Central Cairo',
    location: LatLng(30.0444, 31.2357),
  ),
  CairoPlace(
    name: 'New Cairo (5th Settlement / AUC)',
    nameAr: 'التجمع الخامس - الجامعة الأمريكية',
    area: 'East Cairo',
    location: LatLng(30.0131, 31.4989),
  ),
  CairoPlace(
    name: 'Maadi (Degla Square)',
    nameAr: 'المعادي - ميدان دجلة',
    area: 'South Cairo',
    location: LatLng(29.9592, 31.2825),
  ),
  CairoPlace(
    name: 'Nasr City (City Stars Mall)',
    nameAr: 'مدينة نصر - سيتي ستارز',
    area: 'East Cairo',
    location: LatLng(30.0733, 31.3458),
  ),
  CairoPlace(
    name: 'Heliopolis (Korba Square)',
    nameAr: 'مصر الجديدة - الكربة',
    area: 'East Cairo',
    location: LatLng(30.0906, 31.3267),
  ),
  CairoPlace(
    name: 'Dokki (Mesaha Square)',
    nameAr: 'الدقي - ميدان المساحة',
    area: 'Giza',
    location: LatLng(30.0385, 31.2118),
  ),
  CairoPlace(
    name: 'Mohandessin (Gameat El Dowal)',
    nameAr: 'المهندسين - شارع جامعة الدول',
    area: 'Giza',
    location: LatLng(30.0526, 31.2001),
  ),
  CairoPlace(
    name: '6th of October (Mall of Arabia)',
    nameAr: 'السادس من أكتوبر - مول العرب',
    area: 'West Giza',
    location: LatLng(30.0074, 30.9734),
  ),
  CairoPlace(
    name: 'Sheikh Zayed (Arkan Plaza)',
    nameAr: 'الشيخ زايد - أركان بلازا',
    area: 'West Giza',
    location: LatLng(30.0210, 31.0022),
  ),
  CairoPlace(
    name: 'Cairo International Airport (T3)',
    nameAr: 'مطار القاهرة الدولي - مبنى 3',
    area: 'Heliopolis',
    location: LatLng(30.1219, 31.4056),
  ),
  CairoPlace(
    name: 'Pyramids of Giza (Plateau)',
    nameAr: 'أهرامات الجيزة - نزلة السمان',
    area: 'Giza',
    location: LatLng(29.9792, 31.1342),
  ),
];

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final MapController _mapController = MapController();

  // Active Places & Locations
  CairoPlace _pickupPlace = cairoPlacesCatalog[0]; // Zamalek
  CairoPlace _dropoffPlace = cairoPlacesCatalog[2]; // New Cairo 5th Settlement

  // Fare Formula Parameters
  static const double ratePerKm = 10.0; // User required: 10 LE per km
  static const double baseFare = 15.0; // Base pickup fee: 15 LE
  static const double minFare = 25.0; // Minimum trip fare: 25 LE

  double _distanceKm = 0.0;
  double _calculatedFare = 0.0;

  RideState _rideState = RideState.idle;
  RideTier _selectedTier = RideTier.rafikStandard;
  String _riderGender = 'female';
  bool _uperGirlEligible = true;
  String _securityPin = '----'; // Fetched securely from isolated ride_pins table
  String? _assignedDriverId;

  // Payment Method Selection
  PaymentMethodOption _selectedPayment = const PaymentMethodOption(
    method: PaymentMethod.cash,
    title: 'Cash Payment',
    titleAr: 'الدفع نقداً للسائقة',
    subtitle: 'Pay directly upon arrival',
    icon: Icons.payments_outlined,
    badgeText: 'DIRECT CASH',
  );

  // Live Driver Location Tracking & Movement
  LatLng? _driverLiveLocation;
  double _driverHeading = 45.0;
  int _driverEtaMinutes = 3;
  double _driverDistanceRemainingKm = 1.2;
  Timer? _driverMovementTimer;

  // Realtime Supabase Dispatch Channel
  RealtimeChannel? _dispatchChannel;
  String _activeRideId = '';

  // Assigned driver data
  String _driverName = 'Yasmine El-Sayed';
  String _vehicleInfo = 'Toyota Yaris (س ن ق 1 4 2 9)';
  double _driverRating = 4.96;

  @override
  void initState() {
    super.initState();
    _loadRiderSession();
    _recalculateFare();
    _initRealtimeChannel();
  }

  Future<void> _loadRiderSession() async {
    final gender = await PersistentStorage.getUserGender();
    final uperGirlActive = await PersistentStorage.isUperGirlEnabled();
    if (mounted) {
      setState(() {
        _riderGender = gender;
        _uperGirlEligible = (gender == 'female');
        _selectedTier = (_uperGirlEligible && uperGirlActive)
            ? RideTier.rafikGirl
            : RideTier.rafikStandard;
      });
    }
  }

  @override
  void dispose() {
    _driverMovementTimer?.cancel();
    _dispatchChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtimeChannel() {
    // Realtime postgres_changes active per ride
  }

  StreamSubscription? _firebaseRideSub;
  StreamSubscription? _firebaseLocationSub;

  void _subscribeToRide(String rideId) {
    _firebaseRideSub?.cancel();
    _firebaseRideSub = FirebaseService().streamRide(rideId).listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
      final status = data?['status']?.toString();
      if (status == null) return;

      if (status == 'accepted' && _rideState != RideState.driverAssigned && _rideState != RideState.inTrip) {
        HapticFeedback.heavyImpact();
        final driverId = data?['driver_id']?.toString();
        _assignedDriverId = driverId;
        setState(() {
          _driverName = data?['driver_name']?.toString() ?? 'Rafik Captain';
          _vehicleInfo = '$(data?['vehicle_model'] ?? 'Sedan') ($(data?['vehicle_plate'] ?? ''))';
          _securityPin = data?['pin']?.toString() ?? _securityPin;
          _rideState = RideState.driverAssigned;
        });
        if (driverId != null) {
          _subscribeToDriverLocation(driverId);
        }
      } else if (status == 'arrived' && _rideState != RideState.driverArrived) {
        HapticFeedback.mediumImpact();
        setState(() => _rideState = RideState.driverArrived);
      } else if (status == 'in_progress' && _rideState != RideState.inTrip) {
        HapticFeedback.heavyImpact();
        setState(() => _rideState = RideState.inTrip);
      } else if (status == 'completed' && _rideState != RideState.tripCompleted) {
        HapticFeedback.heavyImpact();
        setState(() => _rideState = RideState.tripCompleted);
      } else if (status == 'cancelled' && _rideState != RideState.idle) {
        setState(() => _rideState = RideState.idle);
      }
    });

    _dispatchChannel?.unsubscribe();
    final supabase = Supabase.instance.client;

    _dispatchChannel = supabase.channel('rider-ride-$rideId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rides',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: rideId,
        ),
        callback: (payload) async {
          final record = payload.newRecord;
          final status = record['status']?.toString();
          if (status == null) return;

          if (status == 'accepted' && _rideState != RideState.driverAssigned && _rideState != RideState.inTrip) {
            HapticFeedback.heavyImpact();
            final driverId = record['driver_id']?.toString();
            _assignedDriverId = driverId;

            if (driverId != null) {
              try {
                final driverData = await supabase
                    .from('drivers')
                    .select('vehicle_make, vehicle_model, vehicle_plate, vehicle_color, profiles:user_id(full_name, rating_avg)')
                    .eq('user_id', driverId)
                    .maybeSingle();

                if (driverData != null && mounted) {
                  final prof = driverData['profiles'] as Map<String, dynamic>?;
                  setState(() {
                    _driverName = prof?['full_name']?.toString() ?? 'Rafik Captain';
                    _driverRating = (prof?['rating_avg'] as num?)?.toDouble() ?? 5.0;
                    _vehicleInfo = '${driverData['vehicle_make']} ${driverData['vehicle_model']} (${driverData['vehicle_plate']})';
                  });
                }
              } catch (_) {}

              _subscribeToDriverLocation(driverId);
            }

            final pin = await SupabaseService().fetchRidePin(rideId);
            if (pin != null && mounted) {
              setState(() => _securityPin = pin);
            }

            if (mounted) {
              setState(() => _rideState = RideState.driverAssigned);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Captain $_driverName accepted your ride!'),
                  backgroundColor: AppTheme.sageSafe,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else if (status == 'arrived' && _rideState == RideState.driverAssigned) {
            HapticFeedback.mediumImpact();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Captain has arrived at your pickup location!'),
                  backgroundColor: AppTheme.sageSafe,
                ),
              );
            }
          } else if (status == 'in_progress' && _rideState != RideState.inTrip) {
            HapticFeedback.mediumImpact();
            if (mounted) {
              setState(() => _rideState = RideState.inTrip);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Trip started safely with PIN handshake.'),
                  backgroundColor: AppTheme.sageSafe,
                ),
              );
            }
          } else if (status == 'completed') {
            HapticFeedback.heavyImpact();
            if (mounted) {
              _showTripCompletedDialog();
            }
          } else if (status == 'expired' || status == 'cancelled') {
            if (mounted) {
              setState(() {
                _rideState = RideState.idle;
                _activeRideId = '';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(status == 'expired'
                      ? 'No captains nearby at this moment. Please try again.'
                      : 'The ride was cancelled.'),
                  backgroundColor: AppTheme.berryCore,
                ),
              );
            }
          }
        },
      )
      ..subscribe();
  }

  void _subscribeToDriverLocation(String driverId) {
    _firebaseLocationSub?.cancel();
    _firebaseLocationSub = FirebaseService().streamDriverLocation(driverId).listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
      final lat = (data?['lat'] as num?)?.toDouble();
      final lng = (data?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() {
          _driverCurrentLocation = LatLng(lat, lng);
        });
      }
    });

    final supabase = Supabase.instance.client;
    supabase.channel('rider-driver-loc-$driverId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'driver_locations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'driver_id',
          value: driverId,
        ),
        callback: (payload) {
          final rec = payload.newRecord;
          final heading = (rec['heading'] as num?)?.toDouble() ?? 0.0;
          if (mounted) {
            setState(() {
              _driverHeading = heading;
            });
          }
        },
      )
      ..subscribe();
  }

  /// Calculates real-world road distance and computes fare preview
  void _recalculateFare() {
    final distanceCalc = const Distance();
    final double meters = distanceCalc.as(
      LengthUnit.Meter,
      _pickupPlace.location,
      _dropoffPlace.location,
    );

    // Apply Cairo urban road routing factor (~1.25x curvature)
    final double roadKm = (meters / 1000.0) * 1.25;
    final double distanceCharge = roadKm * ratePerKm;
    final double total = baseFare + distanceCharge;

    setState(() {
      _distanceKm = double.parse(roadKm.toStringAsFixed(1));
      _calculatedFare = total < minFare ? minFare : double.parse(total.toStringAsFixed(2));
    });
  }

  Future<void> _requestRide() async {
    setState(() {
      _rideState = RideState.searching;
    });

    HapticFeedback.mediumImpact();

    try {
      final rideId = await SupabaseService().requestRide(
        tier: _selectedTier == RideTier.rafikGirl ? 'rafik_girl' : 'standard',
        pickupAddress: _pickupPlace.name,
        pickupLat: _pickupPlace.location.latitude,
        pickupLng: _pickupPlace.location.longitude,
        dropoffAddress: _dropoffPlace.name,
        dropoffLat: _dropoffPlace.location.latitude,
        dropoffLng: _dropoffPlace.location.longitude,
        paymentMethod: _selectedPayment.title,
      );

      if (!mounted) return;
      setState(() => _activeRideId = rideId);
      _subscribeToRide(rideId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rideState = RideState.idle);

      final err = e.toString();
      String userMessage = 'Unable to request ride: $e';
      if (err.contains('rafik_girl_unauthorized')) {
        userMessage = 'Rafik Girl requires identity verification. Please verify your ID first.';
      } else if (err.contains('active_ride_exists')) {
        userMessage = 'You already have an active ride request in progress.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage),
          backgroundColor: AppTheme.berryCore,
        ),
      );
    }
  }

  void _triggerSos() async {
    if (_activeRideId.isNotEmpty) {
      try {
        await SupabaseService().triggerSos(
          rideId: _activeRideId,
          lat: _pickupPlace.location.latitude,
          lng: _pickupPlace.location.longitude,
        );
      } catch (e) {
        debugPrint('SOS trigger notice: $e');
      }
    }

    // Launch Egyptian Police 122 Emergency Phone Dialer
    final uri = Uri.parse('tel:122');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Opens the Places Catalog Bottom Sheet Modal for selecting Pickup / Dropoff
  void _openPlacePicker({required bool isPickup}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredPlaces = cairoPlacesCatalog.where((place) {
              final query = searchQuery.toLowerCase().trim();
              if (query.isEmpty) return true;
              return place.name.toLowerCase().contains(query) ||
                  place.nameAr.contains(query) ||
                  place.area.toLowerCase().contains(query);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PillBadge(
                        label: isPickup ? 'SELECT PICKUP LOCATION' : 'SELECT DESTINATION PLACE',
                        variant: isPickup ? PillBadgeVariant.roseGold : PillBadgeVariant.sage,
                      ),
                      const Text(
                        '10 LE / KM RATE',
                        style: TextStyle(
                          color: AppTheme.roseGoldLight,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Places in Cairo & Giza',
                    style: TextStyle(
                      color: Color(0xFFFCE4E6),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search Box
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search place, district, or mall (e.g. New Cairo, الزمالك)',
                      prefixIcon: const Icon(Icons.search, color: AppTheme.roseGold, size: 20),
                      filled: true,
                      fillColor: AppTheme.darkBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.roseGold.withValues(alpha: 0.3)),
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Places List
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredPlaces.length,
                      separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.06)),
                      itemBuilder: (context, index) {
                        final place = filteredPlaces[index];
                        final isSelected = isPickup
                            ? place.name == _pickupPlace.name
                            : place.name == _dropoffPlace.name;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isPickup ? AppTheme.roseGold : AppTheme.sageSafe)
                                  : Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPickup ? Icons.my_location : Icons.location_on,
                              color: isSelected ? Colors.white : AppTheme.roseGoldLight,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            place.name,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFFFCE4E6) : Colors.white,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                place.nameAr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  place.area,
                                  style: TextStyle(
                                    color: AppTheme.roseGoldLight.withValues(alpha: 0.8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: AppTheme.sageSafe, size: 20)
                              : const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                          onTap: () {
                            setState(() {
                              if (isPickup) {
                                _pickupPlace = place;
                              } else {
                                _dropoffPlace = place;
                              }
                              _recalculateFare();
                            });
                            Navigator.pop(context);

                            // Smoothly move map to the newly selected destination
                            _mapController.move(place.location, 13.0);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Shows the Fare Calculation Breakdown Modal
  void _showFareBreakdownModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.roseGold.withValues(alpha: 0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: AppTheme.roseGold, size: 24),
            SizedBox(width: 10),
            Text(
              'FARE CALCULATION',
              style: TextStyle(
                color: Color(0xFFFCE4E6),
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PillBadge(
              label: 'OFFICIAL RATE: 10.00 EGP / KM',
              variant: PillBadgeVariant.roseGold,
            ),
            const SizedBox(height: 16),
            _buildFareRow('Base Pickup Fee', '${baseFare.toStringAsFixed(2)} EGP'),
            const SizedBox(height: 8),
            _buildFareRow(
              'Trip Distance',
              '$_distanceKm km',
              subtitle: 'From ${_pickupPlace.name.split('(')[0]} to ${_dropoffPlace.name.split('(')[0]}',
            ),
            const SizedBox(height: 8),
            _buildFareRow(
              'Distance Rate Charge',
              '${(_distanceKm * ratePerKm).toStringAsFixed(2)} EGP',
              subtitle: '$_distanceKm km × 10.00 LE/km',
            ),
            const Divider(color: Colors.white24, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL UPFRONT FARE',
                  style: TextStyle(
                    color: Color(0xFFFCE4E6),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${_calculatedFare.toStringAsFixed(2)} EGP',
                  style: const TextStyle(
                    color: AppTheme.roseGoldLight,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: AppTheme.roseGoldLight)),
          ),
        ],
      ),
    );
  }

  Widget _buildFareRow(String title, String value, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // 1. OpenStreetMap Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickupPlace.location,
              initialZoom: 13.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rafik.rider',
              ),

              // Route Polyline between Pickup and Dropoff
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [_pickupPlace.location, _dropoffPlace.location],
                    color: AppTheme.roseGold,
                    strokeWidth: 3.5,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.black45,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  // Rider Pickup Marker
                  Marker(
                    point: _pickupPlace.location,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.roseGold,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.person, color: Colors.white, size: 20),
                      ),
                    ),
                  ),

                  // Destination Dropoff Marker
                  Marker(
                    point: _dropoffPlace.location,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.sageSafe,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.location_on, color: Colors.white, size: 22),
                      ),
                    ),
                  ),

                  // Nearby Female Drivers (Simulated)
                  Marker(
                    point: LatLng(_pickupPlace.location.latitude + 0.008, _pickupPlace.location.longitude + 0.006),
                    width: 36,
                    height: 36,
                    child: _buildDriverMapMarker(),
                  ),
                  Marker(
                    point: LatLng(_pickupPlace.location.latitude - 0.007, _pickupPlace.location.longitude - 0.005),
                    width: 36,
                    height: 36,
                    child: _buildDriverMapMarker(),
                  ),

                  // Assigned Moving Female Driver Marker
                  if (_driverLiveLocation != null &&
                      (_rideState == RideState.driverAssigned || _rideState == RideState.inTrip))
                    Marker(
                      point: _driverLiveLocation!,
                      width: 50,
                      height: 50,
                      child: _buildAssignedMovingDriverMarker(),
                    ),
                ],
              ),
            ],
          ),

          // 2. Top Branded Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.roseGold.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.roseGold.withValues(alpha: 0.4)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'RAFIK',
                          style: TextStyle(
                            color: Color(0xFFFCE4E6),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const PillBadge(
                          label: 'VERIFIED',
                          variant: PillBadgeVariant.sage,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // My Trips Button
                  IconButton(
                    onPressed: _openTripHistory,
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.history_rounded, color: AppTheme.roseGold, size: 18),
                    ),
                    tooltip: 'My Trips',
                  ),

                  // Log Out Button
                  IconButton(
                    onPressed: () async {
                      await PersistentStorage.clearSession();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                    ),
                    tooltip: 'Log Out',
                  ),

                  // Safety Shield Button
                  IconButton(
                    onPressed: _openSafetyShield,
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.sageSafe.withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppTheme.sageSafe, size: 18),
                    ),
                    tooltip: 'Safety Shield & Contacts',
                  ),

                  // SOS Button
                  GestureDetector(
                    onTap: _triggerSos,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.alertSos,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.alertSos.withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'SOS 122',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Booking Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedMovingDriverMarker() {
    return Transform.rotate(
      angle: _driverHeading * (3.141592653589793 / 180.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.roseGold,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.roseGold.withOpacity(0.65),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.navigation_rounded, color: Colors.black, size: 24),
        ),
      ),
    );
  }

  void _openPaymentSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PaymentSelectorSheet(
        initialMethod: _selectedPayment.method,
        fareAmount: _calculatedFare,
        onSelect: (option) {
          setState(() {
            _selectedPayment = option;
          });
        },
      ),
    );
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InRideChatSheet(
        rideId: _activeRideId.isNotEmpty ? _activeRideId : 'demo-ride',
        myRole: 'rider',
        otherPartyName: _driverName,
        otherPartySubtitle: _vehicleInfo,
      ),
    );
  }

  void _openSafetyShield() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafetyShieldSheet(
        activeRideId: _activeRideId,
        driverName: _driverName,
        vehicleInfo: _vehicleInfo,
        pickupName: _pickupPlace.name,
        dropoffName: _dropoffPlace.name,
        safetyPin: _securityPin,
      ),
    );
  }

  void _openTripHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
    );
  }

  void _showRatingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(
        rideId: _activeRideId.isNotEmpty ? _activeRideId : 'demo-ride',
        driverName: _driverName,
        vehicleInfo: _vehicleInfo,
        fareAmount: _calculatedFare,
        onDismissed: () {
          setState(() {
            _rideState = RideState.idle;
            _activeRideId = '';
          });
        },
      ),
    );
  }

  Widget _buildDriverMapMarker() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.sageSafe, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.directions_car, color: AppTheme.sageSafe, size: 18),
      ),
    );
  }

  Widget _buildBottomPanel() {
    switch (_rideState) {
      case RideState.idle:
        return _buildIdlePanel();
      case RideState.searching:
        return _buildSearchingPanel();
      case RideState.driverAssigned:
      case RideState.inTrip:
        return _buildDriverAssignedPanel();
    }
  }

  Widget _buildIdlePanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.darkBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PillBadge(
                  label: _selectedTier == RideTier.rafikGirl
                      ? 'RAFIK GIRL • 100% FEMALE CAPTAINS'
                      : 'RAFIK STANDARD • GENERAL FLEET',
                  variant: _selectedTier == RideTier.rafikGirl
                      ? PillBadgeVariant.roseGold
                      : PillBadgeVariant.sage,
                ),
                GestureDetector(
                  onTap: _showFareBreakdownModal,
                  child: Row(
                    children: [
                      Text(
                        '${_calculatedFare.toStringAsFixed(2)} EGP',
                        style: const TextStyle(
                          color: Color(0xFFFCE4E6),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline, color: AppTheme.roseGoldLight, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '$_distanceKm km route',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•  10.00 LE / km calculation',
                  style: TextStyle(
                    color: AppTheme.sageSafe.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // DUAL-TIER FLEET SELECTOR (RAFIK STANDARD VS RAFIK GIRL)
            Row(
              children: [
                // Option 1: RAFIK STANDARD
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTier = RideTier.rafikStandard);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _selectedTier == RideTier.rafikStandard
                            ? AppTheme.sageSafe.withValues(alpha: 0.18)
                            : AppTheme.darkBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedTier == RideTier.rafikStandard
                              ? AppTheme.sageSafe
                              : Colors.white.withValues(alpha: 0.1),
                          width: _selectedTier == RideTier.rafikStandard ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 15,
                                color: _selectedTier == RideTier.rafikStandard
                                    ? AppTheme.sageSafe
                                    : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'RAFIK STANDARD',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: _selectedTier == RideTier.rafikStandard
                                      ? Colors.white
                                      : Colors.white60,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'General Fleet',
                            style: TextStyle(
                              fontSize: 9,
                              color: _selectedTier == RideTier.rafikStandard
                                  ? AppTheme.sageSafe
                                  : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Option 2: RAFIK GIRL
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!_uperGirlEligible) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('RAFIK GIRL option is reserved for female passengers.'),
                            backgroundColor: AppTheme.berryCore,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTier = RideTier.rafikGirl);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _selectedTier == RideTier.rafikGirl
                            ? AppTheme.roseGold.withValues(alpha: 0.18)
                            : AppTheme.darkBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedTier == RideTier.rafikGirl
                              ? AppTheme.roseGold
                              : Colors.white.withValues(alpha: 0.1),
                          width: _selectedTier == RideTier.rafikGirl ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield,
                                size: 14,
                                color: _selectedTier == RideTier.rafikGirl
                                    ? AppTheme.roseGoldLight
                                    : Colors.white60,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'RAFIK GIRL',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: _selectedTier == RideTier.rafikGirl
                                      ? Colors.white
                                      : Colors.white60,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _uperGirlEligible ? 'بنات فقط (100% Female)' : 'بنات فقط (Female Only)',
                            style: TextStyle(
                              fontSize: 9,
                              color: _selectedTier == RideTier.rafikGirl
                                  ? AppTheme.roseGoldLight
                                  : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Pickup & Destination Interactive Pickers
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  // Pickup Tile (Tap to choose)
                  InkWell(
                    onTap: () => _openPlacePicker(isPickup: true),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location, color: AppTheme.roseGold, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PICKUP LOCATION (TAP TO CHANGE)', style: TextStyle(color: Colors.white38, fontSize: 9.5, letterSpacing: 1)),
                              const SizedBox(height: 2),
                              Text(
                                _pickupPlace.name,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_right, color: Colors.white38, size: 18),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 16),

                  // Dropoff Tile (Tap to choose)
                  InkWell(
                    onTap: () => _openPlacePicker(isPickup: false),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.sageSafe, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('DESTINATION (TAP TO CHANGE)', style: TextStyle(color: Colors.white38, fontSize: 9.5, letterSpacing: 1)),
                              const SizedBox(height: 2),
                              Text(
                                _dropoffPlace.name,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_right, color: Colors.white38, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Payment Method Selector
            GestureDetector(
              onTap: _openPaymentSelector,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.roseGold.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Icon(_selectedPayment.icon, color: AppTheme.roseGold, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedPayment.title,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _selectedPayment.subtitle,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    PillBadge(
                      text: _selectedPayment.badgeText,
                      textColor: AppTheme.roseGold,
                      bgColor: const Color(0x1FB76E79),
                      borderColor: const Color(0x3DB76E79),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.roseGold, size: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTier == RideTier.rafikGirl
                      ? AppTheme.roseGold
                      : AppTheme.sageSafe,
                  foregroundColor: _selectedTier == RideTier.rafikGirl
                      ? Colors.white
                      : Colors.black,
                ),
                onPressed: _requestRide,
                child: Text(
                  _selectedTier == RideTier.rafikGirl
                      ? 'REQUEST RAFIK GIRL (${_calculatedFare.toStringAsFixed(0)} EGP) ➔'
                      : 'REQUEST RAFIK STANDARD (${_calculatedFare.toStringAsFixed(0)} EGP) ➔',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'All rights reserved to Rafik 2026 • جميع الحقوق محفوظة لـ رفيق 2026',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 8.5,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: _selectedTier == RideTier.rafikGirl ? AppTheme.roseGold : AppTheme.sageSafe,
            ),
            const SizedBox(height: 20),
            PillBadge(
              label: _selectedTier == RideTier.rafikGirl ? 'RAFIK GIRL DISPATCH' : 'RAFIK STANDARD DISPATCH',
              variant: _selectedTier == RideTier.rafikGirl ? PillBadgeVariant.roseGold : PillBadgeVariant.sage,
            ),
            const SizedBox(height: 12),
            Text(
              _selectedTier == RideTier.rafikGirl
                  ? 'Finding Nearest Verified Female Captain...'
                  : 'Finding Nearest Verified Rafik Captain...',
              style: const TextStyle(
                color: Color(0xFFFCE4E6),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Routing from ${_pickupPlace.name.split('(')[0]} to ${_dropoffPlace.name.split('(')[0]} ($_distanceKm km • ${_calculatedFare.toStringAsFixed(0)} EGP)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAssignedPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.sageSafe.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Security PIN Handshake Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.berryCore.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.roseGoldLight.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SAFETY HANDSHAKE PIN',
                        style: TextStyle(
                          color: AppTheme.roseGoldLight,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Give to driver before trip begins',
                        style: TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                    ],
                  ),
                  Text(
                    _securityPin,
                    style: const TextStyle(
                      color: Color(0xFFFCE4E6),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Driver Card
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.sageSafe.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: AppTheme.sageSafe, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _driverName,
                            style: const TextStyle(
                              color: Color(0xFFFCE4E6),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, color: AppTheme.sageSafe, size: 16),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _vehicleInfo,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$_driverRating',
                      style: const TextStyle(
                        color: AppTheme.roseGoldLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$_driverEtaMinutes MINS AWAY',
                      style: const TextStyle(
                        color: AppTheme.sageSafe,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cancel / Contact Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelRide,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('CANCEL RIDE', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.roseGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('CHAT CAPTAIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _cancelRide() {
    _dispatchChannel?.sendBroadcastMessage(
      event: 'ride_cancelled',
      payload: {'ride_id': _activeRideId},
    );
    setState(() {
      _rideState = RideState.idle;
      _activeRideId = '';
    });
  }

  void _showTripCompletedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.sageSafe.withValues(alpha: 0.5)),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.sageSafe, size: 28),
            SizedBox(width: 10),
            Text(
              'TRIP COMPLETED',
              style: TextStyle(
                color: Color(0xFFFCE4E6),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PillBadge(
              label: 'ARRIVED SAFELY WITH RAFIK',
              variant: PillBadgeVariant.sage,
            ),
            const SizedBox(height: 14),
            Text(
              'You have safely arrived at ${_dropoffPlace.name.split('(')[0]}.\n\nTotal Paid: ${_calculatedFare.toStringAsFixed(2)} EGP\nSettlement: ${_selectedPayment.title}\nCaptain: $_driverName',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showRatingDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('RATE CAPTAIN & VIEW BADGES', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
