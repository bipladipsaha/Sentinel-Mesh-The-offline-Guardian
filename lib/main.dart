import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/app_only/police_support_screen.dart';
import 'screens/app_only/medical_support_screen.dart';
import 'widgets/ai_floating_widget.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io';
import 'services/ble_service.dart';

bool _isBleInitialized = false;
bool _isConnecting = false;
bool _autoScanEnabled = false;
BluetoothDevice? _connectedDevice;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('force_connect').listen((event) async {
    _autoScanEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_scan_enabled', true);
    _triggerScan(service);
  });

  service.on('cancel_scan').listen((event) async {
    _autoScanEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_scan_enabled', false);
    _isConnecting = false;
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    try { FlutterBluePlus.stopScan(); } catch (_) {}
    service.invoke('ble_state', {'state': 'disconnected'});
  });

  final prefs = await SharedPreferences.getInstance();
  _autoScanEnabled = prefs.getBool('auto_scan_enabled') ?? false;

  await _initBackgroundBle(flutterLocalNotificationsPlugin, service);
}

Future<void> _initBackgroundBle(FlutterLocalNotificationsPlugin flnp, ServiceInstance service) async {
  if (_isBleInitialized) return;
  _isBleInitialized = true;

  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String charUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  FlutterBluePlus.scanResults.listen((results) async {
    if (_isConnecting || _connectedDevice != null) return;
    
    for (ScanResult r in results) {
      if (r.device.platformName == 'Sentinel_ESP' || r.device.advName == 'Sentinel_ESP' || 
          r.device.platformName == 'Sentinel' || r.device.advName == 'Sentinel') {
        _isConnecting = true;
        try { await FlutterBluePlus.stopScan(); } catch (_) {}
        service.invoke('ble_state', {'state': 'connecting'});
        
        try {
           await r.device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
           _connectedDevice = r.device;
           
           await _setupBleListeners(_connectedDevice!, service, flnp);
           
           service.invoke('ble_state', {'state': 'connected'});
           
           r.device.connectionState.listen((state) {
             if (state == BluetoothConnectionState.disconnected) {
               _connectedDevice = null;
               _isConnecting = false;
               service.invoke('ble_state', {'state': 'disconnected'});
             }
           });
        } catch (e) {
          debugPrint("BLE Connect error: $e");
          _connectedDevice = null;
          service.invoke('ble_state', {'state': 'disconnected'});
          // Cooldown to prevent instant loop from cached stream results
          await Future.delayed(const Duration(seconds: 5));
          _isConnecting = false;
        }
        break; // Only process the first matched device
      }
    }
  });

  FlutterBluePlus.isScanning.listen((isScanning) {
    if (!isScanning && !_isConnecting && _connectedDevice == null) {
      service.invoke('ble_state', {'state': 'disconnected'});
    }
  });

  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (!_autoScanEnabled || _connectedDevice != null || _isConnecting) return;
    
    try {
      var connectedDevices = await FlutterBluePlus.connectedSystemDevices;
      if (connectedDevices.any((d) => d.platformName == 'Sentinel_ESP' || d.advName == 'Sentinel_ESP' || d.platformName == 'Sentinel' || d.advName == 'Sentinel')) {
        _connectedDevice = connectedDevices.firstWhere((d) => d.platformName == 'Sentinel_ESP' || d.advName == 'Sentinel_ESP' || d.platformName == 'Sentinel' || d.advName == 'Sentinel');
        service.invoke('ble_state', {'state': 'connected'});
        _isConnecting = false;
        await _setupBleListeners(_connectedDevice!, service, flutterLocalNotificationsPlugin);
        return;
      }
    } catch (_) {}

    if (FlutterBluePlus.isScanningNow == false) {
      try {
        if (await FlutterBluePlus.isSupported == false) return;
        service.invoke('ble_state', {'state': 'scanning'});
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      } catch (e) {
        debugPrint("⚠️ Background BLE Scan Error: $e");
      }
    }
  });
}

Future<void> _triggerScan(ServiceInstance service) async {
  if (_connectedDevice != null || _isConnecting || FlutterBluePlus.isScanningNow) return;
  try {
    if (await FlutterBluePlus.isSupported == true) {
      service.invoke('ble_state', {'state': 'scanning'});
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    }
  } catch (e) {
    service.invoke('ble_state', {'state': 'disconnected'});
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sentinel_bg', // id
    'Sentinel Background Service', // name
    description: 'Keeps connection to ESP32 alive.', // description
    importance: Importance.low, // low importance keeps it silent
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'sentinel_bg',
      initialNotificationTitle: 'Sentinel Connected',
      initialNotificationContent: 'Listening for ESP32 SOS triggers...',
      foregroundServiceNotificationId: 889,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: (ServiceInstance service) => false,
    ),
  );
  await service.startService();
}

late List<CameraDescription> _cameras;
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// ── Cyberpunk Neon Palette ──────────────────────────────────────────────────
class _Neon {
  static const Color bg        = Color(0xFF050508);
  static const Color surface   = Color(0xFF0D0D12);
  static const Color cyan      = Color(0xFF00F0FF);
  static const Color magenta   = Color(0xFFFF2D78);
  static const Color lime      = Color(0xFF39FF14);
  static const Color hotRed    = Color(0xFFFF3333);
  static const Color amber     = Color(0xFFFFB300);
  static const Color textMain  = Color(0xFFE8E8EC);
  static const Color textDim   = Color(0xFF6B6B80);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Camera (non-critical — app works without it)
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
    debugPrint("⚠️ Camera Init Error: $e");
  }
  
  // Load env variables
  await dotenv.load(fileName: ".env");

  // 2. Initialize Firebase FIRST (critical for app functionality)
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: dotenv.env['FIREBASE_API_KEY'] ?? '',
        authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '',
        databaseURL: dotenv.env['FIREBASE_DATABASE_URL'] ?? '',
        projectId: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
        storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '',
        messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
        appId: dotenv.env['FIREBASE_APP_ID'] ?? '',
      ),
    );
  } catch (e) {
    debugPrint("⚠️ Firebase Init Error: $e");
  }
  
  // 3. Initialize Notifications (non-critical)
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

  // 4. Start background service AFTER Firebase (non-critical)
  try {
    await initializeService();
  } catch (e) {
    debugPrint("⚠️ Background Service Init Error: $e");
  }
  
  runApp(const SentinelApp());
}

class SentinelApp extends StatelessWidget {
  const SentinelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AIFloatingWidget(
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData.dark().copyWith(
        primaryColor: _Neon.cyan,
        scaffoldBackgroundColor: _Neon.bg,
        colorScheme: const ColorScheme.dark(
          primary: _Neon.cyan,
          secondary: _Neon.magenta,
          surface: _Neon.surface,
          error: _Neon.hotRed,
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

// ============================================================================
// ROLE SELECTION
// ============================================================================
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  StreamSubscription? _bleSub;
  StreamSubscription? _sosSub;
  StreamSubscription? _firebaseSosSub;
  String _bleState = 'disconnected';
  bool _alreadyNavigatedToSos = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _requestPermissions();

    _bleSub = FlutterBackgroundService().on('ble_state').listen((event) {
      if (mounted) {
        setState(() {
          _bleState = event?['state'] ?? 'disconnected';
        });
      }
    });

    _sosSub = FlutterBackgroundService().on('sos_triggered').listen((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _navigateToSender();
      }
    });

    // 🔥 Firebase SOS listener — most reliable path
    _firebaseSosSub = FirebaseDatabase.instance
        .ref('devices/device001/status')
        .onValue
        .listen((event) {
      final status = event.snapshot.value?.toString() ?? 'IDLE';
      debugPrint('Firebase device001/status = $status');
      if (status == 'ACTIVE' && mounted && !_alreadyNavigatedToSos) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          debugPrint('🚨 Firebase ACTIVE detected! Navigating to SOS camera...');
          _navigateToSender();
        }
      } else if (status != 'ACTIVE') {
        _alreadyNavigatedToSos = false;
      }
    });
    
    // Check initial connection status natively just in case
    FlutterBluePlus.connectedSystemDevices.then((devices) {
      if (devices.any((d) => d.platformName == 'Sentinel_ESP' || d.advName == 'Sentinel_ESP' || d.platformName == 'Sentinel' || d.advName == 'Sentinel')) {
        if (mounted) setState(() => _bleState = 'connected');
      }
    });
  }

  void _navigateToSender() {
    if (_alreadyNavigatedToSos) return;
    _alreadyNavigatedToSos = true;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SenderScreen()));
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.camera,
      Permission.microphone,
    ].request();
  }

  void _onConnectTap() async {
    if (_bleState == 'disconnected') {
      var scanPerm = await Permission.bluetoothScan.request();
      var connPerm = await Permission.bluetoothConnect.request();
      var locPerm = await Permission.location.request();
      
      if ((scanPerm.isGranted || scanPerm.isLimited) && (connPerm.isGranted || connPerm.isLimited)) {
        FlutterBackgroundService().invoke('force_connect');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth permissions required to connect!'),
              backgroundColor: _Neon.hotRed,
            ),
          );
        }
      }
    } else {
      FlutterBackgroundService().invoke('cancel_scan');
    }
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _sosSub?.cancel();
    _firebaseSosSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Color _bleStatusColor() {
    switch (_bleState) {
      case 'connected': return _Neon.lime;
      case 'connecting': return _Neon.amber;
      case 'scanning': return _Neon.cyan;
      default: return _Neon.hotRed;
    }
  }

  String _bleStatusText() {
    switch (_bleState) {
      case 'connected': return "ESP32 CONNECTED";
      case 'connecting': return "CONNECTING…";
      case 'scanning': return "SCANNING…";
      default: return "DISCONNECTED";
    }
  }

  IconData _bleStatusIcon() {
    switch (_bleState) {
      case 'connected': return Icons.bluetooth_connected;
      case 'connecting': return Icons.bluetooth_searching;
      case 'scanning': return Icons.bluetooth_searching;
      default: return Icons.bluetooth_disabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _bleStatusColor();
    final bool isWorking = _bleState == 'scanning' || _bleState == 'connecting';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_Neon.bg, _Neon.surface, _Neon.bg],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // ── Pulsing Shield Icon with Neon Glow ──
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Container(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _Neon.cyan.withOpacity(0.05),
                          boxShadow: [
                            BoxShadow(color: _Neon.cyan.withOpacity(0.3 * _pulseAnim.value), blurRadius: 40, spreadRadius: 8),
                            BoxShadow(color: _Neon.magenta.withOpacity(0.15 * _pulseAnim.value), blurRadius: 60, spreadRadius: 4),
                          ],
                          border: Border.all(color: _Neon.cyan.withOpacity(0.3 * _pulseAnim.value), width: 2),
                        ),
                        child: const Icon(Icons.shield, size: 100, color: _Neon.cyan),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  "SENTINEL MESH",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: _Neon.textMain,
                    shadows: [
                      Shadow(color: _Neon.cyan.withOpacity(0.6), blurRadius: 20),
                      Shadow(color: _Neon.cyan.withOpacity(0.3), blurRadius: 40),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "DECENTRALIZED SAFETY NETWORK",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 3, color: _Neon.textDim),
                ),
                const SizedBox(height: 28),

                // ── BLE Status Chip + Connect Button ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: statusColor.withOpacity(0.15), blurRadius: 16, spreadRadius: 0),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Animated status dot
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                          boxShadow: [BoxShadow(color: statusColor.withOpacity(0.6), blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(_bleStatusIcon(), color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bleStatusText(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      // Connect / Disconnect button
                      GestureDetector(
                        onTap: _onConnectTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isWorking ? statusColor.withOpacity(0.2) : statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor.withOpacity(0.6), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isWorking) ...[
                                SizedBox(
                                  width: 12, height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _bleState == 'disconnected' ? "CONNECT" : (_bleState == 'connected' ? "DISCONNECT" : "CANCEL"),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
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

                const SizedBox(height: 28),

                // ── Sender Button ──
                _NeonButton(
                  label: "SENDER MODE  ·  VICTIM",
                  icon: Icons.sos,
                  glowColor: _Neon.magenta,
                  fillColor: _Neon.magenta.withOpacity(0.08),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SenderScreen())),
                ),
                
                const SizedBox(height: 16),

                // ── Responder Button ──
                _NeonButton(
                  label: "RESPONDER  ·  COMMUNITY",
                  icon: Icons.radar,
                  glowColor: _Neon.cyan,
                  fillColor: _Neon.cyan.withOpacity(0.08),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResponderScreen())),
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  children: [
                    const Expanded(child: Divider(color: _Neon.textDim)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("APP-ONLY TOOLS", style: TextStyle(color: _Neon.textDim, fontSize: 12, letterSpacing: 2)),
                    ),
                    const Expanded(child: Divider(color: _Neon.textDim)),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _NeonButton(
                        label: "POLICE",
                        icon: Icons.local_police,
                        glowColor: _Neon.cyan,
                        fillColor: _Neon.cyan.withOpacity(0.05),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliceSupportScreen())),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _NeonButton(
                        label: "MEDICAL",
                        icon: Icons.health_and_safety,
                        glowColor: _Neon.hotRed,
                        fillColor: _Neon.hotRed.withOpacity(0.05),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicalSupportScreen())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable Neon-Bordered Button ───────────────────────────────────────────
class _NeonButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color glowColor;
  final Color fillColor;
  final VoidCallback onTap;

  const _NeonButton({required this.label, required this.icon, required this.glowColor, required this.fillColor, required this.onTap});

  @override
  State<_NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<_NeonButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: _pressed ? widget.glowColor.withOpacity(0.15) : widget.fillColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.glowColor.withOpacity(_pressed ? 0.8 : 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(color: widget.glowColor.withOpacity(_pressed ? 0.4 : 0.15), blurRadius: _pressed ? 24 : 12, spreadRadius: _pressed ? 2 : 0),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: widget.glowColor, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: widget.glowColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SENDER SCREEN (CAMERA RECORDING — NO AGORA)
// ============================================================================
class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});
  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isRecording = false;
  bool _pendingSosTrigger = false;
  late AnimationController _sosPulse;
  late Animation<double> _sosAnim;
  StreamSubscription? _sosSub;
  StreamSubscription? _firebaseSosSub;
  StreamSubscription? _directBleSub;

  @override
  void initState() {
    super.initState();
    _sosPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _sosAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _sosPulse, curve: Curves.easeInOut));
    _initCamera();

    _sosSub = FlutterBackgroundService().on('sos_triggered').listen((_) {
      if (mounted && !_isRecording) {
        debugPrint('BLE SOS trigger (background) detected! Starting record...');
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          _pendingSosTrigger = true;
        } else {
          _triggerSos();
        }
      }
    });

    // 🔥 Firebase SOS listener
    _firebaseSosSub = FirebaseDatabase.instance
        .ref('devices/device001/status')
        .onValue
        .listen((event) {
      final status = event.snapshot.value?.toString() ?? 'IDLE';
      debugPrint('SenderScreen Firebase status = $status');
      if (status == 'ACTIVE' && mounted && !_isRecording) {
        debugPrint('🚨 Firebase ACTIVE detected on SenderScreen! Auto-recording...');
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          _pendingSosTrigger = true;
        } else {
          _triggerSos();
        }
      }
    });

    // 🔌 DIRECT BLE listener in UI thread — bypasses background service entirely
    _setupDirectBleListener();
  }

  Future<void> _setupDirectBleListener() async {
    try {
      // Find any already-connected Sentinel ESP32 device
      List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedSystemDevices;
      BluetoothDevice? espDevice;
      for (var d in connectedDevices) {
        if (d.platformName == 'Sentinel_ESP' || d.advName == 'Sentinel_ESP' ||
            d.platformName == 'Sentinel' || d.advName == 'Sentinel') {
          espDevice = d;
          break;
        }
      }

      if (espDevice == null) {
        debugPrint('⚡ Direct BLE: No connected ESP32 found, will rely on background service.');
        return;
      }

      debugPrint('⚡ Direct BLE: Found connected ESP32: ${espDevice.platformName}');
      List<BluetoothService> services = await espDevice.discoverServices();
      for (var svc in services) {
        if (svc.uuid.toString() == '0000ffe0-0000-1000-8000-00805f9b34fb') {
          for (var charc in svc.characteristics) {
            if (charc.uuid.toString() == '0000ffe1-0000-1000-8000-00805f9b34fb') {
              debugPrint('⚡ Direct BLE: Subscribed to SOS characteristic!');
              await charc.setNotifyValue(true);
              _directBleSub = charc.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  String msg = utf8.decode(value);
                  debugPrint('⚡ Direct BLE received: "$msg"');
                  if (msg.trim() == '1' || msg.trim() == '2') {
                    debugPrint('🚨🚨🚨 DIRECT BLE SOS TRIGGER! Starting recording NOW!');
                    if (mounted && !_isRecording) {
                      if (_cameraController == null || !_cameraController!.value.isInitialized) {
                        _pendingSosTrigger = true;
                      } else {
                        _triggerSos();
                      }
                    }
                  }
                }
              });
              return; // Done
            }
          }
        }
      }
      debugPrint('⚡ Direct BLE: SOS characteristic not found on device.');
    } catch (e) {
      debugPrint('⚡ Direct BLE setup error: $e');
    }
  }

  Future<void> _initCamera() async {
    await [Permission.camera, Permission.microphone, Permission.location].request();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      // Look for the back camera, fallback to the first available if not found
      CameraDescription targetCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      _cameraController = CameraController(targetCamera, ResolutionPreset.medium, enableAudio: true);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
    }

    // Check if launched by ESP32 Background Service
    final prefs = await SharedPreferences.getInstance();
    bool autoStart = prefs.getBool('auto_start_sos') ?? false;
    if (autoStart && !_isRecording) {
      debugPrint('ESP32 Wakeup detected! Starting record...');
      await prefs.setBool('auto_start_sos', false);
      _pendingSosTrigger = true;
    }

    if (_pendingSosTrigger) {
      _pendingSosTrigger = false;
      _triggerSos();
    }
  }

  Future<void> _triggerSos() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (!_isRecording) {
      // START recording
      await _cameraController!.startVideoRecording();
      if (mounted) setState(() => _isRecording = true);

      // Push GPS + ACTIVE status to Firebase for responders
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      } catch (_) {}
      FirebaseDatabase.instance.ref('devices').child('device001').update({
        'status': 'ACTIVE',
        'lat': pos?.latitude,
        'lng': pos?.longitude,
      });
    } else {
      // STOP recording
      final XFile video = await _cameraController!.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      FirebaseDatabase.instance.ref('devices').child('device001').update({'status': 'IDLE'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Evidence saved: ${video.path}', style: const TextStyle(color: _Neon.textMain)),
        backgroundColor: _Neon.lime.withOpacity(0.25),
      ));
    }
  }

  @override
  void dispose() {
    _sosPulse.dispose();
    _sosSub?.cancel();
    _firebaseSosSub?.cancel();
    _directBleSub?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = _isRecording ? _Neon.hotRed : _Neon.magenta;

    return Scaffold(
      backgroundColor: _Neon.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text('SOS MODE', style: TextStyle(color: _Neon.textMain, fontWeight: FontWeight.w800, letterSpacing: 2)),
            if (_isRecording) ...[
              const SizedBox(width: 12),
              AnimatedBuilder(
                animation: _sosAnim,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Neon.hotRed.withOpacity(0.15 + 0.15 * _sosAnim.value),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _Neon.hotRed.withOpacity(0.5 + 0.3 * _sosAnim.value)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: _Neon.hotRed.withOpacity(0.5 + 0.5 * _sosAnim.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('REC', style: TextStyle(color: _Neon.hotRed, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: _Neon.textMain), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          // Camera preview
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
            )
          else
            Container(color: _Neon.bg),

          // ── Red overlay when recording ──
          if (_isRecording)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _Neon.hotRed.withOpacity(0.05),
                        Colors.transparent,
                        _Neon.hotRed.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── SOS Button ──
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedBuilder(
                    animation: _sosAnim,
                    builder: (_, __) {
                      return GestureDetector(
                        onTap: _triggerSos,
                        child: Container(
                          height: 140, width: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording
                                ? _Neon.hotRed.withOpacity(0.2)
                                : _Neon.magenta.withOpacity(0.1),
                            border: Border.all(
                              color: activeColor.withOpacity(0.6 + 0.4 * _sosAnim.value),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withOpacity(0.3 + 0.3 * _sosAnim.value),
                                blurRadius: 30 + 20 * _sosAnim.value,
                                spreadRadius: 4 + 6 * _sosAnim.value,
                              ),
                              BoxShadow(
                                color: activeColor.withOpacity(0.1),
                                blurRadius: 80,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _isRecording ? 'STOP' : 'SOS',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                color: activeColor,
                                shadows: [Shadow(color: activeColor.withOpacity(0.8), blurRadius: 20)],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Background ESP32 Monitoring Active',
                    style: TextStyle(color: _Neon.textDim, fontSize: 11, letterSpacing: 1),
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
// RESPONDER SCREEN (MAP & ROUTING LOGIC)
// ============================================================================
class ResponderScreen extends StatefulWidget {
  const ResponderScreen({super.key});
  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> with SingleTickerProviderStateMixin {
  Position? _myLocation;
  Position? _victimLocation;
  bool _nearbyAlertActive = false;
  double _distanceToVictim = 0.0;
  bool _hasNotified = false;
  late AnimationController _radarPulse;
  late Animation<double> _radarAnim;
  GoogleMapController? _mapController;
  StreamSubscription? _devicesSubscription;

  @override
  void initState() {
    super.initState();
    _radarPulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _radarAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _radarPulse, curve: Curves.easeInOut));
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

    _devicesSubscription = FirebaseDatabase.instance.ref('devices').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final Map<dynamic, dynamic> allDevices = event.snapshot.value as Map<dynamic, dynamic>;
        if (allDevices.isEmpty) return;
        final data = Map<String, dynamic>.from(allDevices.values.first as Map);
        String status = data['status'] ?? 'IDLE';

        if (status == 'ACTIVE') {
          double? vLat = data['lat'] != null ? (data['lat'] as num).toDouble() : null;
          double? vLng = data['lng'] != null ? (data['lng'] as num).toDouble() : null;

          if (vLat != null && vLng != null && _myLocation != null) {
            double distance = Geolocator.distanceBetween(_myLocation!.latitude, _myLocation!.longitude, vLat, vLng);
            if (mounted) setState(() { 
              _nearbyAlertActive = true; 
              _distanceToVictim = distance;
              _victimLocation = Position(longitude: vLng, latitude: vLat, timestamp: DateTime.now(), accuracy: 1, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0);
            });
            
            // Move camera to fit both
            _fitMapToBoth();

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
          // CRITICAL FIX: Reset everything when IDLE so the next SOS will ring again!
          if (mounted) {
            setState(() { 
              _nearbyAlertActive = false; 
              _hasNotified = false; 
              _victimLocation = null;
            });
          }
        }
      }
    });
  }

  void _fitMapToBoth() {
    if (_mapController == null || _myLocation == null || _victimLocation == null) return;
    
    LatLngBounds bounds;
    if (_myLocation!.latitude > _victimLocation!.latitude && _myLocation!.longitude > _victimLocation!.longitude) {
      bounds = LatLngBounds(southwest: LatLng(_victimLocation!.latitude, _victimLocation!.longitude), northeast: LatLng(_myLocation!.latitude, _myLocation!.longitude));
    } else if (_myLocation!.longitude > _victimLocation!.longitude) {
      bounds = LatLngBounds(southwest: LatLng(_myLocation!.latitude, _victimLocation!.longitude), northeast: LatLng(_victimLocation!.latitude, _myLocation!.longitude));
    } else if (_myLocation!.latitude > _victimLocation!.latitude) {
      bounds = LatLngBounds(southwest: LatLng(_victimLocation!.latitude, _myLocation!.longitude), northeast: LatLng(_myLocation!.latitude, _victimLocation!.longitude));
    } else {
      bounds = LatLngBounds(southwest: LatLng(_myLocation!.latitude, _myLocation!.longitude), northeast: LatLng(_victimLocation!.latitude, _victimLocation!.longitude));
    }
    
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
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

  Future<void> _launchNavigation() async {
    if (_victimLocation == null) return;
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${_victimLocation!.latitude},${_victimLocation!.longitude}&travelmode=walking';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  void dispose() {
    _radarPulse.dispose();
    _devicesSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color stateColor = _nearbyAlertActive ? _Neon.hotRed : _Neon.cyan;

    return Scaffold(
      backgroundColor: _Neon.bg,
      appBar: AppBar(
        title: Text(
          'RESPONDER RADAR',
          style: TextStyle(color: _Neon.textMain, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: _Neon.textMain), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          // Upper Section: Map or Radar Scan
          Expanded(
            flex: 3,
            child: _nearbyAlertActive && _victimLocation != null
                ? Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _Neon.hotRed, width: 2),
                      boxShadow: [
                        BoxShadow(color: _Neon.hotRed.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)
                      ]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_myLocation!.latitude, _myLocation!.longitude),
                          zoom: 14,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        markers: {
                          Marker(
                            markerId: const MarkerId('victim'),
                            position: LatLng(_victimLocation!.latitude, _victimLocation!.longitude),
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                            infoWindow: const InfoWindow(title: 'Victim Location'),
                          )
                        },
                        onMapCreated: (controller) {
                          _mapController = controller;
                          _fitMapToBoth();
                        },
                      ),
                    ),
                  )
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _radarAnim,
                        builder: (_, __) {
                          return Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: stateColor.withOpacity(0.05),
                              border: Border.all(color: stateColor.withOpacity(0.2 + 0.3 * _radarAnim.value), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: stateColor.withOpacity(0.2 + 0.3 * _radarAnim.value),
                                  blurRadius: 30 + 20 * _radarAnim.value,
                                  spreadRadius: 4 + 8 * _radarAnim.value,
                                ),
                              ],
                            ),
                            child: Icon(Icons.radar, size: 80, color: stateColor),
                          );
                        },
                      ),
                    ),
                  ),
          ),

          // Lower Section: Info & Actions
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: _Neon.surface,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
                boxShadow: [
                  BoxShadow(color: _Neon.cyan.withOpacity(0.05), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, -5))
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _nearbyAlertActive ? "EMERGENCY DETECTED" : "SCANNING SECTORS…",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: stateColor,
                      shadows: [Shadow(color: stateColor.withOpacity(0.5), blurRadius: 15)],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_nearbyAlertActive) ...[
                    Text(
                      _distanceToVictim > 0 ? "${_distanceToVictim.toStringAsFixed(0)} meters away" : "Location tracking…", 
                      style: TextStyle(fontSize: 16, color: _Neon.textMain, letterSpacing: 1),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Neon.hotRed.withOpacity(0.15),
                          foregroundColor: _Neon.hotRed,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: _Neon.hotRed.withOpacity(0.8), width: 1.5)
                          ),
                          elevation: 0,
                        ),
                        onPressed: _launchNavigation,
                        icon: const Icon(Icons.navigation, size: 24),
                        label: const Text("NAVIGATE TO VICTIM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    )
                  ] else ...[
                    Text(
                      "All sectors clear. You are a designated community responder. Stay alert.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _Neon.lime.withOpacity(0.7), height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _setupBleListeners(BluetoothDevice device, ServiceInstance service, FlutterLocalNotificationsPlugin flnp) async {
  try {
    List<BluetoothService> services = await device.discoverServices();
    for (var svc in services) {
      if (svc.uuid.toString() == "0000ffe0-0000-1000-8000-00805f9b34fb") {
        for (var charc in svc.characteristics) {
          if (charc.uuid.toString() == "0000ffe1-0000-1000-8000-00805f9b34fb") {
            await charc.setNotifyValue(true);
            charc.onValueReceived.listen((value) async {
              if (value.isNotEmpty) {
                String msg = utf8.decode(value);
                if (msg.trim() == '1' || msg.trim() == '2') {
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('auto_start_sos', true);
                  
                  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
                    'emergency_wakeup',
                    'Emergency Wakeup',
                    importance: Importance.max,
                    priority: Priority.max,
                    fullScreenIntent: true,
                    category: AndroidNotificationCategory.alarm,
                  );
                  const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
                  await flnp.show(
                    888, 
                    '🚨 ESP32 SOS TRIGGERED!', 
                    'Impact or button detected! Launching Sentinel...', 
                    platformDetails
                  );
                  
                  service.invoke('sos_triggered');
                  
                  if (Platform.isAndroid) {
                    const intent = AndroidIntent(
                      action: 'android.intent.action.MAIN',
                      package: 'com.example.sentinel_mesh',
                      componentName: 'com.example.sentinel_mesh.MainActivity',
                      arguments: <String, dynamic>{'AUTO_RECORD': true},
                      flags: <int>[268435456], // FLAG_ACTIVITY_NEW_TASK
                    );
                    await intent.launch();
                  }
                }
              }
            });
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Setup BLE Listeners Error: $e");
  }
}