package com.example.quick_notification

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AppNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val content = if (!bigText.isNullOrBlank()) bigText else text

        val timeStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(sbn.postTime))

        val payload = mapOf<String, Any?>(
            "id" to (sbn.key ?: "${sbn.packageName}-${sbn.postTime}"),
            "app" to (sbn.packageName ?: "未知应用"),
            "title" to title.ifBlank { "新通知" },
            "content" to content,
            "time" to timeStr,
            "unread" to true,
        )
        NotificationListenerBridge.emit(payload)
    }
}
