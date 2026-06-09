import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SenderScreen extends StatefulWidget {
  final bool autoRecord; // Legacy param, ignored now
  final String deviceId;
  const SenderScreen({super.key, this.autoRecord = false, required this.deviceId});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  StreamSubscription? _firebaseSubscription;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    _initSenderPermissionsAndCamera();
  }

  Future<void> _initSenderPermissionsAndCamera() async {
    await [Permission.camera, Permission.microphone, Permission.location, Permission.bluetoothScan, Permission.bluetoothConnect].request();

    // Setup Firebase listener first (independent of camera)
    _firebaseSubscription = FirebaseDatabase.instance.ref('devices').child(widget.deviceId).onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        String status = data['status'] ?? 'IDLE';

        if (status == 'IDLE' && _isRecording) {
          _stopRecording();
        }
      }
    });

    // Init camera (non-critical — SOS still works without it)
    _cameras = await availableCameras();
    if (_cameras.isNotEmpty) {
      _cameraController = CameraController(_cameras[0], ResolutionPreset.medium, enableAudio: true);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } else {
      debugPrint('No cameras available on this device');
    }

    // Check if launched by ESP32 Background Service
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool autoStart = prefs.getBool('auto_start_sos') ?? false;
    if (autoStart && !_isRecording) {
      debugPrint("ESP32 Wakeup detected! Starting record...");
      await prefs.setBool('auto_start_sos', false); // Reset flag
      _triggerSosAction();
    }
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isRecording) return; 
    await _cameraController!.startVideoRecording();
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (!_isRecording) return; 
    XFile video = await _cameraController!.stopVideoRecording();
    if (mounted) setState(() => _isRecording = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Evidence Saved: ${video.path}'), backgroundColor: Colors.green));
  }

  Future<void> _triggerSosAction() async {
    if (_isRecording) {
      await _stopRecording();
      FirebaseDatabase.instance.ref('devices').child(widget.deviceId).update({'status': 'IDLE'});
    } else {
      await _startRecording();
      // Fetch exact GPS to send to Responder map
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      } catch (e) {
        debugPrint("Could not get location for SOS");
      }
      // Only include coordinates if GPS succeeded — don't overwrite valid data with nulls
      final Map<String, dynamic> updateData = {'status': 'ACTIVE'};
      if (pos != null) {
        updateData['lat'] = pos.latitude;
        updateData['lng'] = pos.longitude;
      }
      FirebaseDatabase.instance.ref('devices').child(widget.deviceId).update(updateData);
    }
  }

  @override
  void dispose() {
    _firebaseSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text('SOS Mode', style: TextStyle(color: Colors.white)),
            if (_isRecording) ...[
              const SizedBox(width: 10),
              const _RecIndicator(),
            ],
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.bluetooth, color: Colors.blueAccent),
          )
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(color: const Color(0xFF0A0E1A)),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _triggerSosAction,
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
                  const SizedBox(height: 20),
                  Text(
                    "Background ESP32 Monitoring Active",
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecIndicator extends StatefulWidget {
  const _RecIndicator();
  @override
  State<_RecIndicator> createState() => _RecIndicatorState();
}

class _RecIndicatorState extends State<_RecIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (_, __) => Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: _animController.value > 0.5 ? Colors.red : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'REC',
            style: TextStyle(
              color: _animController.value > 0.5 ? Colors.red : Colors.transparent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
