import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class LiveTrackerScreen extends StatefulWidget {
  const LiveTrackerScreen({super.key});

  @override
  State<LiveTrackerScreen> createState() => _LiveTrackerScreenState();
}

class _LiveTrackerScreenState extends State<LiveTrackerScreen> {
  Position? _myLocation;
  List<Map<String, dynamic>> _nearbyEmergencies = [];
  final double _searchRadiusMeters = 5000; // 5km search radius

  @override
  void initState() {
    super.initState();
    _initTracker();
  }

  Future<void> _initTracker() async {
    await Permission.location.request();
    try {
      _myLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
    }

    FirebaseDatabase.instance.ref('devices').onValue.listen((event) {
      if (!mounted || _myLocation == null) return;

      List<Map<String, dynamic>> activeEmergencies = [];

      if (event.snapshot.value != null) {
        final Map<dynamic, dynamic> allDevices = event.snapshot.value as Map<dynamic, dynamic>;
        
        allDevices.forEach((key, value) {
          final data = Map<String, dynamic>.from(value as Map);
          if (data['status'] == 'ACTIVE' && data['lat'] != null && data['lng'] != null) {
            double vLat = (data['lat'] as num).toDouble();
            double vLng = (data['lng'] as num).toDouble();
            
            double distance = Geolocator.distanceBetween(_myLocation!.latitude, _myLocation!.longitude, vLat, vLng);
            
            if (distance <= _searchRadiusMeters) {
              activeEmergencies.add({
                'id': key,
                'distance': distance,
                'lat': vLat,
                'lng': vLng,
              });
            }
          }
        });
      }

      // Sort by distance
      activeEmergencies.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      setState(() {
        _nearbyEmergencies = activeEmergencies;
      });
    });
  }

  Future<void> _openMaps(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Tracker'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.background, AppTheme.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: GlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.radar, color: AppTheme.secondary, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Scanning Nearby Area', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text('Radius: ${_searchRadiusMeters / 1000}km', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (_myLocation != null)
                      const Icon(Icons.check_circle, color: AppTheme.success)
                    else
                      const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _nearbyEmergencies.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.health_and_safety_outlined, size: 80, color: AppTheme.success.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text('No emergencies nearby', style: TextStyle(color: AppTheme.success, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text('The area is clear', style: TextStyle(color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _nearbyEmergencies.length,
                      itemBuilder: (context, index) {
                        final alert = _nearbyEmergencies[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: GlassCard(
                            padding: 16,
                            border: Border.all(color: AppTheme.error.withOpacity(0.5)),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.2), shape: BoxShape.circle),
                                  child: const Icon(Icons.warning, color: AppTheme.error),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('SOS Alert', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('${(alert['distance'] as double).toStringAsFixed(0)} meters away', style: const TextStyle(color: AppTheme.error)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.navigation, color: AppTheme.secondary),
                                  onPressed: () => _openMaps(alert['lat'], alert['lng']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
