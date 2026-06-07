import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _charSubscription;

  bool get isConnected => connectedDevice != null;

  // Default UUIDs for standard BLE modules like HM-10 or custom ESP32
  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String charUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  Future<void> startScanningAndConnect(Function onSosTriggered, Function onStateChanged) async {
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported");
      return;
    }

    // Start scanning
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == 'Sentinel_ESP' || r.device.advName == 'Sentinel_ESP') {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device, onSosTriggered, onStateChanged);
          break;
        }
      }
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device, Function onSosTriggered, Function onStateChanged) async {
    try {
      await device.connect();
      connectedDevice = device;
      onStateChanged();

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == charUuid) {
              await characteristic.setNotifyValue(true);
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

      device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          connectedDevice = null;
          onStateChanged();
          // Try reconnecting
          Future.delayed(const Duration(seconds: 5), () => startScanningAndConnect(onSosTriggered, onStateChanged));
        }
      });
    } catch (e) {
      print("Error connecting to BLE: $e");
    }
  }

  void stop() {
    _scanSubscription?.cancel();
    _charSubscription?.cancel();
    connectedDevice?.disconnect();
  }
}
