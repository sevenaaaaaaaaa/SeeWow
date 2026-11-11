package com.seewow.seewow

import android.app.*
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

/** Keeps active, user-enabled playback foregrounded; the Flutter player owns audio. */
class PlaybackService : Service() {
    companion object {
        private var active: PlaybackService? = null
        fun update(title: String, playing: Boolean, position: Long, duration: Long) { active?.refresh(title, playing, position, duration) }
    }
    private lateinit var session: MediaSession
    private var title = "SeeWow"
    private var playing = false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate(); active = this
        if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel("seewow_playback", "影片后台播放", NotificationManager.IMPORTANCE_LOW))
        session = MediaSession(this, "SeeWow")
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = action("play")
            override fun onPause() = action("pause")
            override fun onStop() = action("stop")
            override fun onSeekTo(pos: Long) { MainActivity.playbackChannel?.invokeMethod("action", mapOf("action" to "seek", "position" to pos)) }
        })
        session.isActive = true
    }
    private fun action(value: String) { MainActivity.playbackChannel?.invokeMethod("action", mapOf("action" to value)) }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "toggle" -> action("toggle")
            "stop" -> { action("stop"); stopSelf(); return START_NOT_STICKY }
        }
        title = intent?.getStringExtra("title") ?: title
        startForeground(2001, notification())
        return START_NOT_STICKY
    }
    private fun button(action: String): PendingIntent = PendingIntent.getService(this, if (action == "stop") 2 else 1,
        Intent(this, PlaybackService::class.java).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun notification(): Notification {
        val launch = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "seewow_playback") else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_media_play).setContentTitle(title).setContentText(if (playing) "正在播放 · SeeWow" else "已暂停 · SeeWow")
            .setContentIntent(launch).setOnlyAlertOnce(true).setOngoing(playing)
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1))
            .addAction(Notification.Action.Builder(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, if (playing) "暂停" else "播放", button("toggle")).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "停止", button("stop")).build()).build()
    }
    private fun refresh(title: String, playing: Boolean, position: Long, duration: Long) {
        this.title = title; this.playing = playing
        session.setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, title).putLong(MediaMetadata.METADATA_KEY_DURATION, duration).build())
        session.setPlaybackState(PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO)
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, position, if (playing) 1f else 0f).build())
        getSystemService(NotificationManager::class.java).notify(2001, notification())
    }
    override fun onDestroy() { active = null; session.release(); stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy() }
}
