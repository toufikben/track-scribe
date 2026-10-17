package dev.toufik.track_scribe

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The platform calls the app owns: the notification-permission channel, and the
 * share sheet. `geolocator` builds the recording notification but never asks
 * Android for permission to show it, and since Android 13 that grant is
 * runtime: without it the notification is enqueued and silently dropped.
 * 1 = granted, 0 = not.
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> share(call, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The share sheet, hand-written rather than pulled in as `share_plus`: no
     * new Flutter dependency, no network, and an intent small enough to read.
     *
     * The URI must be a `content://` one. Android has rejected a `file://`
     * EXTRA_STREAM with `FileUriExposedException` since API 24, and the
     * temporary read grant is what lets the receiving app open a file in our
     * private storage without the user handing it storage permission.
     */
    private fun share(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mimeType")
        if (path == null || mimeType == null) {
            result.error("bad_args", "path and mimeType are required", null)
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.error("no_file", "the export never reached the disk", null)
            return
        }
        val uri: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: IllegalArgumentException) {
            // The path resolved outside the roots declared in file_paths.xml —
            // a moved directory or a Dart-side bug, either way a real failure.
            result.error("outside_root", e.message, null)
            return
        }
        val send = Intent(Intent.ACTION_SEND)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // A chooser is always startable, and a null title makes Android write
        // its own localized heading: when nothing accepts the MIME type the
        // sheet opens and says so in the system's words. That empty case is
        // Android's to phrase — the three errors above are the failures this
        // channel can actually report.
        startActivity(Intent.createChooser(send, null))
        result.success(null)
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
        private const val SHARE_CHANNEL = "dev.toufik.track_scribe/sharing"
        private const val REQUEST_CODE = 4711
        private const val BUILD_CODES = 33
    }
}
