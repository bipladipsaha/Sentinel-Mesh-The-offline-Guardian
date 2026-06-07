import 'package:flutter/material.dart';
import '../../services/device_service.dart';
import '../../widgets/glass_card.dart';
import '../../theme/app_theme.dart';

class DeviceSettingsScreen extends StatefulWidget {
  final String deviceId;
  
  const DeviceSettingsScreen({super.key, required this.deviceId});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final _deviceService = DeviceService();

  void _confirmRemoveDevice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Remove Device', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove ${widget.deviceId} from your account? You will no longer receive alerts from it.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deviceService.removeDevice(widget.deviceId);
              if (!mounted) return;
              Navigator.pop(context); // Go back to Home
            },
            child: const Text('REMOVE', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Settings'),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Column(
                  children: [
                    const Icon(Icons.developer_board, size: 64, color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      widget.deviceId,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.success.withOpacity(0.5)),
                      ),
                      child: const Text(
                        'LINKED TO ACCOUNT',
                        style: TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Danger Zone',
                style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: 16,
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline, color: AppTheme.error),
                  ),
                  title: const Text('Remove Device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Unlink from your account', style: TextStyle(color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
                  onTap: _confirmRemoveDevice,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
