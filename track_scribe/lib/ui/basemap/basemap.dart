import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// The one basemap interface (spec §6): a widget built into the map band,
/// given the route points and the band's bounds. Plan 1 ships the generated
/// [GridBasemap]; the offline-tile implementation is a later stage with its
/// own spike.
abstract class Basemap {
  Widget build(
    BuildContext context, {
    required List<StoredPoint> points,
    required Rect bounds,
  });
}
