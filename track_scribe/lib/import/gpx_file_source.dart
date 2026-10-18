import 'package:flutter/services.dart';

/// The one platform call §2أ owns for reading a file, beside the share and
/// notification channels already in `MainActivity.kt`.
///
/// Hand-written rather than `file_picker` / `flutter_file_selector`: the owner's
/// rule is that everything stays local with no external service, and picking a
/// file is one `ACTION_OPEN_DOCUMENT` intent on the same device. A dependency
/// would also decide what a cancellation means, and this project needs to say
/// it precisely (see [GpxFileSource.readDocument]).
const kImportChannel = MethodChannel('dev.toufik.track_scribe/importing');

/// Where a GPX document to import comes from.
///
/// An interface rather than a channel call in the widget because `dart:io` and
/// a real picker both never complete inside `testWidgets` on this host (measured
/// in §2أ-2: the directory is created, the file is not, the test hangs). The
/// screen below depends on this type alone, so the whole import flow — sport
/// chooser, date entry, the wording of a refusal — is testable without a
/// platform.
abstract interface class GpxFileSource {
  /// The user's chosen document, or null when they backed out of the picker.
  ///
  /// `null` and `''` are different answers and must stay different: an empty
  /// document is a file the reader refuses («الملف ليس مستند GPX»), a
  /// cancellation is a user who changed their mind and is owed no error at all.
  /// A platform-side failure throws [PlatformException] rather than answering
  /// null, so a broken read cannot masquerade as a cancellation.
  Future<String?> readDocument();
}

/// The picker itself: the platform returns the file's text, already read.
///
/// The bytes cross as a String rather than as a URI handed to Dart because the
/// app has no storage permission to follow one, and because the reader's cap is
/// stated in characters — the platform reads at most
/// `kMaxGpxSourceChars + 1` bytes, so a huge file arrives over the cap and the
/// reader refuses it with its own words. Neither side truncates: a clipped file
/// would import as a shorter route than the one the user picked.
class SafGpxFileSource implements GpxFileSource {
  const SafGpxFileSource();

  @override
  Future<String?> readDocument() => kImportChannel.invokeMethod<String>('open');
}
