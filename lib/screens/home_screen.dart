import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/book_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library});
  final Library library;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Shelf>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final session = context.read<AppSession>();
    _future = session.api!.personalized(widget.library.id);
    session.refreshProgress();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: FutureBuilder<List<Shelf>>(
        future: _future,
        builder: (context, snap) {
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.library.name.toUpperCase(),
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: context.colors.accent, letterSpacing: 1.4)),
                            const SizedBox(height: 6),
                            Text(greeting(),
                                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () => setState(_load),
                      ),
                    ],
                  ),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (snap.hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Text('Could not load your library.\n${snap.error}',
                        textAlign: TextAlign.center, style: TextStyle(color: context.colors.muted)),
                  ),
                )
              else if (snap.data!.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('Nothing here yet — add some audiobooks to your server.',
                        style: TextStyle(color: context.colors.muted)),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: snap.data!.length,
                  itemBuilder: (_, i) => _ShelfRow(shelf: snap.data![i]),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}

class _ShelfRow extends StatefulWidget {
  const _ShelfRow({required this.shelf});
  final Shelf shelf;

  @override
  State<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<_ShelfRow> {
  final _scroll = ScrollController();

  void _page(int dir) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + dir * _scroll.position.viewportDimension * 0.8)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    _scroll.animateTo(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.shelf.label,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _page(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 236,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
              clipBehavior: Clip.none,
              itemCount: widget.shelf.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 22),
              itemBuilder: (_, i) => SizedBox(width: 168, child: BookCard(book: widget.shelf.items[i])),
            ),
          ),
        ],
      ),
    );
  }
}
