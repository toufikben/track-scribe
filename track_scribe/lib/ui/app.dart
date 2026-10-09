import 'package:flutter/material.dart';

class TrackScribeApp extends StatelessWidget {
  const TrackScribeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Track Scribe',
        home: Scaffold(
          body: Center(child: Text('تسجيل', style: Theme.of(context).textTheme.headlineMedium)),
        ),
      );
}
