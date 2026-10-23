import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';
import 'book_screen.dart';

/// Listening statistics from the server: totals, a 14-day chart, your most
/// listened books and recent sessions.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final session = context.read<AppSession>();
    _future = session.api!.listeningStats();
    session.refreshProgress();
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final session = context.watch<AppSession>();

    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Could not load your stats.\n${snap.error}',
                  textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
            );
          }
          final stats = snap.data!;
          double n(dynamic v) => v is num ? v.toDouble() : 0;

          final days = <String, double>{};
          final rawDays = stats['days'];
          if (rawDays is Map) rawDays.forEach((k, v) => days[k.toString()] = n(v));

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          double sumDays(int count) {
            var total = 0.0;
            for (var i = 0; i < count; i++) {
              total += days[_key(today.subtract(Duration(days: i)))] ?? 0;
            }
            return total;
          }

          // Streak: consecutive days with listening, ending today (or
          // yesterday, so it doesn't reset first thing in the morning).
          var streak = 0;
          var day = (days[_key(today)] ?? 0) > 0 ? today : today.subtract(const Duration(days: 1));
          while ((days[_key(day)] ?? 0) > 0) {
            streak++;
            day = day.subtract(const Duration(days: 1));
          }

          final last14 = [
            for (var i = 13; i >= 0; i--)
              (date: today.subtract(Duration(days: i)), seconds: days[_key(today.subtract(Duration(days: i)))] ?? 0.0),
          ];

          final items = <({String id, String title, String author, double seconds})>[];
          final rawItems = stats['items'];
          if (rawItems is Map) {
            rawItems.forEach((k, v) {
              if (v is! Map) return;
              final md = v['mediaMetadata'];
              items.add((
                id: k.toString(),
                title: (md is Map ? md['title'] : null)?.toString() ?? 'Unknown',
                author: (md is Map ? (md['authorName'] ?? _authors(md['authors'])) : null)?.toString() ?? '',
                seconds: n(v['timeListening']),
              ));
            });
          }
          items.sort((a, b) => b.seconds.compareTo(a.seconds));

          final recent = (stats['recentSessions'] as List?) ?? const [];

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Listening stats',
                            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
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
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _Tile(label: 'Today', value: formatDuration(n(stats['today']), compact: true), icon: Icons.today_rounded),
                      _Tile(label: 'Last 7 days', value: formatDuration(sumDays(7), compact: true), icon: Icons.date_range_rounded),
                      _Tile(label: 'Last 30 days', value: formatDuration(sumDays(30), compact: true), icon: Icons.calendar_month_rounded),
                      _Tile(label: 'All time', value: formatDuration(n(stats['totalTime']), compact: true), icon: Icons.all_inclusive_rounded),
                      _Tile(label: 'Books finished', value: '${session.finished.length}', icon: Icons.emoji_events_rounded),
                      _Tile(label: 'Day streak', value: '$streak', icon: Icons.local_fire_department_rounded),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
                sliver: SliverToBoxAdapter(child: _Heading('Last 14 days')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 14, 40, 0),
                sliver: SliverToBoxAdapter(child: _BarChart(days: last14)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(builder: (context, c) {
                    final top = _TopBooks(items: items.take(6).toList());
                    final rec = _Recent(sessions: recent);
                    if (c.maxWidth < 900) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [top, const SizedBox(height: 32), rec]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Expanded(child: top), const SizedBox(width: 40), Expanded(child: rec)],
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String? _authors(dynamic list) {
    if (list is! List || list.isEmpty) return null;
    return list.map((a) => a is Map ? a['name'] : a).join(', ');
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: pal.accent),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.days});
  final List<({DateTime date, double seconds})> days;

  static const _weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final max = days.fold(0.0, (m, d) => d.seconds > m ? d.seconds : m);
    const chartHeight = 160.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: pal.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message: '${d.date.month}/${d.date.day}: ${formatDuration(d.seconds, compact: true)}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: chartHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 0.6,
                          heightFactor: max <= 0 ? 0.02 : (d.seconds / max).clamp(0.02, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: d.seconds > 0 ? pal.accent : pal.track,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_weekday[d.date.weekday - 1],
                        style: theme.textTheme.labelSmall?.copyWith(color: pal.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBooks extends StatelessWidget {
  const _TopBooks({required this.items});
  final List<({String id, String title, String author, double seconds})> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final max = items.isEmpty ? 1.0 : items.first.seconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Most listened'),
        const SizedBox(height: 14),
        if (items.isEmpty) Text('Nothing yet', style: TextStyle(color: pal.muted)),
        for (final it in items)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookScreen(itemId: it.id))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(width: 52, height: 52, child: Cover(itemId: it.id, radius: 6, width: 120)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: max > 0 ? it.seconds / max : 0,
                            minHeight: 5,
                            backgroundColor: pal.track,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(formatDuration(it.seconds, compact: true), style: TextStyle(color: pal.textSoft)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.sessions});
  final List<dynamic> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Recent sessions'),
        const SizedBox(height: 14),
        if (sessions.isEmpty) Text('Nothing yet', style: TextStyle(color: pal.muted)),
        for (final raw in sessions)
          if (raw is Map)
            Builder(builder: (context) {
              final updated = raw['updatedAt'] is num
                  ? DateTime.fromMillisecondsSinceEpoch((raw['updatedAt'] as num).toInt())
                  : null;
              final listened = raw['timeListening'] is num ? (raw['timeListening'] as num).toDouble() : 0.0;
              final when = updated == null ? '' : _relative(updated);
              final device = (raw['deviceInfo'] is Map ? raw['deviceInfo']['clientName'] : null)?.toString();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Cover(itemId: (raw['libraryItemId'] ?? '').toString(), radius: 6, width: 120),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((raw['displayTitle'] ?? 'Unknown').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            [when, if (device != null && device.isNotEmpty) device].join('  ·  '),
                            style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(formatDuration(listened, compact: true), style: TextStyle(color: pal.textSoft)),
                  ],
                ),
              );
            }),
      ],
    );
  }

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return '${t.month}/${t.day}/${t.year}';
  }
}
