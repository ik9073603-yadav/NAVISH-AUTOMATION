package com.navish.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

// Creates the high-importance notification channel BEFORE any FCM message
// can arrive. This must run at process start (not first-notification-time):
// Android silently drops a notification whose channelId doesn't exist on
// the device yet, and Application.onCreate() runs whenever the OS starts
// this process — including a cold start triggered purely to deliver a
// background push — so the channel is guaranteed to exist in time.
//
// Channel id here MUST match ANDROID_CHANNEL_ID in backend/src/lib/fcm.ts
// and the default_notification_channel_id meta-data in AndroidManifest.xml.
class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "high_importance_channel",
                "Navish Alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Task assignments, order stages, checklist and inventory alerts"
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}
