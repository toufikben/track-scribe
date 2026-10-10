import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Locale-derived display tokens (ruling R37): the decimal separator used by
/// [Format] is always consumed as a token from this provider, never
/// hard-coded. Task 10 replaces the constant with the real locale layer.
final localeSepProvider = Provider<String>((_) => ',');
