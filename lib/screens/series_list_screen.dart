import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../widgets/series_card.dart';
import 'series_finder_screen.dart';
import 'series_screen.dart';

class _Sort {
  const _Sort(this.label, this.key, this.desc);
  final String label;
  final String key;
  final bool desc;
}

const _sorts = [
  _Sort('Name', 'name', false),
  _Sort('Recently added', 'addedAt', true),
  _Sort('Most books', 'numBooks', true),
  _Sort('Longest', 'totalDuration', true),
];

/// All series in the library, as a grid of fanned cover stacks.
class SeriesListScreen extends StatefulWidget {
  const SeriesListScreen({super.key, required this.library});
  final Library library;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  static const _pageSize = 40;

  final _scroll = ScrollController();
  final List<SeriesSummary> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  _Sort _sort = _sorts.first;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final api = context.read<AppSession>().api!;
      final res = await api.series(widget.library.id,
          page: _page, limit: _pageSize, sort: _sort.key, desc: _sort.desc);
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page++;
        _hasMore = res.raw == _pageSize;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted && _hasMore && _error == null && _items.length < 30) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
      }
    }
  }

  void _changeSort(_Sort s) {
    setState(() {
      _sort = s;
      _items.clear();
      _page = 0;
      _hasMore = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text('Series', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                // Suggests series for books that aren't in one; only for
                // accounts that may edit books.
                if (context.watch<AppSession>().canEdit && !context.watch<AppSession>().offline) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (await openSeriesFinder(context) && mounted) _changeSort(_sort);
                    },
                    icon: const Icon(Icons.travel_explore_rounded, size: 18),
                    label: const Text('Find missing series'),
                  ),
                  const SizedBox(width: 12),
                ],
                PopupMenuButton<_Sort>(
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: _changeSort,
                  itemBuilder: (_) => [for (final s in _sorts) PopupMenuItem(value: s, child: Text(s.label))],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.sort_rounded, size: 18, color: pal.muted),
                      const SizedBox(width: 8),
                      Text(_sort.label),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? Center(
                    child: Text(_error ?? 'No series in this library', style: TextStyle(color: pal.muted)),
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 28,
                        crossAxisSpacing: 26,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: _items.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) return const Center(child: CircularProgressIndicator());
                        final s = _items[i];
                        return SeriesCard(
                          series: s,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SeriesScreen(
                              libraryId: widget.library.id,
                              seriesId: s.id,
                              name: s.name,
                            ),
                          )),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
