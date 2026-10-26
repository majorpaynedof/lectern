import 'dart:ui' show ImageFilter, FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import '../state/theme_controller.dart' show TouchContext;
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart' show PlayPauseButton;
import '../widgets/player_notices.dart';

/// Slides the full-screen player up over everything.
void openPlayer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => const PlayerScreen(),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  ));
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final s = player.session;
    final theme = Theme.of(context);

    if (s == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Nothing is playing', style: TextStyle(color: context.colors.muted)),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ]),
        ),
      );
    }

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): player.togglePlay,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => player.skip(-10),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => player.skip(30),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): player.previousChapter,
          const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): player.nextChapter,
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Big blurred cover as the backdrop.
              Transform.scale(
                scale: 1.3,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: Cover(itemId: s.libraryItemId, radius: 0, width: 200),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [context.colors.bg.withAlpha(150), context.colors.bg.withAlpha(235)],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Close (Esc)',
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          Text('NOW PLAYING',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(letterSpacing: 2, color: context.colors.textSoft)),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        final wide = c.maxWidth > 900;
                        final coverSize = (wide ? c.maxHeight * 0.62 : c.maxHeight * 0.36).clamp(180.0, 460.0).toDouble();
                        final cover = Hero(
                          tag: 'now-playing-cover',
                          child: Container(
                            width: coverSize,
                            height: coverSize,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.all(Radius.circular(20)),
                              boxShadow: [
                                BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24)),
                              ],
                            ),
                            child: Cover(itemId: s.libraryItemId, radius: 20, width: 800),
                          ),
                        );
                        final controls = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: const _Controls(),
                        );
                        return Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                            child: wide
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [cover, const SizedBox(width: 64), Flexible(child: controls)],
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [cover, const SizedBox(height: 36), controls],
                                  ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              // Messages from the player ("you listened further on another
              // device", saving problems) show here too, not only behind
              // this screen.
              const Positioned(left: 0, right: 0, bottom: 0, child: PlayerNotices()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final s = player.session!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: player.position,
          builder: (_, pos, __) {
            final ch = player.chapterAt(pos);
            return Text(
              (ch?.title.isNotEmpty ?? false) ? ch!.title.toUpperCase() : ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: context.colors.accent, letterSpacing: 1.2, fontWeight: FontWeight.w700),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(s.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 8),
        Text(s.author, style: theme.textTheme.titleMedium?.copyWith(color: context.colors.textSoft)),
        const SizedBox(height: 32),
        const _SeekBar(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundIcon(icon: Icons.skip_previous_rounded, tooltip: 'Previous chapter (Ctrl+←)', onTap: player.previousChapter),
            const SizedBox(width: 16),
            _RoundIcon(icon: Icons.replay_10_rounded, tooltip: 'Back 10s (←)', onTap: () => player.skip(-10)),
            const SizedBox(width: 24),
            PlayPauseButton(size: context.isTouch ? 96 : 76),
            const SizedBox(width: 24),
            _RoundIcon(icon: Icons.forward_30_rounded, tooltip: 'Forward 30s (→)', onTap: () => player.skip(30)),
            const SizedBox(width: 16),
            _RoundIcon(icon: Icons.skip_next_rounded, tooltip: 'Next chapter (Ctrl+→)', onTap: player.nextChapter),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SpeedChip(player: player),
            const SizedBox(width: 10),
            _SleepChip(player: player),
            const SizedBox(width: 10),
            if (s.chapters.isNotEmpty)
              _Chip(
                icon: Icons.format_list_bulleted_rounded,
                label: 'Chapters',
                onTap: () => _showChapters(context, player),
              ),
          ],
        ),
      ],
    );
  }

  void _showChapters(BuildContext context, PlayerController player) {
    final s = player.session!;
    final current = player.currentChapter;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Chapters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: s.chapters.length,
                  itemBuilder: (_, i) {
                    final ch = s.chapters[i];
                    final active = ch.id == current?.id && ch.start == current?.start;
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      selected: active,
                      selectedTileColor: context.colors.accentSoft,
                      selectedColor: context.colors.accent,
                      leading: Text('${i + 1}', style: TextStyle(color: context.colors.muted)),
                      title: Text(ch.title.isEmpty ? 'Chapter ${i + 1}' : ch.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(formatDuration(ch.start),
                          style: TextStyle(
                              color: context.colors.muted, fontFeatures: [FontFeature.tabularFigures()])),
                      onTap: () {
                        player.seekTo(ch.start);
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Book-wide seek bar. Keeps a local value while dragging so the thumb
/// doesn't jump around under the mouse.
class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final dur = player.duration;
    final timeStyle = TextStyle(
      color: context.colors.textSoft,
      fontSize: 13,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return ValueListenableBuilder<double>(
      valueListenable: player.position,
      builder: (_, pos, __) {
        final value = (_drag ?? pos).clamp(0.0, dur > 0 ? dur : 1.0).toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                max: dur > 0 ? dur : 1.0,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  player.seekTo(v);
                  setState(() => _drag = null);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(formatDuration(value), style: timeStyle),
                const Spacer(),
                Text(
                  '${formatDuration((dur - value) / player.speed, compact: true)} left at ${player.speed}×',
                  style: timeStyle,
                ),
                const Spacer(),
                Text(formatDuration(dur), style: timeStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        iconSize: context.isTouch ? 40 : 30,
        style: IconButton.styleFrom(
          foregroundColor: context.colors.text,
          hoverColor: context.colors.hover,
          padding: const EdgeInsets.all(12),
        ),
        icon: Icon(icon),
        onPressed: onTap,
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.onTap, this.highlighted = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted ? context.colors.accentSoft : context.colors.hover,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlighted ? context.colors.accent : context.colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: highlighted ? context.colors.accent : context.colors.text),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: highlighted ? context.colors.accent : context.colors.text)),
        ],
      ),
    );
    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.player});
  final PlayerController player;

  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
        tooltip: 'Playback speed',
        initialValue: player.speed,
        onSelected: player.setSpeed,
        itemBuilder: (_) => [
          for (final v in PlayerController.speeds) PopupMenuItem(value: v, child: Text('$v×')),
        ],
        child: _Chip(icon: Icons.speed_rounded, label: '${player.speed}×', highlighted: player.speed != 1.0),
      );
}

class _SleepChip extends StatelessWidget {
  const _SleepChip({required this.player});
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final remaining = player.sleepRemaining;
    final label = switch (player.sleepMode) {
      SleepMode.off => 'Sleep',
      SleepMode.endOfChapter => 'End of chapter',
      SleepMode.timer => formatDuration((remaining ?? Duration.zero).inSeconds.toDouble()),
    };
    return PopupMenuButton<int>(
      tooltip: 'Sleep timer',
      onSelected: (m) {
        if (m == 0) {
          player.setSleepTimer(null);
        } else if (m == -1) {
          player.sleepAtEndOfChapter();
        } else {
          player.setSleepTimer(Duration(minutes: m));
        }
      },
      itemBuilder: (_) => [
        if (player.sleepMode != SleepMode.off) const PopupMenuItem(value: 0, child: Text('Turn off')),
        for (final m in [5, 10, 15, 30, 45, 60]) PopupMenuItem(value: m, child: Text('$m minutes')),
        const PopupMenuItem(value: -1, child: Text('End of chapter')),
      ],
      child: _Chip(
        icon: Icons.bedtime_rounded,
        label: label,
        highlighted: player.sleepMode != SleepMode.off,
      ),
    );
  }
}
