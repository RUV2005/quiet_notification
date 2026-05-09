package com.example.quick_notification

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel

object NotificationListenerBridge {
    const val METHOD_CHANNEL = "com.example.quick_notification/notification_listener"
    const val EVENT_CHANNEL = "com.example.quick_notification/notification_listener_events"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    val streamHandler: EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(HashMap(payload))
        }
    }

    fun isListenerEnabled(context: Context): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.contains(context.packageName)
    }

    fun openListenerSettings(activity: Activity) {
        activity.startActivity(
            android.content.Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
        )
    }
}
