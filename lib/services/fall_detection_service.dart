import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Callback when a fall is detected.
typedef FallDetectedCallback = void Function();

/// Offline Fall Detection Service using Google ML Kit Pose Detection.
///
/// How it works:
/// 1. Receives camera image frames via [processCameraImage].
/// 2. Runs ML Kit Pose Detection to extract body landmarks.
/// 3. Tracks the average torso Y-position (shoulders + hips) over time.
/// 4. A "fall" is detected when:
///    a. The torso drops rapidly (large Y-delta in a short time window), AND
///    b. The body becomes roughly horizontal (shoulders and hips at similar Y).
/// 5. After firing, it enters a cooldown period to avoid spamming.
class FallDetectionService {
  final PoseDetector _poseDetector;
  final FallDetectedCallback onFallDetected;

  bool _isProcessing = false;
  bool _isDisposed = false;

  // Tracking state
  double? _prevTorsoY;
  DateTime? _prevTimestamp;

  // Tuning constants
  static const double _fallVelocityThreshold = 350.0; // pixels/sec downward movement
  static const double _horizontalBodyThreshold = 60.0; // max Y-diff between shoulders & hips for "horizontal"
  static const Duration _cooldown = Duration(seconds: 10);
  DateTime? _lastFallTime;

  FallDetectionService({required this.onFallDetected})
      : _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base, // lighter model - good for real-time
          ),
        );

  /// Process a single camera frame for fall detection.
  /// Call this from [CameraController.startImageStream].
  Future<void> processCameraImage(CameraImage image, CameraDescription camera) async {
    if (_isProcessing || _isDisposed) return;

    // Cooldown after a detected fall
    if (_lastFallTime != null && DateTime.now().difference(_lastFallTime!) < _cooldown) {
      return;
    }

    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty) {
        _analyzePose(poses.first);
      }
    } catch (e) {
      debugPrint("Fall Detection Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  /// Analyze a single detected pose for fall indicators.
  void _analyzePose(Pose pose) {
    // Get key torso landmarks
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    // Need all four landmarks with reasonable confidence
    if (leftShoulder == null || rightShoulder == null ||
        leftHip == null || rightHip == null) return;
    if (leftShoulder.likelihood < 0.5 || rightShoulder.likelihood < 0.5 ||
        leftHip.likelihood < 0.5 || rightHip.likelihood < 0.5) return;

    final avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2.0;
    final avgHipY = (leftHip.y + rightHip.y) / 2.0;
    final currentTorsoY = (avgShoulderY + avgHipY) / 2.0;
    final now = DateTime.now();

    // Check 1: Rapid downward velocity
    if (_prevTorsoY != null && _prevTimestamp != null) {
      final dt = now.difference(_prevTimestamp!).inMilliseconds / 1000.0;
      if (dt > 0) {
        // In image coordinates, Y increases downward, so a fall means torsoY increases rapidly
        final velocity = (currentTorsoY - _prevTorsoY!) / dt;

        // Check 2: Body is roughly horizontal (shoulders and hips at similar Y)
        final shoulderHipYDiff = (avgShoulderY - avgHipY).abs();
        final isHorizontal = shoulderHipYDiff < _horizontalBodyThreshold;

        if (velocity > _fallVelocityThreshold && isHorizontal) {
          debugPrint("🚨 FALL DETECTED! velocity=$velocity, shoulderHipDiff=$shoulderHipYDiff");
          _lastFallTime = DateTime.now();
          _prevTorsoY = null;
          _prevTimestamp = null;
          onFallDetected();
          return;
        }
      }
    }

    _prevTorsoY = currentTorsoY;
    _prevTimestamp = now;
  }

  /// Convert [CameraImage] to ML Kit [InputImage].
  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    // Only supported on Android (NV21) and iOS (bgra8888) natively
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotationFromCamera(camera),
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Map camera sensor orientation to ML Kit rotation.
  InputImageRotation _rotationFromCamera(CameraDescription camera) {
    if (Platform.isAndroid) {
      switch (camera.sensorOrientation) {
        case 0:   return InputImageRotation.rotation0deg;
        case 90:  return InputImageRotation.rotation90deg;
        case 180: return InputImageRotation.rotation180deg;
        case 270: return InputImageRotation.rotation270deg;
        default:  return InputImageRotation.rotation0deg;
      }
    }
    // iOS defaults to 0
    return InputImageRotation.rotation0deg;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _isDisposed = true;
    await _poseDetector.close();
  }
}
