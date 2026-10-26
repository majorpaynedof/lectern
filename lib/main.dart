import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'api/abs_api.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'state/app_session.dart';
import 'state/data_folder.dart';
import 'state/downloads.dart';
import 'state/media_controls.dart';
import 'state/player_controller.dart';
import 'state/theme_controller.dart';
import 'state/window_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  _registerLicenses();
  await moveOldDataFolder(); // must run before anything reads saved data
  try {
    AbsApi.clientVersion = (await PackageInfo.fromPlatform()).version; // shown in server sessions
  } catch (_) {}
  await WindowState.setUp(); // title, minimum size, remembered position

  final downloads = DownloadManager();
  await downloads.load(); // so offline mode knows what's on disk

  final session = AppSession();
  // Whenever the server is reachable, upload any listening done offline.
  session.onOnline = (api) => downloads.flushPending(api);
  session.restore();

  // While offline, check every two minutes whether the server is back.
  Timer.periodic(const Duration(minutes: 2), (_) {
    if (session.api == null) return;
    if (session.offline) {
      session.retryOnline();
    } else if (downloads.hasPending) {
      downloads.flushPending(session.api!);
    }
  });

  final themes = ThemeController()..load();
  final player = PlayerController(downloads);
  WindowState.beforeClose = player.stop; // closing the window saves your place
  MediaControls(player).start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: themes),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: downloads),
      ],
      child: const LecternApp(),
    ),
  );
}

class LecternApp extends StatelessWidget {
  const LecternApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lectern',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        context.watch<ThemeController>().palette,
        touch: context.watch<ThemeController>().touchMode,
      ),
      // Fade between color themes instead of snapping.
      themeAnimationDuration: const Duration(milliseconds: 350),
      // Let mouse drags scroll horizontal shelves, like touch does.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      home: Consumer<AppSession>(
        builder: (_, session, __) {
          final Widget page;
          if (session.restoring) {
            page = const Scaffold(key: ValueKey('splash'), body: Center(child: AppLogo(size: 64)));
          } else if (session.api == null) {
            page = const LoginScreen(key: ValueKey('login'));
          } else {
            page = const Shell(key: ValueKey('shell'));
          }
          return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: page);
        },
      ),
    );
  }
}

/// Licences for parts that aren't Dart packages (those are added
/// automatically): the audio engine bundled by media_kit.
void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['libmpv (mpv)', 'FFmpeg'], """
Lectern plays audio through libmpv (https://mpv.io) and FFmpeg
(https://ffmpeg.org), shipped as libmpv-2.dll by the media_kit package.

mpv and FFmpeg are licensed under the GNU Lesser General Public License
(LGPL) version 2.1 or later, or the GNU General Public License (GPL)
version 2 or later depending on how they were built. Their source code is
available from https://github.com/mpv-player/mpv and
https://git.ffmpeg.org/ffmpeg.git, and the media_kit builds from
https://github.com/media-kit/libmpv-win32-audio-cmake.""");
  });
}
