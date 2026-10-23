import 'dart:ui' show ImageFilter, FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../state/downloads.dart';
import '../state/player_controller.dart';
import '../state/theme_controller.dart' show TouchContext;
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';
import 'author_screen.dart';
import 'edit_book_dialog.dart';
import 'match_book_dialog.dart';
import 'series_screen.dart';

class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.itemId});
  final String itemId;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  late Future<BookDetail> _future;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppSession>().api!.item(widget.itemId);
  }

  void _reload() {
    _future.ignore(); // the old request may still fail; nobody is listening to it now
    setState(() {
      _future = context.read<AppSession>().api!.item(widget.itemId);
    });
  }

  Future<void> _edit(BookDetail b) async {
    if (await showEditBookDialog(context, b)) {
      _reload();
      _toast('Details saved');
    }
  }

  Future<void> _match(BookDetail b) async {
    if (await showMatchBookDialog(context, b)) {
      _reload();
      _toast('Match applied');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  void _play({double? at}) {
    final session = context.read<AppSession>();
    context.read<PlayerController>().play(session.api!, session.deviceId, widget.itemId, startAt: at);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<BookDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Could not load this book.\n${snap.error}',
                  textAlign: TextAlign.center, style: TextStyle(color: context.colors.muted)),
            );
          }
          return _buildBook(context, snap.data!);
        },
      ),
    );
  }

  Widget _buildBook(BuildContext context, BookDetail b) {
    final theme = Theme.of(context);
    final player = context.watch<PlayerController>();
    final isCurrent = player.session?.libraryItemId == b.id;
    final description = stripHtml(b.description);

    return Stack(
      children: [
        // Faint, blurred cover wash behind the header.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 420,
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: _blur,
                child: Cover(itemId: b.id, radius: 0, width: 200),
              ),
            ),
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 24, 40, 0),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth > 720;
                  final cover = Container(
                    width: wide ? 280 : 220,
                    height: wide ? 280 : 220,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 18))],
                    ),
                    child: Cover(itemId: b.id, radius: 16, width: 600),
                  );
                  final canEdit = context.read<AppSession>().canEdit;
                  final info = _Info(
                    book: b,
                    isCurrent: isCurrent,
                    onPlay: () => _play(),
                    onEdit: canEdit ? () => _edit(b) : null,
                    onMatch: canEdit ? () => _match(b) : null,
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [cover, const SizedBox(width: 40), Expanded(child: info)],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [cover, const SizedBox(height: 28), info],
                        );
                }),
              ),
            ),
            if (description.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          alignment: Alignment.topCenter,
                          child: Text(
                            description,
                            maxLines: _expanded ? null : 5,
                            overflow: _expanded ? null : TextOverflow.fade,
                            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: context.colors.textSoft),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _expanded = !_expanded),
                          child: Text(_expanded ? 'Show less' : 'Read more'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (b.chapters.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 32, 40, 12),
                sliver: SliverToBoxAdapter(
                  child: Text('${b.chapters.length} chapters',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
                sliver: SliverList.builder(
                  itemCount: b.chapters.length,
                  itemBuilder: (_, i) {
                    final ch = b.chapters[i];
                    return ValueListenableBuilder<double>(
                      valueListenable: player.position,
                      builder: (_, pos, __) {
                        final active = isCurrent && pos >= ch.start && pos < ch.end;
                        return _ChapterTile(
                          index: i + 1,
                          chapter: ch,
                          active: active,
                          onTap: () => _play(at: ch.start),
                        );
                      },
                    );
                  },
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ],
    );
  }
}

final _blur = ImageFilter.blur(sigmaX: 50, sigmaY: 50);

class _Info extends StatelessWidget {
  const _Info({required this.book, required this.isCurrent, required this.onPlay, this.onEdit, this.onMatch});
  final BookDetail book;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback? onEdit; // null when the user may not edit
  final VoidCallback? onMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = context.watch<PlayerController>();
    final b = book;
    final started = b.currentTime > 0 && !b.isFinished;

    final meta = <String>[
      formatDuration(b.duration, compact: true),
      if (b.year != null && b.year!.isNotEmpty) b.year!,
      if (b.narrator != null) 'Narrated by ${b.narrator}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (b.seriesRefs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in b.seriesRefs)
                  _Link(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SeriesScreen(
                        libraryId: context.read<AppSession>().currentLibrary?.id ?? '',
                        seriesId: r.id,
                        name: r.name,
                      ),
                    )),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration:
                          BoxDecoration(color: context.colors.accentSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(r.sequence != null ? '${r.name} #${r.sequence}' : r.name,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: context.colors.accent, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          )
        else if (b.series != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: context.colors.accentSoft, borderRadius: BorderRadius.circular(20)),
            child: Text(b.series!,
                style: theme.textTheme.labelMedium?.copyWith(color: context.colors.accent, fontWeight: FontWeight.w600)),
          ),
        Text(b.title, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 8),
        if (b.authorRefs.isEmpty)
          Text('by ${b.author}', style: theme.textTheme.titleMedium?.copyWith(color: context.colors.textSoft))
        else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('by ', style: theme.textTheme.titleMedium?.copyWith(color: context.colors.textSoft)),
              for (var i = 0; i < b.authorRefs.length; i++) ...[
                if (i > 0) Text(', ', style: theme.textTheme.titleMedium?.copyWith(color: context.colors.textSoft)),
                _Link(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AuthorScreen(authorId: b.authorRefs[i].id, name: b.authorRefs[i].name),
                  )),
                  child: Text(
                    b.authorRefs[i].name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: context.colors.textSoft,
                      decoration: TextDecoration.underline,
                      decorationColor: context.colors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 10),
        Text(meta.join('  ·  '), style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
        if (started) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: 320,
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.progress.clamp(0.0, 1.0).toDouble(),
                      minHeight: 5,
                      backgroundColor: context.colors.track,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${formatDuration(b.duration - b.currentTime, compact: true)} left',
                    style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: isCurrent ? player.togglePlay : onPlay,
              icon: Icon(isCurrent && player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(isCurrent
                  ? (player.playing ? 'Pause' : 'Resume')
                  : (started ? 'Resume' : (b.isFinished ? 'Listen again' : 'Play'))),
            ),
            _DownloadButton(itemId: b.id),
            if (onMatch != null)
              OutlinedButton.icon(
                onPressed: onMatch,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.text,
                  side: BorderSide(color: context.colors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Match'),
              ),
            if (onEdit != null)
              OutlinedButton.icon(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.text,
                  side: BorderSide(color: context.colors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChapterTile extends StatefulWidget {
  const _ChapterTile({required this.index, required this.chapter, required this.active, required this.onTap});
  final int index;
  final Chapter chapter;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.chapter;
    final active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: context.isTouch ? 18 : 12),
          decoration: BoxDecoration(
            color: active ? context.colors.accentSoft : (_hover ? context.colors.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: _hover || active
                    ? Icon(active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                        size: 18, color: context.colors.accent)
                    : Text('${widget.index}', style: TextStyle(color: context.colors.muted)),
              ),
              Expanded(
                child: Text(
                  ch.title.isEmpty ? 'Chapter ${widget.index}' : ch.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? context.colors.accent : context.colors.text,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(formatDuration(ch.end - ch.start),
                  style: TextStyle(color: context.colors.muted, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}


/// Makes any widget clickable with a hand cursor.
class _Link extends StatelessWidget {
  const _Link({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: child),
      );
}


/// Download / progress / downloaded button for the book page.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.itemId});
  final String itemId;

  ButtonStyle _style(BuildContext context) => OutlinedButton.styleFrom(
        foregroundColor: context.colors.text,
        side: BorderSide(color: context.colors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<DownloadManager>();
    final task = dl.tasks[itemId];

    if (task != null) {
      return OutlinedButton.icon(
        style: _style(context),
        onPressed: () => dl.cancel(itemId),
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2.2, value: task.progress > 0 ? task.progress : null),
        ),
        label: Text('${(task.progress * 100).round()}%  ·  Cancel'),
      );
    }

    if (dl.isDownloaded(itemId)) {
      return OutlinedButton.icon(
        style: _style(context),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove download?'),
              content: const Text('The audio files will be deleted from this computer. The book stays on your server.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
              ],
            ),
          );
          if (ok == true) await dl.remove(itemId);
        },
        icon: Icon(Icons.download_done_rounded, size: 18, color: context.colors.accent),
        label: const Text('Downloaded'),
      );
    }

    return OutlinedButton.icon(
      style: _style(context),
      onPressed: () async {
        final api = context.read<AppSession>().api!;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await dl.download(api, itemId);
          if (dl.isDownloaded(itemId)) {
            messenger.showSnackBar(const SnackBar(content: Text('Downloaded: ready to play offline'), behavior: SnackBarBehavior.floating));
          }
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Download failed: $e'), behavior: SnackBarBehavior.floating));
        }
      },
      icon: const Icon(Icons.download_rounded, size: 18),
      label: const Text('Download'),
    );
  }
}
