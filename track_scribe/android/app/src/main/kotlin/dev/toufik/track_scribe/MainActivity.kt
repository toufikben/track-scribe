package dev.toufik.track_scribe

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * The platform calls the app owns: the notification-permission channel, the
 * share sheet, and the file picker. `geolocator` builds the recording
 * notification but never asks Android for permission to show it, and since
 * Android 13 that grant is runtime: without it the notification is enqueued and
 * silently dropped. 1 = granted, 0 = not.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    /** The one `open` reply waiting on a picker. A second press replaces it. */
    private var importPending: MethodChannel.Result? = null

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IMPORT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> openDocument(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The document picker, hand-written rather than pulled in as `file_picker`:
     * no new Flutter dependency, no network, and one intent small enough to
     * read.
     *
     * `ACTION_OPEN_DOCUMENT`, not `ACTION_GET_CONTENT`: the former is Storage
     * Access Framework's own contract and every document provider on the device
     * answers it, while the latter is a legacy content picker whose providers
     * may hand back a URI this app cannot re-open.
     *
     * The MIME filter is `*/*` deliberately. GPX crossed between apps with no
     * registered type — `application/octet-stream`, `text/xml`, or nothing at
     * all, depending on the file manager — and a filter that excludes those
     * shows a picker in which the user's own file is greyed out with no
     * explanation. Refusing a non-GPX file is the reader's job, in Arabic, with
     * a reason («الملف ليس مستند GPX»). This channel's job is only to hand over
     * what was picked.
     */
    private fun openDocument(result: MethodChannel.Result) {
        // A second request must not orphan the first reply: the awaiting Dart
        // future would never complete.
        importPending?.success(null)
        importPending = result
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        try {
            startActivityForResult(pick, IMPORT_CODE)
        } catch (e: ActivityNotFoundException) {
            // No document provider at all: a real failure the UI can say so,
            // distinct from a user who backed out of a picker.
            importPending = null
            result.error("no_picker", e.message, null)
        }
    }

    /**
     * Reads the picked document, but no further than the cap.
     *
     * `IMPORT_MAX_BYTES` is `kMaxGpxSourceChars + 1` in bytes: the reader's
     * ceiling counts UTF-16 characters, and a byte count is all a stream
     * exposes, so the platform guard is a memory limit and the parse-time check
     * stays the ruling. Reading one byte past it matters — a file trimmed to
     * exactly the cap would parse as a shorter route than the one the user
     * picked, silently. Over the cap the extra bytes are dropped and the Dart
     * reader refuses on length.
     */
    private fun readBounded(uri: Uri): String? {
        // A provider that returns no stream is a failed read, not a cancelled
        // one — the caller turns null into `read_failed` for exactly that
        // reason.
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { stream ->
            val out = ByteArrayOutputStream()
            // No readNBytes: it is API 34 for InputStream on Android, and the
            // app's floor is minSdk 21.
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
                if (out.size() > IMPORT_MAX_BYTES) break
            }
            return String(out.toByteArray(), Charsets.UTF_8)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != IMPORT_CODE) return
        val reply = importPending
        importPending = null
        // A result with no waiting call means the engine detached (or the
        // activity was recreated) while the picker was up. Nothing to answer.
        if (reply == null) return
        if (resultCode != RESULT_OK) {
            reply.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            reply.success(null)
            return
        }
        try {
            val text = readBounded(uri)
            if (text == null) {
                reply.error("read_failed", "the provider refused to open the document", null)
            } else {
                reply.success(text)
            }
        } catch (e: IOException) {
            // A dead provider is reported as a failed read, never as a
            // cancellation: the user did pick a file, and silence would look
            // like nothing happened.
            reply.error("read_failed", e.message, null)
        } catch (e: SecurityException) {
            // A revoked or non-openable URI. Same answer as a dead provider,
            // and the same reason for not letting it reach the thread uncaught.
            reply.error("read_failed", e.message, null)
        }
    }

    override fun onDestroy() {
        pending?.success(0)
        pending = null
        // The awaiting Dart future must not outlive the activity that owns the
        // answer. null reads as a cancellation, which is the closest honest
        // fact when the screen carrying the picker dies.
        importPending?.success(null)
        importPending = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "dev.toufik.track_scribe/notifications"
        private const val SHARE_CHANNEL = "dev.toufik.track_scribe/sharing"
        private const val IMPORT_CHANNEL = "dev.toufik.track_scribe/importing"
        private const val REQUEST_CODE = 4711
        private const val IMPORT_CODE = 4712
        private const val BUILD_CODES = 33

        /** `kMaxGpxSourceChars + 1`, counted in bytes. See [readBounded]. */
        private const val IMPORT_MAX_BYTES = 8 * 1024 * 1024 + 1
    }
}
