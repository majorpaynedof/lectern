import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/book_card.dart';
import '../widgets/series_card.dart';

/// One series: its books in reading order, with a button that picks up
/// at the first book you haven't finished.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.libraryId, required this.seriesId, required this.name});
  final String libraryId;
  final String seriesId;
  final String name;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late Future<List<SeriesEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppSession>().api!.seriesBooks(widget.libraryId, widget.seriesId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final session = context.watch<AppSession>();

    return Scaffold(
      body: FutureBuilder<List<SeriesEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Could not load this series.\n${snap.error}',
                  textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
            );
          }
          final entries = snap.data!;
          final finished = entries.where((e) => session.finished.contains(e.book.id)).length;
          SeriesEntry? next;
          for (final e in entries) {
            if (!session.finished.contains(e.book.id)) {
              next = e;
              break;
            }
          }
          final total = entries.fold(0.0, (sum, e) => sum + e.book.duration);

          return CustomScrollView(
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
                padding: const EdgeInsets.fromLTRB(40, 12, 40, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CoverStack(ids: [for (final e in entries.take(3)) e.book.id], radius: 14),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SERIES',
                                style: theme.textTheme.labelMedium?.copyWith(color: pal.accent, letterSpacing: 1.4)),
                            const SizedBox(height: 6),
                            Text(widget.name,
                                style: theme.textTheme.displaySmall
                                    ?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                            const SizedBox(height: 10),
                            Text(
                              '${entries.length} ${entries.length == 1 ? 'book' : 'books'}'
                              '  ·  ${formatDuration(total, compact: true)}'
                              '${finished > 0 ? '  ·  $finished finished' : ''}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: pal.muted),
                            ),
                            const SizedBox(height: 22),
                            if (next != null)
                              FilledButton.icon(
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(finished == 0 && (session.progress[next.book.id] ?? 0) == 0
                                    ? 'Start series'
                                    : 'Continue with ${next.sequence != null ? 'book ${next.sequence}' : next.book.title}'),
                                onPressed: () {
                                  final api = session.api!;
                                  context.read<PlayerController>().play(api, session.deviceId, next!.book.id);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 28, 40, 48),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 26,
                    crossAxisSpacing: 24,
                    childAspectRatio: 0.58,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: entries.length,
                    (_, i) {
                      final e = entries[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.sequence != null ? 'BOOK ${e.sequence}' : ' ',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: pal.accent, letterSpacing: 1.2, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          BookCard(book: e.book),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
