import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_session.dart';
import '../state/downloads.dart';
import '../state/player_controller.dart';
import '../state/theme_controller.dart' show TouchContext;
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';
import 'book_screen.dart';
import 'player_screen.dart' show openPlayer;

/// Books saved on this computer, plus any downloads in progress.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final dl = context.watch<DownloadManager>();
    final books = dl.books;
    final tasks = dl.tasks.values.toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 6),
            sliver: SliverToBoxAdapter(
              child: Text('Downloads', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 20),
            sliver: SliverToBoxAdapter(
              child: Text(
                books.isEmpty
                    ? 'Download a book from its page to listen without a connection to your server.'
                    : '${books.length} ${books.length == 1 ? 'book' : 'books'}  ·  ${formatBytes(dl.totalBytes)} on this computer',
                style: theme.textTheme.bodyMedium?.copyWith(color: pal.muted),
              ),
            ),
          ),
          if (tasks.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
              sliver: SliverList.list(children: [
                for (final t in tasks) _TaskRow(task: t),
              ]),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 28,
                crossAxisSpacing: 24,
                childAspectRatio: 0.6,
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: books.length,
                (_, i) => _DownloadCard(book: books[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 48, height: 48, child: Cover(itemId: task.id, radius: 6, width: 120)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloading… ${(task.progress * 100).round()}%'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: task.progress, minHeight: 5, backgroundColor: pal.track),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: Icon(Icons.close_rounded, color: pal.muted),
            onPressed: () => context.read<DownloadManager>().cancel(task.id),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatefulWidget {
  const _DownloadCard({required this.book});
  final DownloadedBook book;

  @override
  State<_DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<_DownloadCard> {
  bool _hover = false;

  void _open() {
    final session = context.read<AppSession>();
    if (session.offline) {
      _play(openFull: true);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookScreen(itemId: widget.book.id)));
    }
  }

  void _play({bool openFull = false}) {
    final session = context.read<AppSession>();
    context.read<PlayerController>().play(session.api!, session.deviceId, widget.book.id);
    if (openFull) openPlayer(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('"${widget.book.title}" will be deleted from this computer. It stays on your server.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<DownloadManager>().remove(widget.book.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final b = widget.book;
    final progress = b.duration > 0 ? (b.position / b.duration).clamp(0.0, 1.0) : 0.0;
    final showButtons = _hover || context.isTouch;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Cover(itemId: b.id),
                  if (progress > 0)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.toDouble(),
                          minHeight: 4,
                          backgroundColor: const Color(0x66000000),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                      child: Icon(Icons.download_done_rounded, size: 14, color: pal.onAccent),
                    ),
                  ),
                  if (showButtons)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: const Color(0x99000000),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Remove download',
                          iconSize: 18,
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          onPressed: _delete,
                        ),
                      ),
                    ),
                  if (showButtons)
                    Positioned(
                      right: 10,
                      bottom: progress > 0 ? 20 : 10,
                      child: Material(
                        color: pal.accent,
                        shape: const CircleBorder(),
                        elevation: 6,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _play,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.play_arrow_rounded, color: pal.onAccent),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(b.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(b.author,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
            const SizedBox(height: 2),
            Text('${formatDuration(b.duration, compact: true)}  ·  ${formatBytes(b.sizeBytes)}',
                style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
          ],
        ),
      ),
    );
  }
}
