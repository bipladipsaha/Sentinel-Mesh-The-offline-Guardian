import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/places_service.dart';

class Neon {
  static const Color bg        = Color(0xFF050508);
  static const Color surface   = Color(0xFF0D0D12);
  static const Color cyan      = Color(0xFF00F0FF);
  static const Color magenta   = Color(0xFFFF2D78);
  static const Color lime      = Color(0xFF39FF14);
  static const Color hotRed    = Color(0xFFFF3333);
  static const Color textMain  = Color(0xFFE8E8EC);
  static const Color textDim   = Color(0xFF6B6B80);
}

class MedicalSupportScreen extends StatefulWidget {
  const MedicalSupportScreen({super.key});

  @override
  State<MedicalSupportScreen> createState() => _MedicalSupportScreenState();
}

class _MedicalSupportScreenState extends State<MedicalSupportScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  List<dynamic> _hospitals = [];
  Set<Marker> _markers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLocationAndPlaces();
  }

  Future<void> _fetchLocationAndPlaces() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      final hospitals = await PlacesService.getNearbyHospitals(
        position.latitude, position.longitude,
      );

      Set<Marker> newMarkers = {};
      newMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );

      for (var hospital in hospitals) {
        final lat = hospital['geometry']['location']['lat'];
        final lng = hospital['geometry']['location']['lng'];
        newMarkers.add(
          Marker(
            markerId: MarkerId(hospital['place_id']),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: hospital['name']),
          )
        );
      }

      setState(() {
        _hospitals = hospitals;
        _markers = newMarkers;
        _isLoading = false;
      });

      if (_mapController != null && _currentLocation != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 14.0));
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint("Error fetching location/places: $e");
    }
  }

  Future<void> _callAmbulance(String? phone) async {
    final url = phone != null ? 'tel:$phone' : 'tel:108'; // India ambulance
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  String _calculateETA(double lat, double lng) {
    if (_currentLocation == null) return "N/A";
    double distanceInMeters = Geolocator.distanceBetween(
      _currentLocation!.latitude, _currentLocation!.longitude,
      lat, lng
    );
    double distanceInKm = distanceInMeters / 1000;
    // ~40 km/h urban average for emergency vehicles
    int etaMinutes = (distanceInKm / 40 * 60).ceil();
    return "~${etaMinutes} min ETA";
  }

  String _formatDistance(double lat, double lng) {
    if (_currentLocation == null) return "N/A";
    double distanceInMeters = Geolocator.distanceBetween(
      _currentLocation!.latitude, _currentLocation!.longitude,
      lat, lng
    );
    return "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
  }

  Widget _buildPlaceCard(dynamic place) {
    final lat = place['geometry']['location']['lat'];
    final lng = place['geometry']['location']['lng'];
    
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Neon.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Neon.hotRed.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.local_hospital, color: Neon.hotRed, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  place['name'] ?? 'Hospital',
                  style: const TextStyle(color: Neon.textMain, fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDistance(lat, lng), style: const TextStyle(color: Neon.textDim, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Neon.hotRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _calculateETA(lat, lng), 
                  style: const TextStyle(color: Neon.hotRed, fontSize: 12, fontWeight: FontWeight.bold)
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _callAmbulance(place['phone']),
                  icon: const Icon(Icons.phone, size: 16, color: Neon.textMain),
                  label: const Text('Call', style: TextStyle(color: Neon.textMain)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Neon.textDim),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigate(lat, lng),
                  icon: const Icon(Icons.navigation, size: 16, color: Neon.bg),
                  label: const Text('Nav', style: TextStyle(color: Neon.bg, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Neon.hotRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Neon.bg,
      appBar: AppBar(
        title: const Text('MEDICAL SUPPORT', style: TextStyle(color: Neon.textMain, fontWeight: FontWeight.w800, letterSpacing: 2)),
        backgroundColor: Neon.bg,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Neon.textMain), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_hospital, color: Neon.hotRed),
            onPressed: () => _callAmbulance(null), // Fallback to 108
          )
        ],
      ),
      body: Stack(
        children: [
          if (_currentLocation != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLocation!,
                zoom: 14.0,
              ),
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            )
          else
            const Center(child: CircularProgressIndicator(color: Neon.hotRed)),
          
          if (_isLoading)
            Container(
              color: Neon.bg.withOpacity(0.7),
              child: const Center(child: CircularProgressIndicator(color: Neon.hotRed)),
            ),

          if (!_isLoading && _hospitals.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 180,
                margin: const EdgeInsets.only(bottom: 24),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _hospitals.length,
                  itemBuilder: (context, index) {
                    return _buildPlaceCard(_hospitals[index]);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
