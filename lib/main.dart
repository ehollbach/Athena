import 'dart:async';

import 'package:athena_native/athena_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'autotest.dart';
import 'controller.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_bundledLicenses);
  final controller = AthenaController();
  var args = const <String>[];
  try {
    args = await AthenaNative.launchArguments();
  } on PlatformException {
    // no arguments, then
  }
  runApp(AthenaApp(controller: controller));
  unawaited(args.contains('--autotest') ? runAutotest(controller, args) : controller.start());
}

/// kneejerk and llama.cpp are compiled in; their own MIT notices go on the licenses page.
Stream<LicenseEntry> _bundledLicenses() async* {
  for (final (name, asset) in [
    ('kneejerk', 'third_party/kneejerk/LICENSE'),
    ('llama.cpp', 'third_party/kneejerk/llama.cpp/LICENSE'),
  ]) {
    yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(asset));
  }
}

class AthenaApp extends StatelessWidget {
  const AthenaApp({super.key, required this.controller});

  final AthenaController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Athena',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            controller.phase == Phase.ready ? HomeScreen(controller: controller) : SetupScreen(controller: controller),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5), brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: const TextStyle(fontSize: 16),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
