import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/book_screen.dart';
import '../state/app_session.dart';
import '../state/downloads.dart';
import '../state/theme_controller.dart' show TouchContext;
import '../state/player_controller.dart';
import '../theme.dart';
import 'cover.dart';

/// Cover + title + author, with a hover lift and a quick-play button.
class BookCard extends StatefulWidget {
  const BookCard({super.key, required this.book});
  final BookSummary book;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _hover = false;

  void _open() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookScreen(itemId: widget.book.id),
    ));
  }

  void _play() {
    final session = context.read<AppSession>();
    context.read<PlayerController>().play(session.api!, session.deviceId, widget.book.id);
  }

  /// Touch mode: long-press a cover for quick actions.
  Future<void> _menu() async {
    final session = context.read<AppSession>();
    final dl = context.read<DownloadManager>();
    final id = widget.book.id;
    final pal = context.colors;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(widget.book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final (value, icon, label) in [
              ('play', Icons.play_arrow_rounded, 'Play'),
              ('open', Icons.info_outline_rounded, 'Open book page'),
              if (!session.offline && !dl.isDownloaded(id) && !dl.tasks.containsKey(id))
                ('download', Icons.download_rounded, 'Download'),
              if (dl.isDownloaded(id)) ('remove', Icons.delete_outline_rounded, 'Remove download'),
            ])
              ListTile(
                minTileHeight: 60,
                leading: Icon(icon, color: pal.accent),
                title: Text(label, style: const TextStyle(fontSize: 17)),
                onTap: () => Navigator.of(ctx).pop(value),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'play':
        _play();
      case 'open':
        _open();
      case 'download':
        dl.download(session.api!, id).catchError((_) {});
      case 'remove':
        await dl.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final touch = context.isTouch;
    final showPlay = _hover || touch;
    final progress = session.progress[widget.book.id] ?? 0;
    final finished = session.finished.contains(widget.book.id);
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _open,
        onLongPress: touch ? _menu : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: AnimatedScale(
                scale: _hover ? 1.035 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _hover ? const Color(0x66000000) : const Color(0x33000000),
                        blurRadius: _hover ? 24 : 12,
                        offset: Offset(0, _hover ? 10 : 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Cover(itemId: widget.book.id),
                      if (progress > 0 && !finished)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0).toDouble(),
                              minHeight: 4,
                              backgroundColor: const Color(0x66000000),
                              color: context.colors.accent,
                            ),
                          ),
                        ),
                      if (finished)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: context.colors.accent,
                            child: Icon(Icons.check_rounded, size: 16, color: context.colors.onAccent),
                          ),
                        ),
                      Positioned(
                        right: 10,
                        bottom: progress > 0 && !finished ? 20 : 10,
                        child: AnimatedOpacity(
                          opacity: showPlay ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: IgnorePointer(
                            ignoring: !showPlay,
                            child: Material(
                              color: context.colors.accent,
                              shape: const CircleBorder(),
                              elevation: 6,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _play,
                                child: Padding(
                                  padding: EdgeInsets.all(touch ? 13 : 10),
                                  child: Icon(Icons.play_arrow_rounded,
                                      size: touch ? 30 : 24, color: context.colors.onAccent),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              widget.book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
