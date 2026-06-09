import 'package:flutter/material.dart';
import '../../services/device_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../theme/app_theme.dart';

class ClaimDeviceScreen extends StatefulWidget {
  const ClaimDeviceScreen({super.key});

  @override
  State<ClaimDeviceScreen> createState() => _ClaimDeviceScreenState();
}

class _ClaimDeviceScreenState extends State<ClaimDeviceScreen> {
  final _deviceIdController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _deviceService = DeviceService();
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _claimDevice() async {
    if (_deviceIdController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a Device ID');
      return;
    }

    String deviceId = _deviceIdController.text.trim();

    String deviceName = _deviceNameController.text.trim();
    if (deviceName.isEmpty) {
      deviceName = 'My Sentinel Mesh';
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _deviceService.claimDevice(deviceId, deviceName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device $deviceId claimed successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Device'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.watch, size: 80, color: AppTheme.primary),
                const SizedBox(height: 24),
                Text(
                  'Link Your Sentinel Mesh',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the unique ID printed on your device or found in the Serial Monitor',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.error.withOpacity(0.5)),
                          ),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: AppTheme.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _deviceIdController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Device ID',
                          hintText: 'e.g. SM-A4CF128B3EF0',
                          prefixIcon: Icon(Icons.qr_code, color: AppTheme.textSecondary),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _deviceNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Device Name (Optional)',
                          hintText: "e.g. Mom's Safety Band",
                          prefixIcon: Icon(Icons.label_outline, color: AppTheme.textSecondary),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 32),
                      GradientButton(
                        text: 'CLAIM DEVICE',
                        onPressed: _claimDevice,
                        isLoading: _isLoading,
                        icon: Icons.link,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
