/// The formats §2أ can write out, and what a receiving app is told about each.
///
/// The MIME types are the ones registrants actually look for: `application/gpx+xml`
/// is what the GPX 1.1 schema's own examples use, and
/// `application/vnd.garmin.tcx+xml` is Garmin's registered type for TCX 2.0.
/// A share sheet routes on this string, so getting it wrong does not fail here —
/// it silently offers the user apps that then refuse the file.
enum ExportFormat {
  gpx(extensionName: 'gpx', mimeType: 'application/gpx+xml'),
  tcx(extensionName: 'tcx', mimeType: 'application/vnd.garmin.tcx+xml');

  const ExportFormat({required this.extensionName, required this.mimeType});

  /// Lower-case, dot-less, because it becomes part of a file name that crosses
  /// into other apps' file systems.
  final String extensionName;
  final String mimeType;
}
