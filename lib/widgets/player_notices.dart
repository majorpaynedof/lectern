import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import '../theme.dart';
import '../util.dart';

/// The player's messages: "you listened further on another device",
/// "progress isn't saving" and playback problems. Shown in the main window
/// and on the full-screen player, so they're never hidden behind it.
class PlayerNotices extends StatelessWidget {
  const PlayerNotices({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final pal = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (player.remoteNewer case final r?)
          MaterialBanner(
            backgroundColor: pal.accentSoft,
            leading: Icon(Icons.devices_rounded, color: pal.accent),
            content: Text(
              'You listened further on another device: '
              '${[if (player.chapterAt(r.currentTime) case final c?) c.title, formatDuration(r.currentTime)].join(', ')}. '
              'Lectern is at ${formatDuration(player.position.value)}.',
            ),
            actions: [
              TextButton(
                onPressed: () => player.resolveRemoteNewer(jump: false),
                child: const Text('Stay here'),
              ),
              FilledButton(
                onPressed: () => player.resolveRemoteNewer(jump: true),
                child: Text('Jump to ${formatDuration(r.currentTime)}'),
              ),
            ],
          ),
        if (player.offlineSpot case final spot?)
          MaterialBanner(
            backgroundColor: pal.accentSoft,
            leading: Icon(Icons.history_rounded, color: pal.accent),
            content: Text(
              'While offline, you got further on this PC: '
              '${[if (player.chapterAt(spot) case final c?) c.title, formatDuration(spot)].join(', ')}. '
              'Another device saved ${formatDuration(player.position.value)} since.',
            ),
            actions: [
              TextButton(
                onPressed: () => player.resolveOfflineSpot(go: false),
                child: const Text('Stay here'),
              ),
              FilledButton(
                onPressed: () => player.resolveOfflineSpot(go: true),
                child: Text('Go to ${formatDuration(spot)}'),
              ),
            ],
          ),
        if (player.syncProblem case final problem?)
          MaterialBanner(
            backgroundColor: pal.surfaceHigh,
            leading: Icon(Icons.cloud_off_rounded, color: pal.danger),
            content: Text(problem),
            actions: [
              TextButton(
                onPressed: player.dismissSyncProblem,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        if (player.lastError case final error?)
          MaterialBanner(
            backgroundColor: pal.surfaceHigh,
            content: SelectableText('Playback problem: $error'),
            actions: [
              TextButton(
                onPressed: player.dismissError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
      ],
    );
  }
}
