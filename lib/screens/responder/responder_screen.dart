import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../theme/app_theme.dart';

class ResponderScreen extends StatefulWidget {
  final List<String> deviceIds;
  const ResponderScreen({super.key, required this.deviceIds});

  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> {
  Position? _myLocation;
  bool _nearbyAlertActive = false;
  double _distanceToVictim = 0.0;
  bool _hasNotified = false;
  String _activeDeviceId = '';
  LatLng? _victimLocation;
  GoogleMapController? _mapController;
  
  final List<StreamSubscription> _subscriptions = [];
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initGeofenceNetwork();
  }

  Future<void> _initGeofenceNetwork() async {
    await [Permission.location, Permission.notification].request();
    
    // Initialize notifications plugin (required before .show() calls)
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: initAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    try {
      _myLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
    }

    // Listen to ALL claimed devices, not just a hardcoded one
    for (String deviceId in widget.deviceIds) {
      var sub = FirebaseDatabase.instance.ref('devices').child(deviceId).onValue.listen((event) {
        if (!mounted) return;

        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          String status = data['status'] ?? 'IDLE';

          if (status == 'ACTIVE') {
            double? vLat = data['lat'] != null ? (data['lat'] as num).toDouble() : null;
            double? vLng = data['lng'] != null ? (data['lng'] as num).toDouble() : null;

            if (vLat != null && vLng != null && _myLocation != null) {
              double distance = Geolocator.distanceBetween(_myLocation!.latitude, _myLocation!.longitude, vLat, vLng);
              setState(() { 
                _nearbyAlertActive = true; 
                _distanceToVictim = distance; 
                _activeDeviceId = deviceId; 
                _victimLocation = LatLng(vLat, vLng);
              });
              
              if (_mapController != null) {
                _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_victimLocation!, 15));
              }

              if (!_hasNotified) { 
                _showEmergencyNotification(distance, deviceId); 
                _hasNotified = true; 
              }
            } else {
              setState(() { 
                _nearbyAlertActive = true; 
                _distanceToVictim = 0.0; 
                _activeDeviceId = deviceId; 
              });
              if (!_hasNotified) { 
                _showEmergencyNotification(0.0, deviceId); 
                _hasNotified = true; 
              }
            }
          } else if (status == 'IDLE' && _activeDeviceId == deviceId) {
            setState(() { 
              _nearbyAlertActive = false; 
              _hasNotified = false; 
              _activeDeviceId = '';
              _victimLocation = null;
            });
          }
        }
      });
      _subscriptions.add(sub);
    }
  }

  Future<void> _showEmergencyNotification(double distance, String deviceId) async {
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'hackathon_final_channel_v3',
      'Emergency Alerts',
      channelDescription: 'High priority SOS alerts',
      importance: Importance.max, 
      priority: Priority.max,
      enableVibration: true, 
      playSound: true, 
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    
    await flutterLocalNotificationsPlugin.show(
      0, 
      '🚨 OWNER SOS ALERT ($deviceId)',
      distance > 0 ? 'Your device triggered SOS ${distance.toStringAsFixed(0)}m away!' : 'Your device triggered SOS!',
      platformDetails,
    );
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Widget _buildMap() {
    Set<Marker> markers = {};
    if (_myLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(_myLocation!.latitude, _myLocation!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You (Responder)'),
      ));
    }
    if (_victimLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('victim'),
        position: _victimLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'SOS Location'),
      ));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _victimLocation ?? LatLng(_myLocation?.latitude ?? 0, _myLocation?.longitude ?? 0),
            zoom: 15,
          ),
          markers: markers,
          onMapCreated: (controller) => _mapController = controller,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          mapType: MapType.normal,
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error, width: 2),
              boxShadow: [
                BoxShadow(color: AppTheme.error.withOpacity(0.5), blurRadius: 10, spreadRadius: 2),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning, color: AppTheme.error, size: 30),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SOS IN PROGRESS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("${_distanceToVictim.toStringAsFixed(0)} meters away", style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadar() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radar, size: 100, color: AppTheme.success),
          const SizedBox(height: 20),
          const Text("Scanning your devices...", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text("All devices are secure", style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nearbyAlertActive ? AppTheme.background : AppTheme.background,
      appBar: AppBar(
        title: const Text('My Responder Radar', style: TextStyle(color: Colors.white)), 
        backgroundColor: _nearbyAlertActive ? AppTheme.error.withOpacity(0.2) : Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: _nearbyAlertActive ? _buildMap() : _buildRadar(),
    );
  }
}
