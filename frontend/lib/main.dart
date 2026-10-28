import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Lock screen orientation strictly to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 2. Set screen refresh rate to 120Hz / highest supported rate if available on Android
  await _configureRefreshRate();

  runApp(const ProviderScope(child: IpoTrackerApp()));
}

/// Discovers and locks the display mode to 120Hz (or highest available refresh rate)
Future<void> _configureRefreshRate() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final List<DisplayMode> supportedModes = await FlutterDisplayMode.supported;
      final DisplayMode activeMode = await FlutterDisplayMode.active;

      // Look for 120Hz mode matching current resolution
      DisplayMode? target120HzMode;
      for (final DisplayMode mode in supportedModes) {
        if (mode.width == activeMode.width &&
            mode.height == activeMode.height &&
            mode.refreshRate.round() == 120) {
          target120HzMode = mode;
          break;
        }
      }

      if (target120HzMode != null) {
        await FlutterDisplayMode.setPreferredMode(target120HzMode);
      } else {
        await FlutterDisplayMode.setHighRefreshRate();
      }
    } catch (e) {
      debugPrint('High refresh rate setup error: $e');
    }
  }
}

class IpoTrackerApp extends ConsumerWidget {
  const IpoTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Indian IPO Allotment Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
        ),
      ),
      routerConfig: router,
    );
  }
}
