import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeviceService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Claim a device by its unique ID
  Future<void> claimDevice(String deviceId, String deviceName) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // First check if the device exists or has been claimed
    final deviceSnapshot = await _dbRef.child('devices').child(deviceId).get();
    
    if (deviceSnapshot.exists) {
      final data = Map<String, dynamic>.from(deviceSnapshot.value as Map);
      if (data['ownerUid'] != null && data['ownerUid'] != user.uid) {
        throw Exception('Device is already claimed by another user');
      }
    }

    // Update the device node
    await _dbRef.child('devices').child(deviceId).update({
      'ownerUid': user.uid,
      'deviceName': deviceName,
      'status': deviceSnapshot.exists ? (deviceSnapshot.child('status').value ?? 'IDLE') : 'IDLE',
    });

    // Update the user's espDevices list
    final userSnapshot = await _dbRef.child('users').child(user.uid).child('espDevices').get();
    List<String> devices = [];
    if (userSnapshot.exists) {
      devices = List<String>.from(userSnapshot.value as List? ?? []);
    }
    
    if (!devices.contains(deviceId)) {
      devices.add(deviceId);
      await _dbRef.child('users').child(user.uid).update({
        'espDevices': devices,
      });
    }
  }

  // Remove a device
  Future<void> removeDevice(String deviceId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Remove owner from device
    await _dbRef.child('devices').child(deviceId).child('ownerUid').remove();

    // Remove from user's list
    final userSnapshot = await _dbRef.child('users').child(user.uid).child('espDevices').get();
    if (userSnapshot.exists) {
      List<String> devices = List<String>.from(userSnapshot.value as List);
      devices.remove(deviceId);
      await _dbRef.child('users').child(user.uid).update({
        'espDevices': devices,
      });
    }
  }

  // Get stream of user's devices
  Stream<DatabaseEvent> getUserDevicesStream() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    
    return _dbRef.child('users').child(user.uid).child('espDevices').onValue;
  }

  // Get stream for a specific device's status
  Stream<DatabaseEvent> getDeviceStatusStream(String deviceId) {
    return _dbRef.child('devices').child(deviceId).onValue;
  }
}
