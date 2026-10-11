package dev.toufik.track_scribe

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one platform call the app owns. `geolocator` builds the recording
 * notification but never asks Android for permission to show it, and since
 * Android 13 that grant is runtime: without it the notification is enqueued
 * and silently dropped. 1 = granted, 0 = not.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> result.success(if (granted()) 1 else 0)
                "request" -> request(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun granted(): Boolean =
        Build.VERSION.SDK_INT < BUILD_CODES ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        if (granted()) {
            result.success(1)
            return
        }
        // A second request while one is open must not orphan the first reply:
        // the awaiting Dart future would never complete.
        pending?.success(0)
        pending = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val answer = if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) 1 else 0
        pending?.success(answer)
        pending = null
    }

    override fun onDestroy() {
        pending?.success(0)
        pending = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "dev.toufik.track_scribe/notifications"
        private const val REQUEST_CODE = 4711
        private const val BUILD_CODES = 33
    }
}
