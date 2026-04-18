import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/ai_chatbot_screen.dart';
import 'services/fall_detection_service.dart';

late List<CameraDescription> _cameras;
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Camera
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("⚠️ Camera Init Error: $e");
  }
  
  // 2. Initialize Notifications & Request Android 13 Permissions early
  try {
    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);
    
    // Explicitly ask for notification permission on startup (Android 13+)
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  } catch (e) {
    debugPrint("⚠️ Notification Init Error: $e");
  }
  
  // 3. Initialize Firebase with correct google-services.json keys
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyB8EbdjZ3vcFDHrmP4VFpUb5sNpN1btdyg",
        authDomain: "esp32iotproject-e9fe1.firebaseapp.com",
        databaseURL: "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app",
        projectId: "esp32iotproject-e9fe1",
        storageBucket: "esp32iotproject-e9fe1.firebasestorage.app",
        messagingSenderId: "312298264533",
        appId: "1:312298264533:android:27386d6b8444fb44038f5c",
      ),
    );
  } catch (e) {
    debugPrint("⚠️ Firebase Init Error: $e");
  }
  
  runApp(const SentinelApp());
}

class SentinelApp extends StatelessWidget {
  const SentinelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFE63946),
        scaffoldBackgroundColor: const Color(0xFF1D3557),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

// ============================================================================
// ROLE SELECTION
// ============================================================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield, size: 100, color: Color(0xFFE63946)),
              const SizedBox(height: 20),
              const Text("Sentinel Mesh", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 60),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: const Color(0xFF457B9D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SenderScreen())),
                child: const Text("SENDER MODE (VICTIM)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              
              const SizedBox(height: 30),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: const Color(0xFF2A9D8F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResponderScreen())),
                child: const Text("RESPONDER MODE (COMMUNITY)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              
              const SizedBox(height: 30),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: const Color(0xFFF4A261),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyChatbotScreen())),
                child: const Text("SAFETY CHATBOT (AI ASSISTANT)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SENDER SCREEN (CAMERA, AUTO-RECORD & FALL DETECTION LOGIC)
// ============================================================================
class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});
  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  
  // Fall Detection
  FallDetectionService? _fallDetectionService;
  bool _fallDetectionEnabled = false;
  bool _fallDetected = false;

  @override
  void initState() {
    super.initState();
    _initSenderPermissionsAndCamera();
  }

  Future<void> _initSenderPermissionsAndCamera() async {
    await [Permission.camera, Permission.microphone].request();
    if (_cameras.isEmpty) return;
    _cameraController = CameraController(_cameras[0], ResolutionPreset.medium, enableAudio: true);
    await _cameraController!.initialize();
    if (mounted) setState(() {});

    // Listen to Firebase to start/stop video based on physical hardware button
    FirebaseDatabase.instance.ref('device001').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        String status = data['status'] ?? 'IDLE';

        if (status == 'ACTIVE' && !_isRecording) {
          _triggerRecording(); // START RECORDING
        } else if (status == 'IDLE' && _isRecording) {
          _triggerRecording(); // STOP RECORDING
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // FALL DETECTION TOGGLE
  // ---------------------------------------------------------------------------
  void _toggleFallDetection(bool enabled) {
    setState(() => _fallDetectionEnabled = enabled);

    if (enabled) {
      _startFallDetection();
    } else {
      _stopFallDetection();
    }
  }

  void _startFallDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_cameras.isEmpty) return;

    _fallDetectionService = FallDetectionService(
      onFallDetected: _onFallDetected,
    );

    // Start streaming camera frames to ML Kit
    _cameraController!.startImageStream((CameraImage image) {
      _fallDetectionService?.processCameraImage(image, _cameras[0]);
    });

    debugPrint("✅ Fall Detection STARTED");
  }

  void _stopFallDetection() {
    _cameraController?.stopImageStream();
    _fallDetectionService?.dispose();
    _fallDetectionService = null;
    if (mounted) setState(() => _fallDetected = false);
    debugPrint("⛔ Fall Detection STOPPED");
  }

  /// Called by FallDetectionService when a fall is detected.
  void _onFallDetected() {
    debugPrint("🚨 FALL DETECTED — AUTO-TRIGGERING SOS!");
    if (mounted) setState(() => _fallDetected = true);

    // Stop the image stream first (can't record video while streaming)
    _cameraController?.stopImageStream();

    // Auto-trigger SOS recording
    if (!_isRecording) {
      _triggerRecording();
    }

    // Push fall alert to Firebase so responders are notified
    FirebaseDatabase.instance.ref('device001').update({
      'status': 'ACTIVE',
      'fallDetected': true,
      'fallTimestamp': DateTime.now().toIso8601String(),
    });

    // Show on-screen alert
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ FALL DETECTED — SOS Activated Automatically!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SOS / RECORDING
  // ---------------------------------------------------------------------------
  Future<void> _triggerRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (!_isRecording) {
      await _cameraController!.startVideoRecording();
      if (mounted) setState(() => _isRecording = true);
    } else {
      XFile video = await _cameraController!.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Evidence Saved: ${video.path}'), backgroundColor: Colors.green));

      // Restart image stream for fall detection if still enabled
      if (_fallDetectionEnabled && _cameras.isNotEmpty) {
        _cameraController!.startImageStream((CameraImage image) {
          _fallDetectionService?.processCameraImage(image, _cameras[0]);
        });
      }
    }
  }

  @override
  void dispose() {
    _fallDetectionService?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sender Mode'), backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 1,
                  height: _cameraController!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  // Fall Detection Toggle
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _fallDetectionEnabled ? Icons.shield : Icons.shield_outlined,
                              color: _fallDetectionEnabled ? Colors.greenAccent : Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            const Text("Fall Detection", style: TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                        Switch(
                          value: _fallDetectionEnabled,
                          onChanged: _toggleFallDetection,
                          activeColor: Colors.greenAccent,
                        ),
                      ],
                    ),
                  ),

                  // Fall Detected Banner
                  if (_fallDetected)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent, width: 2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(child: Text("FALL DETECTED — SOS AUTO-ACTIVATED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // SOS Button
                  GestureDetector(
                    onTap: _triggerRecording,
                    child: Container(
                      height: 140, width: 140,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red[900] : const Color(0xFFE63946),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [if (_isRecording) const BoxShadow(color: Colors.red, blurRadius: 20, spreadRadius: 10)],
                      ),
                      child: Center(child: Text(_isRecording ? "STOP" : "SOS", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RESPONDER SCREEN (NOTIFICATION & RADAR LOGIC)
// ============================================================================
class ResponderScreen extends StatefulWidget {
  const ResponderScreen({super.key});
  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> {
  Position? _myLocation;
  bool _nearbyAlertActive = false;
  double _distanceToVictim = 0.0;
  bool _hasNotified = false;

  @override
  void initState() {
    super.initState();
    _initGeofenceNetwork();
  }

  Future<void> _initGeofenceNetwork() async {
    // Force permission requests for location and notifications
    await [Permission.location, Permission.notification].request();
    
    try {
      _myLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
    }

    FirebaseDatabase.instance.ref('device001').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        String status = data['status'] ?? 'IDLE';

        if (status == 'ACTIVE') {
          double? vLat = data['lat'] != null ? (data['lat'] as num).toDouble() : null;
          double? vLng = data['lng'] != null ? (data['lng'] as num).toDouble() : null;

          if (vLat != null && vLng != null && _myLocation != null) {
            double distance = Geolocator.distanceBetween(_myLocation!.latitude, _myLocation!.longitude, vLat, vLng);
            if (mounted) setState(() { _nearbyAlertActive = true; _distanceToVictim = distance; });
            
            // Trigger Notification
            if (!_hasNotified) { 
              _showEmergencyNotification(distance); 
              _hasNotified = true; 
            }
          } else {
            // Indoor / GPS-less trigger
            if (mounted) setState(() { _nearbyAlertActive = true; _distanceToVictim = 0.0; });
            if (!_hasNotified) { 
              _showEmergencyNotification(0.0); 
              _hasNotified = true; 
            }
          }
        } else {
          // 🔥 CRITICAL FIX: Reset everything when IDLE so the next SOS will ring again!
          if (mounted) {
            setState(() { 
              _nearbyAlertActive = false; 
              _hasNotified = false; 
            });
          }
        }
      }
    });
  }

  Future<void> _showEmergencyNotification(double distance) async {
    // Configured for MAXIMUM volume and screen-waking priority
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'emergency_channel_v2', // Changed channel ID to bypass Android caching
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
      '🚨 COMMUNITY SOS ALERT',
      distance > 0 ? 'Someone needs help ${distance.toStringAsFixed(0)}m away!' : 'Someone needs help nearby!',
      platformDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nearbyAlertActive ? const Color(0xFF450a0a) : const Color(0xFF1D3557),
      appBar: AppBar(title: const Text('Responder Radar'), backgroundColor: Colors.transparent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_nearbyAlertActive ? Icons.warning : Icons.radar, size: 100, color: _nearbyAlertActive ? Colors.redAccent : Colors.tealAccent),
            const SizedBox(height: 20),
            Text(_nearbyAlertActive ? "EMERGENCY DETECTED!" : "Scanning...", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (_nearbyAlertActive) 
              Text(
                _distanceToVictim > 0 ? "${_distanceToVictim.toStringAsFixed(0)} meters away" : "Location tracking...", 
                style: const TextStyle(fontSize: 18)
              ),
          ],
        ),
      ),
    );
  }
}