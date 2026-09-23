package dev.backplane.mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

// The phone's alerts. "turns": a turn ended (what to say comes from Bend,
// src/mobile/notify.bend). "live": the ongoing status while agents work.
object Notes {
    const val TURNS = "turns"
    const val LIVE = "live"
    const val EXTRA_THREAD = "dev.backplane.mobile.thread"

    fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(TURNS, "Finished turns", NotificationManager.IMPORTANCE_DEFAULT))
        nm.createNotificationChannel(NotificationChannel(LIVE, "Agents working", NotificationManager.IMPORTANCE_LOW).apply {
            setShowBadge(false)
        })
    }

    fun allowed(ctx: Context) =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    // opens the app, on a thread when one is named
    fun open(ctx: Context, thread: String, code: Int): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (thread.isNotEmpty()) i.putExtra(EXTRA_THREAD, thread)
        return PendingIntent.getActivity(ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    // one notification per thread: a newer turn's alert replaces the last
    private fun id(thread: String) = thread.hashCode().let { if (it == LiveService.ID) it + 1 else it }

    fun turn(ctx: Context, c: Cmd) {
        if (!allowed(ctx)) return
        val n = NotificationCompat.Builder(ctx, TURNS)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle(c.title)
            .setContentText(c.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(c.body))
            .setCategory(if (c.kind == "fail") NotificationCompat.CATEGORY_ERROR else NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(open(ctx, c.thread, id(c.thread)))
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(id(c.thread), n)
        } catch (_: SecurityException) {
        }
    }

    // the thread is open on screen: its alert has been seen
    fun clear(ctx: Context, thread: String) {
        NotificationManagerCompat.from(ctx).cancel(id(thread))
    }
}
