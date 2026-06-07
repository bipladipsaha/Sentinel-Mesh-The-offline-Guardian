package com.example.sentinel_mesh

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "sentinel_mesh/esp_watcher"
    }

    // Holds the latest intent that may carry AUTO_RECORD flag
    private var latestIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        latestIntent = intent

        // 🔥 Start the background watcher service when the app is opened
        try {
            val serviceIntent = Intent(this, EspWatcherService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        latestIntent = intent
        setIntent(intent)

        // Notify Flutter that a new AUTO_RECORD intent arrived while app was open
        if (intent.getBooleanExtra(EspWatcherService.EXTRA_AUTO_RECORD, false)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("autoRecord", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAutoRecord" -> {
                        val autoRecord = latestIntent
                            ?.getBooleanExtra(EspWatcherService.EXTRA_AUTO_RECORD, false)
                            ?: false
                        result.success(autoRecord)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
