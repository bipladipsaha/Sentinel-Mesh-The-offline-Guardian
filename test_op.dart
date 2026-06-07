import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  String query = '''[out:json][timeout:25];(node["amenity"="police"](around:15000,22.629306,88.3224155);way["amenity"="police"](around:15000,22.629306,88.3224155);relation["amenity"="police"](around:15000,22.629306,88.3224155););out center;''';
  
  final response = await http.post(
    Uri.parse('https://overpass-api.de/api/interpreter'), 
    headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'}, 
    body: {'data': query}
  );
  
  print('Status: \${response.statusCode}');
  if (response.statusCode == 200) {
    print('Results: \${json.decode(response.body)['elements'].length}');
  } else {
    print('Body: \${response.body}');
  }
}
