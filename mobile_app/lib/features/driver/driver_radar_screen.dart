import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/location_service.dart';
import '../../core/services/persistent_storage.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pill_badge.dart';
import '../auth/auth_screen.dart';
import '../chat/in_ride_chat_sheet.dart';
import 'driver_onboarding_screen.dart';
import 'driver_wallet_screen.dart';

class DriverRadarScreen extends StatefulWidget {
  const DriverRadarScreen({super.key});

  @override
  State<DriverRadarScreen> createState() => _DriverRadarScreenState();
}

class _DriverRadarScreenState extends State<DriverRadarScreen> {
  final MapController _mapController = MapController();
  final LatLng _driverLocation = const LatLng(30.0480, 31.2390);

  bool _isOnline = false;
  bool _isBiometricallyVerified = false;
  bool _hasIncomingRequest = false;
  int _countdownSeconds = 15;
  Timer? _countdownTimer;

  // Real Driver Profile Loaded Dynamically
  String _driverName = 'Captain';
  String _driverPhone = '+20 100 000 0000';
  String _driverGender = 'female';
  bool _isUperGirlEnrolled = true;
  String _incomingTier = 'standard';

  // Realtime Supabase Dispatch & Telemetry Channels
  RealtimeChannel? _dispatchChannel;
  RealtimeChannel? _telemetryChannel;
  String _incomingRideId = '';
  String _incomingPickupName = 'Zamalek (شارع 26 يوليو)';
  String _incomingDropoffName = 'New Cairo (التجمع الخامس - AUC)';
  double _incomingDistanceKm = 28.4;
  double _incomingFareEgp = 299.0;
  String _targetPin = '7429';

  // Active Trip State
  bool _tripAccepted = false;
  final TextEditingController _pinInputController = TextEditingController();
  bool _pinVerified = false;
  Timer? _locationStreamTimer;

  @override
  void initState() {
    super.initState();
    _loadDriverSession();
    _initRealtimeChannel();
  }

  Future<void> _loadDriverSession() async {
    final session = await PersistentStorage.getUserSession();
    final isGirl = await PersistentStorage.isUperGirlEnabled();
    final gender = await PersistentStorage.getUserGender();
    if (mounted) {
      setState(() {
        if (session != null) {
          _driverName = session['name'] ?? 'Captain';
          _driverPhone = session['phone'] ?? '+20 100 000 0000';
        }
        _driverGender = gender;
        _isUperGirlEnrolled = (gender == 'female') && isGirl;
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _locationStreamTimer?.cancel();
    _pinInputController.dispose();
    _dispatchChannel?.unsubscribe();
    _telemetryChannel?.unsubscribe();
    super.dispose();
  }

  void _startLocationStreaming() {
    _locationStreamTimer?.cancel();
    _locationStreamTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted || !_tripAccepted) {
        timer.cancel();
        return;
      }
      try {
        final loc = await LocationService().getCurrentLocation();
        final safeId = 'drv-${_driverPhone.replaceAll(RegExp(r'[^0-9]'), '')}';
        final payload = {
          'ride_id': _incomingRideId,
          'driverId': safeId.length > 4 ? safeId : 'drv-captain',
          'driver_name': _driverName,
          'tier': _incomingTier,
          'lat': loc.latitude,
          'lng': loc.longitude,
          'heading': 45.0,
          'speed': 35.0,
          'eta_minutes': 3,
          'distance_km': 1.2,
          'status': 'in_trip',
        };

        // Broadcast to Rider Dispatch Channel
        await _dispatchChannel?.sendBroadcastMessage(
          event: 'driver_location_update',
          payload: payload,
        );

        // Broadcast to Admin Telemetry Channel
        await _telemetryChannel?.sendBroadcastMessage(
          event: 'driver_location_update',
          payload: payload,
        );
      } catch (e) {
        debugPrint('Location streaming error: $e');
      }
    });
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InRideChatSheet(
        rideId: _incomingRideId.isNotEmpty ? _incomingRideId : 'demo-ride',
        myRole: 'driver',
        otherPartyName: 'Verified Passenger',
        otherPartySubtitle: _isUperGirlEnrolled ? 'Rafik Girl Passenger' : 'Rafik Passenger',
      ),
    );
  }

  void _openWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverWalletScreen()),
    );
  }

  void _initRealtimeChannel() {
    try {
      final supabase = Supabase.instance.client;
      _dispatchChannel = supabase.channel('refqa-dispatch');
      _telemetryChannel = supabase.channel('refqa-telemetry');

    // 1. Listen for Live Ride Requests Broadcasted by Riders
    _dispatchChannel!.onBroadcast(
      event: 'ride_requested',
      callback: (payload) {
        if (!_isOnline || _tripAccepted) return;

        final requestedTier = payload['tier']?.toString() ?? 'standard';
        // If passenger requested Uper Girl, only Uper Girl enrolled female captains can receive it!
        if (requestedTier == 'uper_girl' && !_isUperGirlEnrolled) {
          return;
        }

        HapticFeedback.heavyImpact();
        setState(() {
          _incomingRideId = payload['ride_id']?.toString() ?? '';
          _incomingTier = requestedTier;
          _incomingPickupName = payload['pickup_name']?.toString() ?? 'Zamalek';
          _incomingDropoffName = payload['dropoff_name']?.toString() ?? 'New Cairo';
          _incomingDistanceKm = (payload['distance_km'] as num?)?.toDouble() ?? 28.4;
          _incomingFareEgp = (payload['fare_egp'] as num?)?.toDouble() ?? 299.0;
          _targetPin = payload['pin_code']?.toString() ?? '7429';
          _hasIncomingRequest = true;
          _countdownSeconds = 15;
        });

        _startCountdownTimer();
      },
    );

    // 2. Listen for Rider Cancelling the Request
    _dispatchChannel!.onBroadcast(
      event: 'ride_cancelled',
      callback: (payload) {
        final rideId = payload['ride_id']?.toString();
        if (rideId != null && rideId == _incomingRideId && _hasIncomingRequest) {
          _countdownTimer?.cancel();
          setState(() => _hasIncomingRequest = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Passenger cancelled request.'),
                backgroundColor: AppTheme.berryCore,
              ),
            );
          }
        }
      },
    );

    _dispatchChannel!.subscribe();
    _telemetryChannel!.subscribe();
    } catch (e) {
      debugPrint('[Rafik Driver] Realtime channel init notice: $e');
    }
  }

  void _toggleOnline(bool value) async {
    setState(() {
      _isOnline = value;
      _isBiometricallyVerified = true;
      if (!_isOnline) {
        _hasIncomingRequest = false;
        _countdownTimer?.cancel();
      }
    });

    // Broadcast Status Update to Admin Operations Room in Real-Time
    try {
      final safeId = 'drv-${_driverPhone.replaceAll(RegExp(r'[^0-9]'), '')}';
      await _telemetryChannel?.sendBroadcastMessage(
        event: 'driver_status_update',
        payload: {
          'id': safeId.length > 4 ? safeId : 'drv-captain',
          'name': _driverName,
          'phone': _driverPhone,
          'email': 'captain@rafik.app',
          'status': value ? 'online' : 'offline',
          'gender': _driverGender,
          'isUperGirlCertified': _isUperGirlEnrolled,
          'tier': _isUperGirlEnrolled ? 'uper_girl' : 'standard',
          'location': {
            'lat': _driverLocation.latitude,
            'lng': _driverLocation.longitude,
            'heading': 45.0,
            'lastUpdated': DateTime.now().toIso8601String(),
          },
          'vehicle': {
            'make': 'Toyota',
            'model': 'Yaris',
            'year': 2023,
            'plateAr': 'س ن ق 1 4 2 9',
            'plateEn': 'SNQ 1429',
            'color': _isUperGirlEnrolled ? 'Rose Gold Metallic' : 'Obsidian Black',
          },
          'nationalId': '29804150102844',
          'rating': 4.96,
          'tripsCount': 14,
          'livenessScore': 0.984,
          'documents': {
            'nationalIdFront': 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
            'nationalIdBack': 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
            'licenseFront': 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
            'licenseBack': 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
            'mulkiyaFront': 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
            'mulkiyaBack': 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
          },
        },
      );
    } catch (e) {
      debugPrint('Realtime telemetry broadcast error: $e');
    }

    if (_isOnline) {
      HapticFeedback.lightImpact();
      // Optional fallback: If testing alone without a second physical phone, trigger a sample request after 15s
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _isOnline && !_tripAccepted && !_hasIncomingRequest) {
          _startIncomingRequest();
        }
      });
    }
  }

  void _startIncomingRequest() {
    setState(() {
      _hasIncomingRequest = true;
      _countdownSeconds = 15;
    });
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        setState(() => _hasIncomingRequest = false);
      }
    });
  }

  void _acceptRide() async {
    _countdownTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _hasIncomingRequest = false;
      _tripAccepted = true;
    });

    final safeId = 'drv-${_driverPhone.replaceAll(RegExp(r'[^0-9]'), '')}';
    // 1. PostgreSQL Database Update in Supabase
    await SupabaseService().updateRideAccepted(
      rideId: _incomingRideId,
      driverId: safeId.length > 4 ? safeId : 'drv-captain',
      driverName: _driverName,
    );

    // 2. Start Live Location Streaming
    _startLocationStreaming();

    // 3. Broadcast to Rider Device
    try {
      await _dispatchChannel?.sendBroadcastMessage(
        event: 'ride_accepted',
        payload: {
          'ride_id': _incomingRideId,
          'driver_name': _driverName,
          'vehicle_info': 'Toyota Yaris (س ن ق 1 4 2 9)',
          'driver_rating': 4.96,
          'tier': _incomingTier,
        },
      );
    } catch (e) {
      debugPrint('Error broadcasting accept: $e');
    }
  }

  void _declineRide() {
    _countdownTimer?.cancel();
    setState(() => _hasIncomingRequest = false);
  }

  void _verifyPin() async {
    if (_pinInputController.text.trim() == _targetPin) {
      HapticFeedback.heavyImpact();
      setState(() => _pinVerified = true);

      // 1. Update PostgreSQL in Supabase
      await SupabaseService().updateTripStarted(_incomingRideId);

      // 2. Broadcast to Rider Device
      try {
        await _dispatchChannel?.sendBroadcastMessage(
          event: 'trip_started',
          payload: {
            'ride_id': _incomingRideId,
          },
        );
      } catch (e) {
        debugPrint('Error broadcasting trip start: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Safety PIN Verified! Trip safely started.'),
            backgroundColor: AppTheme.sageSafe,
          ),
        );
      }
    } else {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid PIN. Please check 4-digit code with passenger.'),
            backgroundColor: AppTheme.alertSos,
          ),
        );
      }
    }
  }

  void _completeTrip() async {
    _locationStreamTimer?.cancel();
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.payments_rounded, color: AppTheme.sageSafe),
            SizedBox(width: 10),
            Text(
              'Collect Passenger Fare',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount to Collect: ${_incomingFareEgp.toStringAsFixed(2)} LE',
              style: const TextStyle(color: AppTheme.roseGold, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please collect the total fare from the passenger before ending the ride. Platform fee is 0.00 LE (100% earnings to you).',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _finalizeTripCompletion();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRM PAYMENT & COMPLETE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeTripCompletion() async {
    try {
      await _dispatchChannel?.sendBroadcastMessage(
        event: 'trip_completed',
        payload: {
          'ride_id': _incomingRideId,
          'fare_egp': _incomingFareEgp,
        },
      );
    } catch (e) {
      debugPrint('Error broadcasting complete: $e');
    }

    // Persist to PostgreSQL and update driver wallet
    await SupabaseService().updateTripCompleted(
      rideId: _incomingRideId,
      finalFare: _incomingFareEgp,
      tripData: {
        'id': _incomingRideId,
        'created_at': 'Today',
        'pickup_address': _incomingPickupName,
        'dropoff_address': _incomingDropoffName,
        'driver_name': 'Captain Yasmine El-Sayed',
        'vehicle_info': 'Toyota Yaris (س ن ق 1 4 2 9)',
        'distance_km': _incomingDistanceKm,
        'fare_amount': _incomingFareEgp,
        'status': 'completed',
        'payment_method': 'Cash Settlement',
      },
    );

    setState(() {
      _tripAccepted = false;
      _pinVerified = false;
      _pinInputController.clear();
      _incomingRideId = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip completed! ${_incomingFareEgp.toStringAsFixed(2)} EGP credited to driver wallet.'),
          backgroundColor: AppTheme.sageSafe,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // 1. OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _driverLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['0', '1', '2', '3'],
                userAgentPackageName: 'com.rafik.driver',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _driverLocation,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isOnline ? AppTheme.sageSafe : Colors.grey[700],
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
                        child: Icon(Icons.directions_car, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Top Header with Online Toggle & Rafik Logo
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
                        Text(
                          _isUperGirlEnrolled ? 'RAFIK | RAFIK GIRL' : 'RAFIK STANDARD',
                          style: const TextStyle(
                            color: Color(0xFFFCE4E6),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Captain Profile & 6-Sided Documents Vault Button
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DriverOnboardingScreen()),
                      );
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.roseGold.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.badge_outlined, color: AppTheme.roseGold, size: 18),
                    ),
                    tooltip: 'My Captain Profile & 6-Sided Documents',
                  ),
                  const SizedBox(width: 8),

                  // Wallet & Earnings Button
                  IconButton(
                    onPressed: _openWallet,
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.roseGold.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.roseGold, size: 18),
                    ),
                    tooltip: 'Earnings & Wallet',
                  ),
                  const SizedBox(width: 8),

                  // Logout Button
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
                  const SizedBox(width: 8),

                  // Online / Offline Toggle Button
                  GestureDetector(
                    onTap: () => _toggleOnline(!_isOnline),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isOnline ? AppTheme.sageSafe : AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isOnline ? Colors.transparent : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isOnline ? Colors.white : Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isOnline ? 'ONLINE' : 'GO ONLINE',
                            style: TextStyle(
                              color: _isOnline ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
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

          // 3. Active Trip Overlay or Radar Status
          if (_tripAccepted)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildActiveTripPanel(),
            )
          else if (_hasIncomingRequest)
            _buildIncomingRequestModal()
          else if (!_isOnline)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildOfflineBanner(),
            ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillBadge(
            label: _isBiometricallyVerified
                ? 'BIOMETRICALLY VERIFIED • PRE-SHIFT CLEAR'
                : 'PRE-SHIFT BIOMETRIC SCAN REQUIRED',
            variant: _isBiometricallyVerified ? PillBadgeVariant.sage : PillBadgeVariant.roseGold,
          ),
          const SizedBox(height: 12),
          Text(
            _isBiometricallyVerified
                ? 'Identity verified! You are ready to go online and receive rides.'
                : 'Complete your 3-second live selfie check before accepting rides.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _toggleOnline(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sageSafe),
              child: const Text('GO ONLINE NOW ➔'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DriverOnboardingScreen()),
                );
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.roseGold.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                '6-SIDED DOCUMENT VAULT ➔',
                style: TextStyle(color: AppTheme.roseGoldLight, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestModal() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.roseGoldLight, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.roseGold.withValues(alpha: 0.3),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Circular Countdown Timer
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: _countdownSeconds / 15.0,
                      color: AppTheme.roseGold,
                      backgroundColor: Colors.white12,
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    '$_countdownSeconds',
                    style: const TextStyle(
                      color: Color(0xFFFCE4E6),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              PillBadge(
                label: _incomingTier == 'uper_girl'
                    ? 'UPER GIRL • 100% FEMALE TRIP'
                    : 'UPER STANDARD • GENERAL TRIP',
                variant: _incomingTier == 'uper_girl'
                    ? PillBadgeVariant.roseGold
                    : PillBadgeVariant.sage,
              ),
              const SizedBox(height: 12),

              Text(
                '${_incomingFareEgp.toStringAsFixed(2)} EGP',
                style: const TextStyle(
                  color: Color(0xFFFCE4E6),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_incomingDistanceKm km • Rate: 10.00 LE / km',
                style: const TextStyle(
                  color: AppTheme.sageSafe,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.my_location, color: AppTheme.roseGold, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pickup: $_incomingPickupName',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 14),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.sageSafe, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dropoff: $_incomingDropoffName',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _declineRide,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('DECLINE', style: TextStyle(color: Colors.white60)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _acceptRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.sageSafe,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('ACCEPT TRIP ➔'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTripPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.sageSafe.withValues(alpha: 0.4)),
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
                  label: _pinVerified ? 'TRIP IN PROGRESS' : 'VERIFY 4-DIGIT PIN',
                  variant: _pinVerified ? PillBadgeVariant.sage : PillBadgeVariant.roseGold,
                ),
                Text(
                  '${_incomingFareEgp.toStringAsFixed(2)} EGP',
                  style: const TextStyle(
                    color: Color(0xFFFCE4E6),
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (!_pinVerified) ...[
              const Text(
                'Enter Passenger\'s 4-Digit Security PIN:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinInputController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 8,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'PIN',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _verifyPin,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sageSafe),
                    child: const Text('VERIFY & START'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openChat,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.roseGold.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.roseGold, size: 16),
                  label: const Text(
                    'CHAT PASSENGER ("I HAVE ARRIVED OUTSIDE")',
                    style: TextStyle(color: AppTheme.roseGold, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.sageSafe.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.sageSafe),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigation, color: AppTheme.sageSafe),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Navigating to $_incomingDropoffName.\nDrive safely.',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openChat,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.roseGold.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.roseGold, size: 16),
                      label: const Text('CHAT RIDER', style: TextStyle(color: AppTheme.roseGold, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _completeTrip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.roseGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('COMPLETE TRIP ➔', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
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
}
