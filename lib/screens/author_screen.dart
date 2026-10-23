import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/author_avatar.dart';
import '../widgets/book_card.dart';
import '../widgets/cover.dart' show refreshImages;
import '../widgets/series_card.dart';
import 'series_screen.dart';

/// One author: photo, bio, their series, and all their books.
class AuthorScreen extends StatefulWidget {
  const AuthorScreen({super.key, required this.authorId, required this.name});
  final String authorId;
  final String name;

  @override
  State<AuthorScreen> createState() => _AuthorScreenState();
}

class _AuthorScreenState extends State<AuthorScreen> {
  late Future<AuthorDetail> _future;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppSession>().api!.author(widget.authorId);
  }

  bool _busy = false;

  void _reload() {
    _future.ignore(); // the old request may still fail; nobody is listening to it now
    setState(() {
      _future = context.read<AppSession>().api!.author(widget.authorId);
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _match(AuthorDetail a) async {
    setState(() => _busy = true);
    try {
      final found = await context.read<AppSession>().api!.matchAuthor(a.summary.id, a.summary.name);
      if (found) {
        refreshImages();
        _reload();
        _toast('Found ${a.summary.name}: photo and bio updated');
      } else {
        _toast('No match found for "${a.summary.name}". Try editing the name first.');
      }
    } catch (e) {
      _toast('Match failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(AuthorDetail a) async {
    final name = TextEditingController(text: a.summary.name);
    final bioText = stripHtml(a.description);
    final bio = TextEditingController(text: bioText);
    final pal = context.colors;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit author'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name', style: TextStyle(color: pal.muted, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(controller: name),
              const SizedBox(height: 14),
              Text('Bio', style: TextStyle(color: pal.muted, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(controller: bio, minLines: 4, maxLines: 10),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (save == true && name.text.trim().isNotEmpty && mounted) {
      try {
        await context.read<AppSession>().api!.updateAuthor(
              a.summary.id,
              name: name.text.trim(),
              description: bio.text.trim() == bioText ? null : bio.text.trim(),
            );
        _reload();
        _toast('Author saved');
      } catch (e) {
        _toast('Could not save: $e');
      }
    }
    name.dispose();
    bio.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final canEdit = context.read<AppSession>().canEdit;
    final libraryId = context.read<AppSession>().currentLibrary?.id ?? '';

    return Scaffold(
      body: FutureBuilder<AuthorDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Could not load this author.\n${snap.error}',
                  textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
            );
          }
          final a = snap.data!;
          final bio = stripHtml(a.description);

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
                padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      AuthorAvatar(author: a.summary, size: 160),
                      const SizedBox(width: 36),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AUTHOR',
                                style: theme.textTheme.labelMedium?.copyWith(color: pal.accent, letterSpacing: 1.4)),
                            const SizedBox(height: 6),
                            Text(a.summary.name,
                                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Text(
                              '${a.books.length} ${a.books.length == 1 ? 'book' : 'books'}'
                              '${a.series.isNotEmpty ? '  ·  ${a.series.length} series' : ''}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: pal.muted),
                            ),
                            if (canEdit) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _match(a),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: pal.text,
                                      side: BorderSide(color: pal.border),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: _busy
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.travel_explore_rounded, size: 18),
                                    label: const Text('Find photo & bio'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : () => _edit(a),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: pal.text,
                                      side: BorderSide(color: pal.border),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.edit_rounded, size: 18),
                                    label: const Text('Edit'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (bio.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 0),
                  sliver: SliverToBoxAdapter(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            alignment: Alignment.topCenter,
                            child: Text(
                              bio,
                              maxLines: _expanded ? null : 4,
                              overflow: _expanded ? null : TextOverflow.fade,
                              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, color: pal.textSoft),
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
              if (a.series.isNotEmpty) ...[
                _heading(context, 'Series'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 250,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                      clipBehavior: Clip.none,
                      itemCount: a.series.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 24),
                      itemBuilder: (_, i) {
                        final s = a.series[i];
                        return SizedBox(
                          width: 170,
                          child: SeriesCard(
                            series: s,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SeriesScreen(libraryId: libraryId, seriesId: s.id, name: s.name),
                            )),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              _heading(context, 'Books'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 28,
                    crossAxisSpacing: 24,
                    childAspectRatio: 0.64,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: a.books.length,
                    (_, i) => BookCard(book: a.books[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 14),
        sliver: SliverToBoxAdapter(
          child: Text(text,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}
