import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../auth/login_screen.dart';
import '../esp/claim_device_screen.dart';
import '../esp/device_settings_screen.dart';
import '../sender/sender_screen.dart';
import '../responder/responder_screen.dart';
import '../tracker/live_tracker_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool autoRecord;
  const HomeScreen({super.key, this.autoRecord = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _deviceService = DeviceService();
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
    
    // If launched by native ESP signal, auto route to sender screen
    if (widget.autoRecord) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // We assume the user's first device is the one that triggered it
        // Or we pass the device ID through the native intent. For now, default to first device.
        final uid = _authService.currentUser?.uid;
        if (uid != null) {
          final user = await _authService.getUserDetails(uid);
          if (user != null && user.espDevices.isNotEmpty && mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SenderScreen(autoRecord: true, deviceId: user.espDevices.first)));
          }
        }
      });
    }
  }

  Future<void> _loadUser() async {
    final uid = _authService.currentUser?.uid;
    if (uid != null) {
      final user = await _authService.getUserDetails(uid);
      if (mounted) setState(() => _user = user);
    }
  }

  void _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.background, AppTheme.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildQuickActions(),
                      const SizedBox(height: 32),
                      _buildMyDevices(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${_user?.name.split(' ').first ?? 'User'} 👋',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready to monitor your safety',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textSecondary),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.2,
          children: [
            _buildActionCard(
              title: 'SOS Mode',
              icon: Icons.shield,
              color: AppTheme.error,
              onTap: () {
                if (_user != null && _user!.espDevices.isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SenderScreen(deviceId: _user!.espDevices.first)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please claim a device first')));
                }
              },
            ),
            _buildActionCard(
              title: 'My Responder',
              icon: Icons.radar,
              color: AppTheme.success,
              onTap: () {
                 if (_user != null && _user!.espDevices.isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ResponderScreen(deviceIds: _user!.espDevices)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please claim a device first')));
                }
              },
            ),
            _buildActionCard(
              title: 'Live Tracker',
              icon: Icons.map,
              color: AppTheme.secondary,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTrackerScreen()));
              },
            ),
            _buildActionCard(
              title: 'Add Device',
              icon: Icons.add_circle_outline,
              color: AppTheme.textSecondary,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ClaimDeviceScreen())).then((_) => _loadUser());
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: 16,
        border: Border.all(color: color.withOpacity(0.3)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDevices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('My Devices', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
            TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ClaimDeviceScreen())).then((_) => _loadUser());
              },
              child: const Text('ADD NEW', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<DatabaseEvent>(
          stream: _deviceService.getUserDevicesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
              return _buildEmptyDevices();
            }

            List<String> devices = List<String>.from(snapshot.data!.snapshot.value as List);
            if (devices.isEmpty) return _buildEmptyDevices();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (context, index) {
                return _buildDeviceItem(devices[index]);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyDevices() {
    return GlassCard(
      child: Column(
        children: [
          const Icon(Icons.watch_off_outlined, size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text('No devices claimed yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Tap "Add Device" to link your Sentinel Mesh', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(String deviceId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: StreamBuilder<DatabaseEvent>(
        stream: _deviceService.getDeviceStatusStream(deviceId),
        builder: (context, snapshot) {
          String status = 'OFFLINE';
          String deviceName = deviceId;
          
          if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
            final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
            status = data['status'] ?? 'IDLE';
            deviceName = data['deviceName'] ?? deviceId;
          }

          bool isActive = status == 'ACTIVE';

          return GlassCard(
            padding: 16,
            border: Border.all(color: isActive ? AppTheme.error : AppTheme.textSecondary.withOpacity(0.3)),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.error.withOpacity(0.2) : AppTheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.developer_board, color: isActive ? AppTheme.error : AppTheme.primary),
              ),
              title: Text(deviceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(
                isActive ? 'EMERGENCY DETECTED' : 'System Ready',
                style: TextStyle(color: isActive ? AppTheme.error : AppTheme.success, fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceSettingsScreen(deviceId: deviceId))).then((_) => _loadUser());
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
