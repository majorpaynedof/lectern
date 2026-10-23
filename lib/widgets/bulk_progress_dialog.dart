import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'cover.dart' show refreshImages;

/// Result of one item in a bulk job.
enum BulkOutcome { updated, unchanged, notFound, failed }

/// Runs [job] on every item (a few at a time) and shows live progress with
/// a Stop button. Returns how many items were updated.
Future<int> runBulk<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) label,
  required Future<BulkOutcome> Function(T) job,
  int parallel = 3,
}) async {
  final updated = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BulkDialog<T>(title: title, items: items, label: label, job: job, parallel: parallel),
  );
  return updated ?? 0;
}

class _BulkDialog<T> extends StatefulWidget {
  const _BulkDialog({
    required this.title,
    required this.items,
    required this.label,
    required this.job,
    required this.parallel,
  });
  final String title;
  final List<T> items;
  final String Function(T) label;
  final Future<BulkOutcome> Function(T) job;
  final int parallel;

  @override
  State<_BulkDialog<T>> createState() => _BulkDialogState<T>();
}

class _BulkDialogState<T> extends State<_BulkDialog<T>> {
  int _next = 0;
  int _done = 0;
  int _updated = 0;
  int _notFound = 0;
  int _failed = 0;
  bool _stopping = false;
  bool _finished = false;
  final List<String> _current = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    Future<void> worker() async {
      while (!_stopping && _next < widget.items.length) {
        final item = widget.items[_next++];
        final name = widget.label(item);
        if (mounted) setState(() => _current.add(name));
        BulkOutcome outcome;
        try {
          outcome = await widget.job(item);
        } catch (_) {
          outcome = BulkOutcome.failed;
        }
        if (!mounted) return;
        setState(() {
          _current.remove(name);
          _done++;
          switch (outcome) {
            case BulkOutcome.updated:
              _updated++;
            case BulkOutcome.notFound:
              _notFound++;
            case BulkOutcome.failed:
              _failed++;
            case BulkOutcome.unchanged:
              break;
          }
        });
      }
    }

    await Future.wait([for (var i = 0; i < widget.parallel; i++) worker()]);
    refreshImages();
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final total = widget.items.length;
    final value = total == 0 ? 1.0 : _done / total;

    Widget stat(String label, int n, Color color) => Expanded(
          child: Column(
            children: [
              Text('$n', style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
            ],
          ),
        );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: pal.track),
              ),
              const SizedBox(height: 8),
              Text(
                _finished
                    ? (_stopping ? 'Stopped after $_done of $total' : 'Done: $total of $total')
                    : '$_done of $total',
                style: theme.textTheme.bodyMedium?.copyWith(color: pal.muted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  stat('updated', _updated, pal.accent),
                  stat('no match', _notFound, pal.textSoft),
                  stat('errors', _failed, _failed > 0 ? pal.danger : pal.textSoft),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: _finished
                    ? const SizedBox()
                    : Text(
                        _current.isEmpty ? '' : 'Working on: ${_current.join(' · ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _finished
                    ? FilledButton(onPressed: () => Navigator.of(context).pop(_updated), child: const Text('Close'))
                    : TextButton(
                        onPressed: _stopping ? null : () => setState(() => _stopping = true),
                        child: Text(_stopping ? 'Stopping…' : 'Stop'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
