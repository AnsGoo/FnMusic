/// The signed-in shell: navigation rail, library pane, transport and lyrics.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import 'browse_view.dart';
import 'controls.dart';
import 'lyrics_view.dart';
import 'now_playing.dart';
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
          // A phone has no room for a rail, so the same sidebar slides in from
          // the left edge; the tab bar that used to sit under the transport is
          // gone.
          drawer: wide ? null : const _MobileDrawer(),
          drawerScrimColor: const Color(0xD9060404),
          // A phone swipe rarely starts within Flutter's default 20dp edge,
          // so widen the grab strip without covering the whole screen.
          drawerEdgeDragWidth: wide ? null : 56,
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

  /// The player page owns its own transport, so the shell hides the bottom
  /// bar and the tab bar while it is open instead of stacking two of them.
  bool _showingPlayer(AppModel model) =>
      model.nowPlayingVisible && model.currentTrack != null;

  Widget _desktop(AppModel model) {
    if (_showingPlayer(model)) {
      return const NowPlayingPage();
    }
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
    if (_showingPlayer(model)) {
      return const NowPlayingPage();
    }
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
      ],
    );
  }
}

/// The desktop rail on a phone: opened by an edge swipe or the toolbar's menu
/// button, with the same logo, section list and account footer.
class _MobileDrawer extends StatelessWidget {
  const _MobileDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 292,
      backgroundColor: Mf.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(14)),
      ),
      child: SafeArea(
        right: false,
        child: _Sidebar(
          model: context.watch<AppModel>(),
          width: null,
          roomy: true,
          onNavigate: () => Scaffold.maybeOf(context)?.closeDrawer(),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.model,
    this.width = 208,
    this.roomy = false,
    this.onNavigate,
  });

  final AppModel model;
  final double? width;
  final bool roomy;

  /// The drawer closes itself after a section is picked.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: Mf.surface,
      padding: EdgeInsets.fromLTRB(
        roomy ? 18 : 14,
        roomy ? 24 : 18,
        roomy ? 18 : 14,
        roomy ? 20 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 6, bottom: roomy ? 24 : 20),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/logo.png',
                    width: roomy ? 34 : 30,
                    height: roomy ? 34 : 30,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '乐记',
                  style: TextStyle(
                    color: Mf.text,
                    fontSize: roomy ? 16 : 14,
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
              roomy: roomy,
              onTap: () {
                // A section picked from the drawer returns to the library,
                // even if the full-screen player was open.
                model.closeNowPlaying();
                model.select(section);
                onNavigate?.call();
              },
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
    this.roomy = false,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;
  final bool roomy;

  @override
  State<_NavItem> createState() => _NavItemState();
}

/// The rail and the phone drawer share the same glyph per section.
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
          margin: EdgeInsets.only(bottom: widget.roomy ? 6 : 3),
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: widget.roomy ? 14 : 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Mf.accentWash
                : (_hovered ? Mf.raised.withValues(alpha: 0.6) : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                _sectionIcon(widget.section),
                size: widget.roomy ? 20 : 17,
                color: color,
              ),
              SizedBox(width: widget.roomy ? 14 : 10),
              Text(
                widget.section.label,
                style: TextStyle(
                  color: color,
                  fontSize: widget.roomy ? 15 : 13,
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

