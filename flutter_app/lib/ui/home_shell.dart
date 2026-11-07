/// The signed-in shell: navigation rail, library pane, transport and lyrics.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import 'browse_view.dart';
import 'controls.dart';
import 'lyrics_view.dart';
import 'player_bar.dart';
import 'theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _shownError;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    _surfaceError(model);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: Mf.bg,
          body: wide ? _desktop(model) : _compact(model),
        );
      },
    );
  }

  void _surfaceError(AppModel model) {
    final error = model.error;
    if (error == null) {
      _shownError = null;
      return;
    }
    if (error == _shownError) return;
    _shownError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Mf.raised,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      model.consumeError();
    });
  }

  Widget _desktop(AppModel model) {
    return Row(
      children: [
        _Sidebar(model: model),
        const VerticalDivider(width: 1, thickness: 1, color: Mf.border),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: BrowseView()),
                    if (model.lyricsVisible)
                      const Positioned.fill(child: LyricsPanel()),
                  ],
                ),
              ),
              PlayerBar(wide: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compact(AppModel model) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: BrowseView()),
              if (model.lyricsVisible)
                const Positioned.fill(child: LyricsPanel()),
            ],
          ),
        ),
        PlayerBar(wide: false),
        _BottomNav(model: model),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      color: Mf.surface,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 20),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 30,
                    height: 30,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 9),
                const Text(
                  '乐记',
                  style: TextStyle(
                    color: Mf.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          for (final section in Section.values)
            _NavItem(
              section: section,
              selected: model.section == section && model.detail == null,
              onTap: () => model.select(section),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Mf.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.session?.username ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Mf.textSoft, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.session?.hostLabel ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Mf.faint, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                MfIconButton(
                  icon: Icons.logout_rounded,
                  size: 26,
                  glyph: 15,
                  tooltip: '退出登录',
                  onTap: model.logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

/// The rail and the compact tab bar show the same glyph per section.
IconData _sectionIcon(Section section) => switch (section) {
  Section.tracks => Icons.library_music_outlined,
  Section.albums => Icons.album_outlined,
  Section.artists => Icons.person_outline,
  Section.playlists => Icons.queue_music_outlined,
  Section.favorites => Icons.favorite_border,
};

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected
        ? Mf.accent
        : (_hovered ? Mf.text : Mf.muted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Mf.accentWash
                : (_hovered ? Mf.raised.withValues(alpha: 0.6) : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(_sectionIcon(widget.section), size: 17, color: color),
              const SizedBox(width: 10),
              Text(
                widget.section.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Mf.surface,
        border: Border(top: BorderSide(color: Mf.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final section in Section.values)
            _BottomNavItem(
              section: section,
              selected: model.section == section && model.detail == null,
              onTap: () => model.select(section),
            ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Mf.accent : Mf.muted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sectionIcon(section), size: 19, color: color),
              const SizedBox(height: 3),
              Text(
                section.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
