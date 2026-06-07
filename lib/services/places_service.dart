import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PlacesService {
  // Bypassing Google API entirely. Using Overpass API (OpenStreetMap) which is 100% FREE!
  static Future<List<dynamic>> getNearbyPlaces(double lat, double lng, String type) async {
    // Map Google types to OpenStreetMap amenity tags
    String amenity = type == 'police' ? 'police' : 'hospital';
    
    // Overpass QL Query: Find amenities within 15000 meters (15km) to ensure enough results
    String query = '''
      [out:json][timeout:25];
      (
        node["amenity"="$amenity"](around:15000,$lat,$lng);
        way["amenity"="$amenity"](around:15000,$lat,$lng);
        relation["amenity"="$amenity"](around:15000,$lat,$lng);
      );
      out center;
    ''';

    final String url = 'https://overpass-api.de/api/interpreter';
    
    try {
      debugPrint('Overpass API POST Request: $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'User-Agent': 'SentinelMeshApp/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'data': query},
      );
      debugPrint('Overpass API HTTP Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List<dynamic>;
        
        List<dynamic> mappedResults = [];
        
        for (var element in elements) {
          // If it's a way/relation, Overpass 'out center' provides center lat/lon
          double? elementLat = element['lat'] ?? element['center']?['lat'];
          double? elementLng = element['lon'] ?? element['center']?['lon'];
          
          if (elementLat == null || elementLng == null) continue;

          String name = element['tags']?['name'] ?? 
                        element['tags']?['name:en'] ?? 
                        'Unknown $type location';

          // Map to Google Places structure so the UI screens don't need any changes!
          mappedResults.add({
            'place_id': element['id'].toString(),
            'name': name,
            'geometry': {
              'location': {
                'lat': elementLat,
                'lng': elementLng,
              }
            }
          });
        }
        
        debugPrint('Overpass API returned ${mappedResults.length} results for $type');
        return mappedResults;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching from Overpass: $e');
      return [];
    }
  }

  static Future<List<dynamic>> getNearbyPoliceStations(double lat, double lng) async {
    return getNearbyPlaces(lat, lng, 'police');
  }

  static Future<List<dynamic>> getNearbyHospitals(double lat, double lng) async {
    return getNearbyPlaces(lat, lng, 'hospital');
  }
}
