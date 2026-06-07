import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class StreamingService {
  // Provided Agora App ID
  static const String appId = 'a8658402f7444025bc83452677174ef5';
  
  static Future<RtcEngine?> initializeAgora() async {
    if (appId == 'YOUR_AGORA_APP_ID') {
      debugPrint("⚠️ Agora App ID is missing. Streaming will not work.");
      return null;
    }

    await [Permission.microphone, Permission.camera].request();
    
    RtcEngine engine = createAgoraRtcEngine();
    await engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.enableVideo();
    await engine.enableAudio();
    await engine.startPreview();
    await engine.switchCamera(); // Switch to rear camera
    
    return engine;
  }
}
