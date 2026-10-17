import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/export/export_format.dart';
import 'package:track_scribe/export/gpx_document.dart';
import 'package:track_scribe/export/tcx_document.dart';

/// The one platform call §2أ owns for sharing, beside the notification channel
/// already in `MainActivity.kt`.
///
/// Written by hand instead of taking `share_plus`: the owner's rule is that
/// everything stays local and no external service is involved, and a share
/// sheet is an `ACTION_SEND` intent on the same device — one intent, one
/// FileProvider, and no third-party code between the user's track and the app
/// they choose. A ruling, not a fact: `share_plus` would have been less code,
/// and it is still the cheaper option if the Kotlin below ever becomes a
/// maintenance problem.
const kShareChannel = MethodChannel('dev.toufik.track_scribe/sharing');

/// Files land here, under the app support directory.
///
/// The directory is chosen by the Android side, not by taste: a share sheet can
/// only hand over a file a `FileProvider` can produce a `content://` URI for,
/// and androidx `FileProvider` refuses a declared path that resolves outside
/// its own root (`setPath` → "resolves outside the root"). `<files-path>` is
/// `Context.getFilesDir()`, which is exactly what
/// `getApplicationSupportDirectory()` returns on Android
/// (path_provider_android 2.3.1, `path_provider_android_real.dart:29`).
/// `getApplicationDocumentsDirectory()` would have been the natural-looking
/// choice, and would have failed on the device: it is `getDir("flutter")`,
/// i.e. `<data>/app_flutter`, which no `FileProvider` path element reaches
/// (same file, line 38).
const kExportDirName = 'exports';

/// A file name that survives crossing into another app's file system: ASCII,
/// no spaces, and the activity's own start instant, so three artifacts — the
/// name, the document's `<time>`/`<Id>`, and the database row — all state the
/// same moment. The stamp is UTC for that reason and because the test can pin
/// it as a literal instead of recomputing it under whatever zone the runner is in.
String exportFileName(ActivitySummary summary, ExportFormat format) =>
    'track-scribe-${_utcStamp(summary.startWallMillis)}-${summary.sport}.'
    '${format.extensionName}';

String _utcStamp(int millisSinceEpoch) {
  final t = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}'
      'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}

/// Writes a stored activity out as a file and hands it to Android.
///
/// Everything the writers already refused to invent stays refused here: this
/// class only serialises what `buildGpxDocument`/`buildTcxDocument` returned,
/// so an exported file cannot carry an elevation, a rejected fix, or a time
/// that the §2أ gates did not already approve.
class TrackExporter {
  TrackExporter({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDirectory;

  /// Writes [summary] out in [format] and returns the file.
  ///
  /// One file per (activity, format): re-exporting replaces rather than piles
  /// up, so a user who shares the same ride five times does not accumulate
  /// five copies in app storage. The write is not atomic — a crash mid-write
  /// can leave a truncated file, and the next export of the same activity
  /// overwrites it.
  Future<File> export(ActivitySummary summary, ExportFormat format) async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, kExportDirName));
    await dir.create(recursive: true);
    final document = switch (format) {
      ExportFormat.gpx => buildGpxDocument,
      ExportFormat.tcx => buildTcxDocument,
    };
    final file = File(p.join(dir.path, exportFileName(summary, format)));
    await file.writeAsString(document(summary));
    return file;
  }

  /// [export], then the share sheet.
  ///
  /// The platform exceptions are deliberately not caught: a file that Android
  /// could not turn into a `content://` URI, or a device with no app that
  /// accepts a `.gpx`, must reach the screen so it can say so — the alternative
  /// is a button that appears to do nothing.
  Future<File> exportAndShare(ActivitySummary summary, ExportFormat format) async {
    final file = await export(summary, format);
    await kShareChannel.invokeMethod<void>('share', {
      'path': file.path,
      'mimeType': format.mimeType,
    });
    return file;
  }
}

/// Production resolves the real support directory; a test overrides this with a
/// temp one, which is how the written bytes become evidence rather than a claim.
final trackExporterProvider = Provider<TrackExporter>(
  (ref) => TrackExporter(),
);
