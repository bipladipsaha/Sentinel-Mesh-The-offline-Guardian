package com.example.sentinel_mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import com.google.firebase.auth.FirebaseAuth

class EspWatcherService : Service() {

    companion object {
        const val CHANNEL_ID = "sentinel_watcher_channel"
        const val NOTIF_ID = 1001
        const val TAG = "EspWatcherService"
        const val EXTRA_AUTO_RECORD = "AUTO_RECORD"
    }

    private val deviceListeners = mutableMapOf<String, ValueEventListener>()
    private var userDevicesListener: ValueEventListener? = null
    private var wasActive = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildForegroundNotification())
        startWatchingFirebase()
        Log.d(TAG, "EspWatcherService started")
    }

    private fun startWatchingFirebase() {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        
        val dbRef = FirebaseDatabase.getInstance(
            "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app"
        ).reference

        userDevicesListener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                val devices = mutableListOf<String>()
                for (child in snapshot.children) {
                    child.getValue(String::class.java)?.let { devices.add(it) }
                }
                updateDeviceListeners(devices)
            }
            override fun onCancelled(error: DatabaseError) {}
        }
        
        dbRef.child("users").child(uid).child("espDevices").addValueEventListener(userDevicesListener!!)
    }

    private fun updateDeviceListeners(devices: List<String>) {
        val dbRef = FirebaseDatabase.getInstance(
            "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app"
        ).reference.child("devices")

        val toRemove = deviceListeners.keys - devices.toSet()
        for (deviceId in toRemove) {
            deviceListeners[deviceId]?.let { dbRef.child(deviceId).removeEventListener(it) }
            deviceListeners.remove(deviceId)
        }

        for (deviceId in devices) {
            if (!deviceListeners.containsKey(deviceId)) {
                val listener = object : ValueEventListener {
                    override fun onDataChange(snapshot: DataSnapshot) {
                        val status = snapshot.child("status").getValue(String::class.java) ?: "IDLE"
                        if (status == "ACTIVE" && !wasActive) {
                            wasActive = true
                            launchAppForRecording()
                        } else if (status != "ACTIVE") {
                            wasActive = false
                        }
                    }
                    override fun onCancelled(error: DatabaseError) {}
                }
                dbRef.child(deviceId).addValueEventListener(listener)
                deviceListeners[deviceId] = listener
            }
        }
    }

    private fun launchAppForRecording() {
        Log.d(TAG, "ESP ACTIVE — launching app for auto-record")

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_AUTO_RECORD, true)
        }
        applicationContext.startActivity(launchIntent)
    }

    private fun buildForegroundNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Sentinel Mesh")
            .setContentText("Watching for alerts…")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sentinel Watcher",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent watcher for ESP emergency signals"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Restart if killed by the OS
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        val dbRef = FirebaseDatabase.getInstance(
            "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app"
        ).reference
        
        userDevicesListener?.let {
            FirebaseAuth.getInstance().currentUser?.uid?.let { uid ->
                dbRef.child("users").child(uid).child("espDevices").removeEventListener(it)
            }
        }
        
        for ((deviceId, listener) in deviceListeners) {
            dbRef.child("devices").child(deviceId).removeEventListener(listener)
        }
        deviceListeners.clear()
        
        Log.d(TAG, "EspWatcherService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
