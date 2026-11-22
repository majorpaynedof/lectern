import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../sync/abs_progress.dart';
import '../util.dart';
import 'app_session.dart';
import 'downloads.dart';
import 'player_controller.dart';

/// What you can do with your progress on a book.
enum ProgressAction {
  /// Mark finished. Your place is kept on the server.
  finish,

  /// Mark not finished. The server itself puts the book back to 0:00.
  unfinish,

  /// Remove your progress entirely; the book leaves Continue Listening.
  discard,
}

/// The actions that make sense for a book in this state.
List<ProgressAction> progressActionsFor({required bool finished, required bool started}) => [
      if (!finished) ProgressAction.finish,
      if (finished) ProgressAction.unfinish,
      if (started || finished) ProgressAction.discard,
    ];

extension ProgressActionText on ProgressAction {
  String get label => switch (this) {
        ProgressAction.finish => 'Mark as finished',
        ProgressAction.unfinish => 'Mark as not finished',
        ProgressAction.discard => 'Discard progress',
      };

  IconData get icon => switch (this) {
        ProgressAction.finish => Icons.check_circle_outline_rounded,
        ProgressAction.unfinish => Icons.replay_rounded,
        ProgressAction.discard => Icons.remove_circle_outline_rounded,
      };
}

/// Does [action] for book [itemId], asking first when your place would be
/// lost. Safe with the book that's playing: it's stopped (and its place
/// saved) first, and any position kept on this PC for it is forgotten, so
/// it can't come back later. Returns true if something changed.
Future<bool> runProgressAction(
  BuildContext context, {
  required String itemId,
  required String title,
  required ProgressAction action,
}) async {
  final session = context.read<AppSession>();
  final player = context.read<PlayerController>();
  final downloads = context.read<DownloadManager>();
  final messenger = ScaffoldMessenger.of(context);
  final api = session.api;
  if (api == null || session.offline) {
    messenger.showSnackBar(const SnackBar(content: Text('Lectern is offline; try again when the server is back.')));
    return false;
  }

  if (action != ProgressAction.finish) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == ProgressAction.unfinish ? 'Mark "$title" as not finished?' : 'Discard your progress?'),
        content: Text(action == ProgressAction.unfinish
            ? 'The book goes back to the beginning (0:00) on every device.'
            : 'Your place in "$title" is removed on every device, and the book leaves Continue Listening. '
                'This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action == ProgressAction.unfinish ? 'Start over' : 'Discard'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }

  try {
    // The book that's playing: stop first (this saves its place), so the
    // player can't save an old position over the change afterwards.
    if (player.session?.libraryItemId == itemId) await player.stop();

    // Remember the place, so "finished" can be undone without losing it.
    final before = action == ProgressAction.finish ? await api.progressOf(itemId) : null;

    switch (action) {
      case ProgressAction.finish:
        await api.setFinished(itemId, true);
      case ProgressAction.unfinish:
        await api.setFinished(itemId, false);
      case ProgressAction.discard:
        await api.removeProgress(itemId);
    }

    if (action != ProgressAction.finish) {
      // Forget positions kept on this PC, so nothing offers or sends the
      // old place later.
      await PrefsUnsentStore().clear(itemId);
      if (downloads.isDownloaded(itemId)) {
        await downloads.savePosition(itemId, 0);
        await downloads.noteServerPosition(itemId, 0);
      }
    }
    await session.refreshProgress();

    messenger.showSnackBar(SnackBar(
      content: Text(switch (action) {
        ProgressAction.finish => 'Marked as finished',
        ProgressAction.unfinish => 'Marked as not finished',
        ProgressAction.discard => 'Progress discarded',
      }),
      action: before == null
          ? null
          : SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                try {
                  // Unfinishing resets to 0:00 on the server; then put the
                  // place back.
                  final duration = await api.item(itemId).then((b) => b.duration);
                  await api.setFinished(itemId, false);
                  await api.updateProgress(itemId, currentTime: before.currentTime, duration: duration);
                  await session.refreshProgress();
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Could not undo: ${friendlyError(e)}')));
                }
              },
            ),
    ));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not change your progress: ${friendlyError(e)}')));
    return false;
  }
}
