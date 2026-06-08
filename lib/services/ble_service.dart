import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _charSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _retryTimer;

  // Reactive state stream
  final _stateController = StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get stateStream => _stateController.stream;
  BleConnectionState _currentState = BleConnectionState.disconnected;
  BleConnectionState get currentState => _currentState;

  bool get isConnected => _currentState == BleConnectionState.connected;

  // Default UUIDs for standard BLE modules like HM-10 or custom ESP32
  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String charUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  void _setState(BleConnectionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Manually trigger a scan + connect cycle from the UI
  Future<void> startScanningAndConnect(Function onSosTriggered, Function onStateChanged) async {
    // Don't restart if already connected
    if (_currentState == BleConnectionState.connected) return;

    _retryTimer?.cancel();
    _scanSubscription?.cancel();

    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint("Bluetooth not supported");
        return;
      }

      _setState(BleConnectionState.scanning);

      // Stop any existing scan first
      try { await FlutterBluePlus.stopScan(); } catch (_) {}

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == 'Sentinel_ESP' || r.device.advName == 'Sentinel_ESP') {
            FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            _connectToDevice(r.device, onSosTriggered, onStateChanged);
            return;
          }
        }
      });

      // If scan finishes without finding ESP32, schedule a retry
      FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
        if (_currentState == BleConnectionState.scanning) {
          _setState(BleConnectionState.disconnected);
          _scheduleRetry(onSosTriggered, onStateChanged);
        }
      });
    } catch (e) {
      debugPrint("BLE Scan Error: $e");
      _setState(BleConnectionState.disconnected);
      _scheduleRetry(onSosTriggered, onStateChanged);
    }
  }

  void _scheduleRetry(Function onSosTriggered, Function onStateChanged) {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 10), () {
      if (_currentState != BleConnectionState.connected) {
        startScanningAndConnect(onSosTriggered, onStateChanged);
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device, Function onSosTriggered, Function onStateChanged) async {
    _setState(BleConnectionState.connecting);
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      connectedDevice = device;
      _setState(BleConnectionState.connected);
      onStateChanged();

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == charUuid) {
              await characteristic.setNotifyValue(true);
              _charSubscription?.cancel();
              _charSubscription = characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  String msg = utf8.decode(value);
                  if (msg.trim() == '1' || msg.trim() == '2') { // 1: Impact, 2: Button
                    onSosTriggered();
                  }
                }
              });
            }
          }
        }
      }

      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          connectedDevice = null;
          _setState(BleConnectionState.disconnected);
          onStateChanged();
          // Auto-reconnect
          _scheduleRetry(onSosTriggered, onStateChanged);
        }
      });
    } catch (e) {
      debugPrint("Error connecting to BLE: $e");
      connectedDevice = null;
      _setState(BleConnectionState.disconnected);
      _scheduleRetry(onSosTriggered, onStateChanged);
    }
  }

  void stop() {
    _retryTimer?.cancel();
    _scanSubscription?.cancel();
    _charSubscription?.cancel();
    _connectionSub?.cancel();
    connectedDevice?.disconnect();
    connectedDevice = null;
    _setState(BleConnectionState.disconnected);
  }
}
