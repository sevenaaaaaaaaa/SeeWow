package com.seewow.seewow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioDeviceCallback
import android.os.Handler
import android.os.Looper
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter

class MainActivity : FlutterActivity() {
    companion object { var playbackChannel: MethodChannel? = null }
    private var backgroundEnabled = false
    private lateinit var audioManager: AudioManager
    private var routeToken: String? = null
    private val audioCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(devices: Array<out AudioDeviceInfo>) { routeChanged() }
        override fun onAudioDevicesRemoved(devices: Array<out AudioDeviceInfo>) { routeChanged(force = true) }
    }
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { routeChanged(force = true) }
    }
    private fun audioRoute(): Map<String, String> {
        // API 33+ returns the devices actually selected for media, not every
        // connected headset. Older versions cannot prove a private output.
        val devices = try {
            if (Build.VERSION.SDK_INT >= 33) audioManager.getAudioDevicesForAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
            else emptyList()
        } catch (_: Exception) { emptyList() }
        val privateTypes = setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_HEARING_AID)
        val speakerTypes = setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
        val route = when {
            devices.isNotEmpty() && devices.all { it.type in privateTypes } -> "headphones"
            devices.isNotEmpty() && devices.all { it.type in speakerTypes } -> "speaker"
            else -> "unknown" // A2DP can be either headphones or a public speaker.
        }
        return mapOf("route" to route, "token" to devices.joinToString(",") { "${it.id}:${it.type}" }.ifEmpty { "unknown" })
    }
    private fun routeChanged(force: Boolean = false) {
        val route = audioRoute()
        if (force || route["token"] != routeToken) {
            routeToken = route["token"]
            playbackChannel?.invokeMethod("audio.routeChanged", route)
        }
    }
    private var mediaPermissionResult: MethodChannel.Result? = null
    private val mediaPermissionCode = 7711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seewow/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "media.request" -> {
                        // Scoped storage: the SAF folder picker grants per-tree
                        // access, but enumerating media by path still needs the
                        // media runtime permission on Android 13+.
                        val permissions = if (Build.VERSION.SDK_INT >= 33)
                            arrayOf(Manifest.permission.READ_MEDIA_VIDEO, Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_AUDIO)
                        else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                        if (missing.isEmpty()) result.success(true)
                        else if (mediaPermissionResult != null) result.success(false)
                        else {
                            mediaPermissionResult = result
                            requestPermissions(missing.toTypedArray(), mediaPermissionCode)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seewow/playback")
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.registerAudioDeviceCallback(audioCallback, Handler(Looper.getMainLooper()))
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(noisyReceiver, filter)
        playbackChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "audio.route" -> { val route = audioRoute(); routeToken = route["token"]; result.success(route) }
                "audio.volume" -> result.success(true) // libmpv owns the only audio output, including PiP.
                "background" -> {
                    backgroundEnabled = call.argument<Boolean>("enabled") == true
                    try {
                        if (backgroundEnabled) {
                            val intent = Intent(this, PlaybackService::class.java).putExtra("title", call.argument<String>("title") ?: "SeeWow")
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        } else stopService(Intent(this, PlaybackService::class.java))
                        result.success(true)
                    } catch (e: Exception) { result.error("background", "系统未允许后台媒体服务，请在前台重试", null) }
                }
                "update" -> {
                    PlaybackService.update(call.argument<String>("title") ?: "SeeWow", call.argument<Boolean>("playing") == true,
                        call.argument<Number>("position")?.toLong() ?: 0, call.argument<Number>("duration")?.toLong() ?: 0)
                    result.success(true)
                }
                "pip" -> {
                    if (Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        try { result.success(enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build())) }
                        catch (e: Exception) { result.error("pip", "设备未允许系统画中画，请检查应用权限", null) }
                    } else result.success(false)
                }
                "end" -> { backgroundEnabled = false; stopService(Intent(this, PlaybackService::class.java)); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == mediaPermissionCode) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            mediaPermissionResult?.success(granted)
            mediaPermissionResult = null
        }
    }

    override fun onPictureInPictureModeChanged(active: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(active, newConfig)
        playbackChannel?.invokeMethod("pip.mode", mapOf("active" to active))
    }
    override fun onDestroy() {
        if (::audioManager.isInitialized) audioManager.unregisterAudioDeviceCallback(audioCallback)
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        stopService(Intent(this, PlaybackService::class.java))
        playbackChannel?.setMethodCallHandler(null); playbackChannel = null
        super.onDestroy()
    }
}
