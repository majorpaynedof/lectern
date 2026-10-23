# Lectern

A free, open-source desktop client for [Audiobookshelf](https://www.audiobookshelf.org/), for Windows (and Linux). It aims to be as pleasant to use as the best phone apps, on a big screen.

> Lectern is an unofficial client and isn't affiliated with or endorsed by the Audiobookshelf project.

<!-- Screenshots: add a few to docs/ and link them here, e.g.
![Home](docs/home.png) -->

## Features

- **Home, Library, Series and Authors:** your server's shelves, a searchable cover grid, series in reading order, and author pages with photos and bios.
- **Player:** chapter list, previous and next chapter, 10 s and 30 s skip, speed from 0.75× to 3×, and a sleep timer (minutes or end of chapter). It handles books split across many files.
- **Progress sync:** your position is saved to the server every 15 seconds and whenever you pause, so it stays in step with the phone apps.
- **Offline downloads:** download a book and it plays from your computer. If the server can't be reached, Lectern works offline and uploads the listening you did when the server is back.
- **Listening stats:** today, last 7 and 30 days, all time, books finished, day streak and a 14-day chart.
- **Edit and match:** fix book and author details, or match them against Audible, Google Books and other providers, one at a time or the whole library at once. This needs an account with edit permission.
- **Windows integration:** media keys, the Quick Settings media tile and the lock screen show the book and control playback. The window remembers its size and position.
- **Every audio format, including xHE-AAC:** books that the main player can't decode, such as Audible's newer xHE-AAC files, switch automatically to Windows' own media player (Windows 11 22H2 or later).
- **Themes:** classic light and dark themes, plus bold themes inspired by pro football and hockey team colors.
- **Touch mode:** bigger controls and long-press menus for touchscreen PCs.

## Install

Download `Lectern-Setup-<version>.exe` from the [Releases](../../releases) page and run it. It installs for your Windows user only, with no admin prompt. Newer installers upgrade an existing install and keep your sign-in, settings and downloads.

Windows may warn about an unrecognised app, because releases aren't code-signed yet. Choose **More info → Run anyway**. On PCs with **Smart App Control** turned on, unsigned apps are blocked. Signing releases is planned.

## Build it yourself

You need:

- [Flutter](https://docs.flutter.dev/get-started/install/windows) (stable channel).
- Visual Studio 2022 with the **Desktop development with C++** workload.
- Windows **Developer Mode** turned on (Flutter needs it for plugins).

Then, from the project folder:

```
flutter create --platforms=windows --project-name lectern .
powershell -ExecutionPolicy Bypass -File installer\patch-windows-runner.ps1
flutter run -d windows
```

- `flutter create .` only adds missing platform files. It never overwrites the code in `lib/`.
- The patch script hooks in Lectern's own Windows code: media controls, the Windows audio player, the app ID, the Visual C++ runtime and the app's name. It's safe to run again.

**Installer:** install [Inno Setup](https://jrsoftware.org/isinfo.php) once (`winget install JRSoftware.InnoSetup`), then run:

```
powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1
```

The installer is written to `installer\output\`.

**Linux (for development):**

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
                 libmpv-dev mpv libsecret-1-dev libjsoncpp-dev
flutter create --platforms=linux --project-name lectern .
flutter run -d linux
```

### Troubleshooting

- **"Cannot open source file … cpp_client_wrapper"** after switching between `flutter run` and the installer build: run `flutter clean`, then `flutter pub get`, then build again.
- **"An Application Control policy has blocked this file":** Smart App Control is blocking the unsigned build. Turn it off on your development PC under **Windows Security → App & browser control**.

## Releasing

1. Bump `version:` in `pubspec.yaml`, for example `0.7.0+13`.
2. Commit, then tag and push:

   ```
   git tag v0.7.0
   git push origin main v0.7.0
   ```

GitHub Actions then builds the installer and publishes a Release with it attached.

## Project layout

```
lib/
  main.dart                 app entry, providers, licences
  app_info.dart             project and tip links shown in About
  theme.dart                color themes and component styling
  models.dart               data classes for API responses
  api/abs_api.dart          every Audiobookshelf API call
  state/                    session, player (main + Windows), downloads,
                            media controls, themes, window, data folder
  screens/                  home, library, series, authors, book, player,
                            downloads, stats, appearance, login, dialogs
  widgets/                  covers, cards, mini player, about card
windows/runner/
  media_controls.cpp        Windows media keys and Quick Settings tile
  windows_player.cpp        Windows' own media player (xHE-AAC and others)
installer/                  build script, runner patch, Inno Setup script
```

## Contributing

Bug reports and pull requests are welcome. For anything big, please open an issue first so we can talk about the approach.

## Support

Lectern is free. If it's useful to you, you can leave a tip. The link is under **Appearance → About** in the app.

## License

Lectern is licensed under the [GNU General Public License v3.0](LICENSE). It bundles libmpv and FFmpeg (through media_kit) and other open-source packages. Their licences are listed in the app under **Appearance → About → Open-source licences**.

Team-color themes use original names only and aren't affiliated with or endorsed by any league or team.
