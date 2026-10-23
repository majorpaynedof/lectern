import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';

import '../state/app_session.dart';
import '../state/player_controller.dart';
import '../state/theme_controller.dart';
import '../theme.dart';
import '../widgets/mini_player.dart';
import 'appearance_screen.dart';
import 'authors_screen.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart' show AppLogo;
import 'series_list_screen.dart';
import 'stats_screen.dart';

/// Main window layout: sidebar on the left, content on the right,
/// mini player along the bottom.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  // Tabs: 0 Home, 1 Library, 2 Series, 3 Authors, 4 Downloads, 5 Stats, 6 Appearance.
  static const _downloadsTab = 4;
  static const _appearanceTab = 6;
  bool _retrying = false;

  Future<void> _retry(AppSession session) async {
    setState(() => _retrying = true);
    final ok = await session.retryOnline();
    if (!mounted) return;
    setState(() => _retrying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Back online' : 'Still can\'t reach your server'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final lib = session.currentLibrary;
    final player = context.watch<PlayerController>();

    // Offline, only Downloads and Appearance work.
    final tab = session.offline && _tab != _appearanceTab ? _downloadsTab : _tab;

    Widget content;
    if (tab == _downloadsTab) {
      content = const DownloadsScreen();
    } else if (tab == 5) {
      content = const StatsScreen();
    } else if (tab == _appearanceTab) {
      content = const AppearanceScreen();
    } else if (lib == null) {
      content = const _Empty(message: 'No audiobook libraries on this server yet.');
    } else {
      content = switch (tab) {
        0 => HomeScreen(library: lib),
        1 => LibraryScreen(library: lib),
        2 => SeriesListScreen(library: lib),
        _ => AuthorsScreen(library: lib),
      };
    }

    return Scaffold(
      body: Column(
        children: [
          if (session.offline)
            MaterialBanner(
              backgroundColor: context.colors.surfaceHigh,
              leading: Icon(Icons.cloud_off_rounded, color: context.colors.accent),
              content: const Text("You're offline. Your downloaded books still play, and your listening will sync when the server is back."),
              actions: [
                TextButton(
                  onPressed: _retrying ? null : () => _retry(session),
                  child: Text(_retrying ? 'Trying…' : 'Try again'),
                ),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                SidebarTheme(
                  child: _Sidebar(selected: tab, offline: session.offline, onSelect: (i) => setState(() => _tab = i)),
                ),
                Expanded(
                  // A nested navigator so book pages open inside the
                  // content area and the sidebar + player stay put.
                  child: Navigator(
                    key: ValueKey('$tab-${lib?.id}-${session.offline}'),
                    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => content),
                  ),
                ),
              ],
            ),
          ),
          if (player.lastError != null)
            MaterialBanner(
              backgroundColor: context.colors.surfaceHigh,
              content: SelectableText('Playback problem: ${player.lastError}'),
              actions: [
                TextButton(
                  onPressed: () {
                    player.lastError = null;
                    setState(() {});
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          const SidebarTheme(child: MiniPlayer()),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect, this.offline = false});
  final int selected;
  final ValueChanged<int> onSelect;
  final bool offline; // dims items that need the server

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    final theme = Theme.of(context);

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
      // Scrolls when the window is too short to fit everything (e.g. with
      // Touch mode's bigger items); otherwise fills the height as before.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const AppLogo(size: 32),
                const SizedBox(width: 12),
                Text('Lectern', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: selected == 0,
            onTap: () => onSelect(0),
          ),
          _NavItem(
            icon: Icons.auto_stories_rounded,
            label: 'Library',
            selected: selected == 1,
            onTap: () => onSelect(1),
          ),
          _NavItem(
            icon: Icons.collections_bookmark_rounded,
            label: 'Series',
            selected: selected == 2,
            onTap: () => onSelect(2),
          ),
          _NavItem(
            icon: Icons.person_rounded,
            label: 'Authors',
            selected: selected == 3,
            onTap: () => onSelect(3),
          ),
          _NavItem(
            icon: Icons.download_rounded,
            label: 'Downloads',
            selected: selected == 4,
            onTap: () => onSelect(4),
          ),
          _NavItem(
            icon: Icons.insights_rounded,
            label: 'Stats',
            selected: selected == 5,
            onTap: () => onSelect(5),
          ),
          const SizedBox(height: 24),
          if (session.libraries.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Text('LIBRARIES',
                  style: theme.textTheme.labelSmall?.copyWith(color: context.colors.muted, letterSpacing: 1.2)),
            ),
            for (final l in session.libraries)
              _NavItem(
                icon: Icons.folder_rounded,
                label: l.name,
                dense: true,
                selected: session.currentLibrary?.id == l.id,
                onTap: () => session.selectLibrary(l),
              ),
          ],
          const Spacer(),
          const _TouchToggle(),
          _NavItem(
            icon: Icons.palette_rounded,
            label: 'Appearance',
            selected: selected == 6,
            onTap: () => onSelect(6),
          ),
          const _SupportLink(),
          const Divider(height: 24),
          Row(
            children: [
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 16,
                backgroundColor: context.colors.accentSoft,
                child: Text(
                  (session.username?.isNotEmpty ?? false) ? session.username![0].toUpperCase() : '?',
                  style: TextStyle(color: context.colors.accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(session.username ?? '',
                    overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
              IconButton(
                tooltip: 'Sign out',
                icon: Icon(Icons.logout_rounded, size: 20, color: context.colors.muted),
                onPressed: () async {
                  await context.read<PlayerController>().stop();
                  await session.logout();
                },
              ),
            ],
          ),
        ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? context.colors.accent : (_hover ? context.colors.text : context.colors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: (widget.dense ? 9 : 12) + (context.isTouch ? 6 : 0)),
            decoration: BoxDecoration(
              color: widget.selected
                  ? context.colors.accentSoft
                  : (_hover ? context.colors.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: widget.dense ? 18 : 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected ? context.colors.text : color,
                      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: widget.dense ? 13 : 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(message, style: TextStyle(color: context.colors.muted)),
      );
}


/// Sidebar switch for Touch mode.
class _TouchToggle extends StatelessWidget {
  const _TouchToggle();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ThemeController>();
    final on = context.isTouch;
    final pal = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.setTouchMode(!on),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, on ? 10 : 6, 4, on ? 10 : 6),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 22, color: on ? pal.accent : pal.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Touch mode',
                      style: TextStyle(color: on ? pal.text : pal.muted, fontWeight: FontWeight.w500)),
                ),
                Switch(value: on, onChanged: controller.setTouchMode),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet "Support Lectern" link with a heart. With one tip link it opens
/// it straight away; with several it offers a small menu.
class _SupportLink extends StatelessWidget {
  const _SupportLink();

  @override
  Widget build(BuildContext context) {
    final tips = [for (final t in AppInfo.tips) if (t.$2.isNotEmpty) t];
    if (tips.isEmpty) return const SizedBox.shrink();

    Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

    if (tips.length == 1) {
      return _NavItem(
        icon: Icons.favorite_rounded,
        label: 'Support Lectern',
        dense: true,
        selected: false,
        onTap: () => open(tips.first.$2),
      );
    }
    return MenuAnchor(
      alignmentOffset: const Offset(12, 0),
      menuChildren: [
        for (final (label, url) in tips)
          MenuItemButton(
            leadingIcon: Icon(Icons.favorite_rounded, size: 18, color: context.colors.accent),
            onPressed: () => open(url),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(label),
            ),
          ),
      ],
      builder: (context, menu, _) => _NavItem(
        icon: Icons.favorite_rounded,
        label: 'Support Lectern',
        dense: true,
        selected: false,
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
