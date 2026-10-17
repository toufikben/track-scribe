import 'package:xml/xml.dart';

/// Reads a GPX 1.1 document into the points an import would store (§2أ, the
/// reader half of the pair whose writer is `lib/export/gpx_document.dart`).
///
/// Pure: no file, no picker, no plugin, no clock. It reports what the FILE
/// says and nothing else — the totals, the sport choice and the database row
/// are the caller's job, through `TrackImporter`.
///
/// GPX is the one format this app can receive from another app at all, so the
/// stakes of this file differ from the writers': a writer decides what we
/// publish, a reader decides what a user is allowed to believe about a track
/// this phone never recorded. Every gate below exists because a real file in
/// the wild can carry the number it refuses.

/// Refuse to hand a hostile file to the XML parser at all.
///
/// The picker can be pointed at anything the user names `.gpx`, and `package:xml`
/// builds the whole tree in memory on a phone with 4 GB of RAM shared with
/// ColorOS. A multi-megabyte track is already absurd — 28,800 points is an
/// eight-hour recording at one fix a second — so the cap costs nothing real and
/// bounds the worst case.
const kMaxGpxSourceChars = 8 * 1024 * 1024;

/// The file is not a track this app may store. [message] is written to be shown
/// to the user as-is: it names what was wrong, never what was assumed.
class GpxParseException implements Exception {
  const GpxParseException(this.message);
  final String message;

  @override
  String toString() => 'GpxParseException: $message';
}

/// The three sports this app can record, which is also the whole vocabulary a
/// stored `activities.sport` may hold — see [ImportedTrack.sport].
enum ImportSport { walk, run, bike }

/// Prefixes for `<type>`, matched with `startsWith` and never `contains`.
/// `contains` would read "motorcycle" as a cycling ride: the leading word is the
/// one that decides what a token means, so only a prefix may match it. A token
/// that does not open with a known word is refused (`sport == null`), never
/// guessed — see [ImportedTrack.sport].
const _runPrefixes = ['run', 'jog'];
const _bikePrefixes = ['bik', 'cycl', 'ride', 'mtb', 'ebike', 'bmx', 'virtual'];
const _walkPrefixes = ['walk', 'hik'];

ImportSport? _sportOf(String? rawType) {
  final token = rawType?.trim().toLowerCase();
  if (token == null || token.isEmpty) return null;
  if (_runPrefixes.any(token.startsWith)) return ImportSport.run;
  if (_bikePrefixes.any(token.startsWith)) return ImportSport.bike;
  if (_walkPrefixes.any(token.startsWith)) return ImportSport.walk;
  return null;
}

/// One position as the file states it.
class ImportedPoint {
  const ImportedPoint({
    required this.lat,
    required this.lon,
    this.eleM,
    this.wallMillis,
  });

  final double lat, lon;

  /// `<ele>` verbatim. Null when the file has no `<ele>`, when it is not a
  /// number, and when it is `NaN` or `Infinity` — the three cases a broken
  /// export really does contain.
  final double? eleM;

  /// `<time>` as an absolute instant, null when absent, unparseable, or
  /// carrying no zone designator (see [_wallMillisOf]).
  final int? wallMillis;
}

/// What one GPX file claims about one activity.
class ImportedTrack {
  const ImportedTrack({
    required this.points,
    required this.rawType,
    required this.sport,
    required this.startWallMillis,
    required this.rejectedPoints,
    required this.droppedTimes,
  });

  final List<ImportedPoint> points;

  /// The file's `<type>` text exactly as written — including when it means
  /// nothing to us — so a picker can show it while asking.
  final String? rawType;

  /// null means the file never named a sport we recognise. The caller must
  /// then let the user pick one; guessing `walk` would label a 90 km ride as a
  /// stroll, and the list screen cannot tell the two apart afterwards.
  final ImportSport? sport;

  /// The first `<trkpt>` stamp this reader kept, or null when the file stated
  /// no usable instant for any point. This is the row's `start_wall_millis`.
  /// `<metadata><time>` is deliberately not consulted: GPX 1.1 defines it as
  /// when the document was created, which says nothing about when the activity
  /// started — see [parseGpxTrack].
  final int? startWallMillis;

  /// `<trkpt>` elements the file carried and this reader refused: a missing,
  /// non-numeric or out-of-range coordinate. They are counted, not silenced —
  /// an import that quietly drops 40 % of a track would print a distance for a
  /// shorter track than the file describes.
  final int rejectedPoints;

  /// Stamps refused because they were not usable as a clock: no zone
  /// designator, or earlier than the stamp before them.
  final int droppedTimes;
}

/// A zone designator: `Z` or `±HH:MM` at the end of the stamp.
final _zoneDesignator = RegExp(r'(?:Z|[+-]\d{2}:\d{2})$');

/// `xsd:dateTime` → an absolute instant, or null.
///
/// A stamp with no zone designator is dropped, not read as UTC and not read as
/// local. Either choice would be a fabrication: as UTC it silently shifts every
/// European export by an hour or two, as local it makes the SAME file a
/// different track on two phones — and the elapsed recomputed from it would
/// print as a measured duration either way.
int? _wallMillisOf(String? text) {
  final stamp = text?.trim();
  if (stamp == null || stamp.isEmpty) return null;
  if (!_zoneDesignator.hasMatch(stamp)) return null;
  return DateTime.tryParse(stamp)?.millisecondsSinceEpoch;
}

double? _finiteDoubleOf(String? text) {
  final value = double.tryParse(text?.trim() ?? '');
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Parse the one track in [source]. Throws [GpxParseException] for a file that
/// is not XML, is not GPX, holds no `<trk>`, holds more than one, or holds no
/// point this reader was willing to keep.
ImportedTrack parseGpxTrack(String source) {
  if (source.length > kMaxGpxSourceChars) {
    throw const GpxParseException('الملف أكبر مما يقبله الاستيراد');
  }
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source);
  } on Object catch (e) {
    throw GpxParseException('الملف ليس وثيقة XML صحيحة: $e');
  }

  // The root must be `gpx` — by LOCAL name, so `<gpx:gpx xmlns:gpx="…">` passes
  // and anything else does not. Without this gate a valid XML file that merely
  // happens to contain a `<trk>` would be imported as a track.
  if (doc.rootElement.localName != 'gpx') {
    throw const GpxParseException('الملف ليس مستند GPX');
  }

  // Every lookup asks for the LOCAL name with `namespaceUri: '*'`. With no
  // namespace argument `package:xml` compares the FULLY QUALIFIED name, so a
  // file whose tags are prefixed (`<gpx:trkpt xmlns:gpx="…">`, which exists in
  // exports from other vendors) would read as an empty document — the worst
  // possible failure, because it looks like a valid file with nothing in it.
  final tracks = doc.rootElement
      .findElements('trk', namespaceUri: '*')
      .toList();
  if (tracks.isEmpty) {
    // A route (`<rte>`) is a plan nobody walked, and a bare `<wpt>` is a
    // marker. Neither has times, so importing one would store a distance for a
    // trip that never happened.
    throw const GpxParseException('الملف لا يحتوي مسارًا مسجَّلًا (<trk>)');
  }
  if (tracks.length > 1) {
    throw const GpxParseException(
      'الملف يحتوي أكثر من مسار؛ كل ملف يُستورد كنشاط واحد',
    );
  }
  final track = tracks.single;
  final points = track.findAllElements('trkpt', namespaceUri: '*').toList();
  if (points.isEmpty) {
    throw const GpxParseException('المسار لا يحتوي أي نقطة');
  }

  final kept = <ImportedPoint>[];
  var rejected = 0;
  var droppedTimes = 0;
  // The monotonic gate runs over the FILE, in file order: an elapsed computed
  // later subtracts the first kept stamp from the last, and a single reversed
  // stamp in a badly exported file would otherwise make that negative.
  int? lastKept;
  for (final pt in points) {
    final lat = _finiteDoubleOf(pt.getAttribute('lat'));
    final lon = _finiteDoubleOf(pt.getAttribute('lon'));
    if (lat == null ||
        lon == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      rejected++;
      continue;
    }
    final ele = _finiteDoubleOf(
      pt.getElement('ele', namespaceUri: '*')?.innerText,
    );
    final stamp = pt.getElement('time', namespaceUri: '*')?.innerText.trim();
    var wall = _wallMillisOf(stamp);
    if (wall == null) {
      // The file wrote a `<time>` and this reader could not use it: that is a
      // dropped clock, and the caller needs the count to know the elapsed it
      // may compute covers only part of the track.
      if (stamp != null && stamp.isNotEmpty) droppedTimes++;
    } else if (lastKept != null && wall <= lastKept) {
      droppedTimes++;
      wall = null;
    }
    if (wall != null) lastKept = wall;
    kept.add(ImportedPoint(lat: lat, lon: lon, eleM: ele, wallMillis: wall));
  }
  if (kept.isEmpty) {
    throw const GpxParseException('ولا إحداثيات الملف صالحة');
  }

  final rawType = track.getElement('type', namespaceUri: '*')?.innerText.trim();
  // The start is the first POINT stamp the file gave us — never
  // `<metadata><time>`, which GPX 1.1 defines as the moment the DOCUMENT was
  // created. A 2023 ride exported in 2026 would otherwise enter the history
  // list dated 2026, and that list sorts by this column. Null is the honest
  // answer for a file whose stamps were all zone-less or all unusable.
  int? start;
  for (final p in kept) {
    if (p.wallMillis != null) {
      start = p.wallMillis;
      break;
    }
  }

  return ImportedTrack(
    points: kept,
    rawType: (rawType == null || rawType.isEmpty) ? null : rawType,
    sport: _sportOf(rawType),
    startWallMillis: start,
    rejectedPoints: rejected,
    droppedTimes: droppedTimes,
  );
}
