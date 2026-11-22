import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/abs_api.dart';
import '../duplicate_finder.dart';
import '../models.dart';
import '../state/app_session.dart';
import '../state/downloads.dart';
import '../state/player_controller.dart';
import '../sync/abs_progress.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';

/// Find duplicates, review first: books that look like the same book entered
/// more than once, shown side by side. You pick the copy to keep; nothing is
/// deleted until you confirm, and your place can move to the copy you keep.
///
/// Returns true if anything was deleted.
Future<bool> openDuplicates(BuildContext context, Library library) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => DuplicatesScreen(library: library))) ??
    false;

const _kIgnored = 'duplicatesIgnored';

/// One copy's details from the server.
class _Copy {
  _Copy(Map<String, dynamic> j)
      : id = j['id'].toString(),
        path = (j['path'] ?? '').toString(),
        addedAt = (j['addedAt'] as num?)?.toInt() ?? 0,
        size = (j['size'] as num?)?.toInt() ?? 0,
        title = ((j['media'] as Map?)?['metadata'] as Map?)?['title']?.toString() ?? 'Untitled',
        duration = (((j['media'] as Map?)?['duration']) as num?)?.toDouble() ?? 0,
        files = ((j['media'] as Map?)?['audioFiles'] as List?)?.length ?? 0,
        formats = {
          for (final f in ((j['media'] as Map?)?['audioFiles'] as List?) ?? const [])
            if (f is Map) ((f['metadata'] as Map?)?['ext'] ?? '').toString().replaceAll('.', '').toUpperCase(),
        }..remove(''),
        currentTime = ((j['userMediaProgress'] as Map?)?['currentTime'] as num?)?.toDouble() ?? 0,
        finished = (j['userMediaProgress'] as Map?)?['isFinished'] == true;

  final String id;
  final String path;
  final int addedAt;
  final int size;
  final String title;
  final double duration;
  final int files;
  final Set<String> formats;
  final double currentTime;
  final bool finished;

  bool get hasProgress => finished || currentTime > 0;

  String get place => finished ? 'Finished' : (currentTime > 0 ? 'At ${formatDuration(currentTime)}' : 'Not started');

  String get added {
    if (addedAt <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(addedAt);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

enum _St { open, working, done, notDuplicates }

class _Group {
  _Group(this.group);
  final DuplicateGroup group;
  _St status = _St.open;
  String? message;
}

class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key, required this.library});
  final Library library;

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  bool _loading = true;
  String? _error;
  int _checked = 0;
  List<_Group> _groups = [];
  final Map<String, Future<_Copy>> _copies = {};
  bool _changed = false;
  bool _showDone = false;
  late final AbsApi _api;

  @override
  void initState() {
    super.initState();
    _api = context.read<AppSession>().api!;
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ignored = (prefs.getStringList(_kIgnored) ?? const []).toSet();
      final books = await _api.allBooks(widget.library.id);
      final found = findDuplicates(
        [for (final b in books) DupBook(id: b.id, title: b.title, author: b.author, duration: b.duration, series: b.series, path: b.path)],
        ignored: ignored,
      );
      if (!mounted) return;
      setState(() {
        _checked = books.length;
        _groups = [for (final g in found) _Group(g)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the library: ${friendlyError(e)}';
        });
      }
    }
  }

  Future<_Copy> _copy(String id) => _copies.putIfAbsent(id, () => _api.itemRaw(id).then(_Copy.new));

  Future<void> _notDuplicates(_Group g) async {
    final prefs = await SharedPreferences.getInstance();
    final ignored = (prefs.getStringList(_kIgnored) ?? <String>[]).toSet();
    final ids = g.group.ids;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        ignored.add(pairKey(ids[i], ids[j]));
      }
    }
    await prefs.setStringList(_kIgnored, ignored.toList());
    setState(() {
      g.status = _St.notDuplicates;
      g.message = 'Marked as not duplicates; they won\'t be suggested again.';
    });
  }

  Future<void> _keep(_Group g, String keepId) async {
    final session = context.read<AppSession>();
    final api = session.api!;
    final player = context.read<PlayerController>();
    final downloads = context.read<DownloadManager>();

    final List<_Copy> all;
    try {
      all = await Future.wait(g.group.ids.map(_copy));
    } catch (e) {
      _snack('Could not load the copies: ${friendlyError(e)}');
      return;
    }
    final keep = all.firstWhere((c) => c.id == keepId);
    final remove = all.where((c) => c.id != keepId).toList();
    if (!mounted) return;
    final choice = await showDialog<_KeepChoice>(
      context: context,
      builder: (_) => _KeepDialog(keep: keep, remove: remove),
    );
    if (choice == null || !mounted) return;

    setState(() => g.status = _St.working);
    final failed = <String>[];
    try {
      // Anything playing or saved on this PC for these books goes first, so
      // nothing saves an old position afterwards.
      final ids = {keep.id, ...remove.map((c) => c.id)};
      if (ids.contains(player.session?.libraryItemId)) await player.stop();

      final from = choice.carryFrom;
      if (from != null) {
        if (from.finished) {
          await api.setFinished(keep.id, true);
        } else {
          await api.updateProgress(keep.id, currentTime: from.currentTime, duration: keep.duration);
        }
        await PrefsUnsentStore().clear(keep.id);
      }

      for (final c in remove) {
        try {
          if (downloads.isDownloaded(c.id)) await downloads.remove(c.id);
          await PrefsUnsentStore().clear(c.id);
          await api.deleteItem(c.id, deleteFiles: choice.deleteFiles);
        } catch (e) {
          failed.add('${c.title}: ${friendlyError(e)}');
        }
      }
      await session.refreshProgress();
    } catch (e) {
      failed.add(friendlyError(e));
    }
    if (!mounted) return;
    setState(() {
      _changed = true;
      g.status = failed.isEmpty ? _St.done : _St.open;
      g.message = failed.isEmpty
          ? 'Kept "${keep.title}"; ${remove.length == 1 ? 'the other copy was' : '${remove.length} copies were'} '
              '${choice.deleteFiles ? 'deleted with its files' : 'removed from the library'}.'
              '${choice.carryFrom != null ? ' Your place moved to the copy you kept.' : ''}'
          : 'Some of it didn\'t work: ${failed.join('; ')}';
      for (final c in remove) {
        _copies.remove(c.id);
      }
      _copies.remove(keep.id);
    });
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final canDelete = context.read<AppSession>().canDelete;
    final open = _groups.where((g) => g.status == _St.open || g.status == _St.working).toList();
    final done = _groups.where((g) => g.status == _St.done || g.status == _St.notDuplicates).toList();
    final shown = _showDone ? done : open;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(_changed),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Text('Find duplicates', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(
                'Books that look like the same book entered more than once. Compare the copies, then keep one. '
                'Nothing is deleted until you confirm, and your place can move to the copy you keep.',
                style: TextStyle(color: pal.muted),
              ),
              if (!canDelete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Your account isn\'t allowed to delete books, so you can only compare them here.',
                      style: TextStyle(color: pal.danger)),
                ),
              const SizedBox(height: 14),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!, style: TextStyle(color: pal.danger))))
              else ...[
                Row(children: [
                  ChoiceChip(
                    label: Text('To review (${open.length})'),
                    selected: !_showDone,
                    onSelected: (_) => setState(() => _showDone = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Done (${done.length})'),
                    selected: _showDone,
                    onSelected: (_) => setState(() => _showDone = true),
                  ),
                  const SizedBox(width: 16),
                  Text('Checked $_checked books', style: TextStyle(color: pal.textSoft)),
                ]),
                const SizedBox(height: 14),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(
                            _groups.isEmpty ? 'No duplicates found.' : 'Nothing here.',
                            style: TextStyle(color: pal.muted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 40),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, n) => _groupCard(shown[n], canDelete),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(_Group g, bool canDelete) {
    final pal = context.colors;
    final open = g.status == _St.open;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(g.group.reason, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                _Tag('${g.group.confidence} confidence', strong: g.group.confidence == 'High'),
                _Tag('${g.group.ids.length} copies'),
              ]),
            ),
            if (open) TextButton(onPressed: () => _notDuplicates(g), child: const Text('Not duplicates')),
            if (g.status == _St.working)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (g.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(g.message!, style: TextStyle(color: g.status == _St.open ? pal.danger : pal.muted)),
            ),
          if (g.status == _St.open || g.status == _St.working) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final id in g.group.ids)
                  SizedBox(
                    width: 300,
                    child: FutureBuilder<_Copy>(
                      future: _copy(id),
                      builder: (context, snap) => _copyCard(
                        id,
                        snap.data,
                        snap.error,
                        onKeep: open && canDelete && snap.hasData ? () => _keep(g, id) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _copyCard(String id, _Copy? c, Object? error, {VoidCallback? onKeep}) {
    final pal = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 72, height: 72, child: Cover(itemId: id, width: 200, radius: 8)),
            const SizedBox(width: 12),
            Expanded(
              child: c == null
                  ? Text(error == null ? 'Loading…' : 'Could not load: ${friendlyError(error)}',
                      style: TextStyle(color: error == null ? pal.muted : pal.danger))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(c.place,
                          style: TextStyle(color: c.hasProgress ? pal.accent : pal.muted, fontWeight: FontWeight.w600)),
                    ]),
            ),
          ]),
          if (c != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (c.duration > 0) _Tag(formatDuration(c.duration, compact: true)),
              if (c.formats.isNotEmpty) _Tag(c.formats.join(', ')),
              _Tag('${c.files} file${c.files == 1 ? '' : 's'}'),
              if (c.size > 0) _Tag(formatBytes(c.size)),
              if (c.added.isNotEmpty) _Tag('Added ${c.added}'),
            ]),
            const SizedBox(height: 8),
            SelectableText(c.path, style: TextStyle(color: pal.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onKeep, child: const Text('Keep this one')),
            ),
          ],
        ],
      ),
    );
  }
}

/// What to do with the other copies.
class _KeepChoice {
  const _KeepChoice({required this.deleteFiles, this.carryFrom});
  final bool deleteFiles;

  /// The copy whose place moves to the kept one, if any.
  final _Copy? carryFrom;
}

class _KeepDialog extends StatefulWidget {
  const _KeepDialog({required this.keep, required this.remove});
  final _Copy keep;
  final List<_Copy> remove;

  @override
  State<_KeepDialog> createState() => _KeepDialogState();
}

class _KeepDialogState extends State<_KeepDialog> {
  _Copy? _source;
  bool _carry = false;

  @override
  void initState() {
    super.initState();
    // The copy furthest along, if it's further than the one you keep.
    double rank(_Copy c) => c.finished ? double.infinity : c.currentTime;
    final best = widget.remove.where((c) => c.hasProgress).fold<_Copy?>(
          null,
          (a, c) => a == null || rank(c) > rank(a) ? c : a,
        );
    if (best != null && rank(best) > rank(widget.keep) + 60) {
      _source = best;
      // Same length: the same time is the same spot in the story.
      _carry = best.finished || _sameLength(best, widget.keep);
    }
  }

  static bool _sameLength(_Copy a, _Copy b) =>
      a.duration > 0 && b.duration > 0 && (a.duration - b.duration).abs() <= 0.02 * (a.duration > b.duration ? a.duration : b.duration);

  /// Deleting files would also delete the copy you keep (one folder inside
  /// the other, or the same folder).
  bool get _sharedFolder {
    String norm(String p) => p.replaceAll('\\', '/').toLowerCase().replaceAll(RegExp(r'/+$'), '');
    final k = norm(widget.keep.path);
    return widget.remove.any((c) {
      final r = norm(c.path);
      return r.isEmpty || k.isEmpty || r == k || k.startsWith('$r/') || r.startsWith('$k/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    final source = _source;
    final n = widget.remove.length;
    return AlertDialog(
      title: Text('Keep "${widget.keep.title}"?'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n == 1 ? 'The other copy will go:' : 'These $n copies will go:'),
            const SizedBox(height: 8),
            for (final c in widget.remove)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${c.title} (${[if (c.formats.isNotEmpty) c.formats.join(', '), if (c.size > 0) formatBytes(c.size), c.place].join(', ')})\n  ${c.path}',
                  style: TextStyle(color: pal.textSoft),
                ),
              ),
            if (source != null) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _carry,
                onChanged: (v) => setState(() => _carry = v ?? false),
                title: Text(source.finished
                    ? 'Mark the copy you keep as finished'
                    : 'Move your place (${formatDuration(source.currentTime)}) to the copy you keep'),
                subtitle: source.finished || _sameLength(source, widget.keep)
                    ? null
                    : Text('The two copies are different lengths, so the same time may not be the same spot.',
                        style: TextStyle(color: pal.muted)),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Remove from library only: the files stay on the server, and the next library scan will probably '
              'add the book back.\n'
              'Delete files too: the copy\'s folder is deleted from the server. This can\'t be undone.',
              style: TextStyle(color: pal.muted, fontSize: 13),
            ),
            if (_sharedFolder)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'These copies share a folder, so deleting files would delete the copy you keep too. '
                  'Only "Remove from library" is possible here.',
                  style: TextStyle(color: pal.danger, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(
          onPressed: () =>
              Navigator.pop(context, _KeepChoice(deleteFiles: false, carryFrom: _carry ? _source : null)),
          child: const Text('Remove from library only'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: pal.danger),
          onPressed: _sharedFolder
              ? null
              : () => Navigator.pop(context, _KeepChoice(deleteFiles: true, carryFrom: _carry ? _source : null)),
          child: const Text('Delete files too'),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: strong ? pal.accentSoft : pal.surfaceHigh, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, color: strong ? pal.accent : pal.muted)),
    );
  }
}
