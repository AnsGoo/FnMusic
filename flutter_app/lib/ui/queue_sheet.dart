/// The "当前播放" queue: the live queue, recently played songs, row removal /
/// drag reordering and the compact bottom mode chips.
///
/// Two shapes share one body: a mobile bottom sheet (drag handle, rounded top,
/// modal scrim) and a docked right-hand panel on desktop (title bar + close,
/// no scrim, the library stays visible and interactive beside it).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';

enum QueueTab { current, history }

/// Windows at least this wide get the docked panel. Matches HomeShell's
/// desktop layout breakpoint so the two never disagree about the shape.
const double kDockedQueueBreakpoint = 900;

/// Single entry point for every "播放列表" button.
///
/// On a narrow window the mobile bottom sheet is still the right shape. On a
/// desktop window the queue docks on the right: from the transport it toggles
/// the panel, while from the full-window player ([fromFullPlayer]) it first
/// returns to the library — that page covers the shell entirely, so a docked
/// panel behind it would be invisible.
void showQueue(BuildContext context, {bool fromFullPlayer = false}) {
  if (MediaQuery.sizeOf(context).width < kDockedQueueBreakpoint) {
    unawaited(showQueueSheet(context));
    return;
  }
  final model = context.read<AppModel>();
  if (fromFullPlayer) {
    model.closeNowPlaying();
    model.openQueuePanel();
  } else {
    model.toggleQueuePanel();
  }
}

/// Shared with the full player and the mini bar so the mode glyph never
/// disagrees with the queue sheet.
IconData playModeIcon(PlayMode mode) => switch (mode) {
  PlayMode.sequential => Icons.playlist_play_rounded,
  PlayMode.loopAll => Icons.repeat_rounded,
  PlayMode.loopOne => Icons.repeat_one_rounded,
  PlayMode.shuffle => Icons.shuffle_rounded,
};

String playModeLabel(PlayMode mode) => switch (mode) {
  PlayMode.sequential => '顺序播放',
  PlayMode.loopAll => '列表循环',
  PlayMode.loopOne => '单曲循环',
  PlayMode.shuffle => '随机播放',
};

Future<void> showQueueSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB3000000),
    builder: (_) => const QueueSheet(),
  );
}

class QueueSheet extends StatefulWidget {
  const QueueSheet({
    super.key,
    this.initialTab = QueueTab.current,
    this.docked = false,
  });

  final QueueTab initialTab;

  /// Desktop: render as a full-height right-hand panel with a title bar and a
  /// close button instead of a rounded, bottom-aligned modal sheet.
  final bool docked;

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  /// Rows are a fixed height, which lets "回到当前" jump straight to the
  /// current index without a per-item GlobalKey (list rows are lazily built).
  static const _rowHeight = 62.0;

  late QueueTab _tab = widget.initialTab;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    // One body, two shells: the desktop panel keeps everything except the
    // drag handle and the rounded / bottom-aligned frame.
    final body = Column(
      children: [
        if (widget.docked) _panelHeader() else _handle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: _tabs(model),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: _source(model),
        ),
        Expanded(child: _list(model)),
      ],
    );
    if (widget.docked) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Mf.bg,
          border: Border(left: BorderSide(color: Mf.border)),
        ),
        child: body,
      );
    }
    final height = (MediaQuery.sizeOf(context).height * 0.74).clamp(
      380.0,
      680.0,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Mf.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop title bar: a phone-style drag handle makes no sense on a panel
  /// that cannot be dragged away, so it becomes an explicit close control.
  Widget _panelHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
      child: Row(
        children: [
          const Text(
            '播放队列',
            style: TextStyle(
              color: Mf.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          MfIconButton(
            icon: Icons.close_rounded,
            size: 30,
            glyph: 18,
            tooltip: '关闭播放队列',
            onTap: () => context.read<AppModel>().closeQueuePanel(),
          ),
        ],
      ),
    );
  }

  Widget _handle() => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Mf.raised,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _tabs(AppModel model) {
    return Row(
      children: [
        _tabLabel(
          '当前播放',
          count: model.queue.length,
          selected: _tab == QueueTab.current,
          onTap: () => setState(() => _tab = QueueTab.current),
        ),
        const SizedBox(width: 22),
        _tabLabel(
          '历史播放',
          selected: _tab == QueueTab.history,
          onTap: () => setState(() => _tab = QueueTab.history),
        ),
        const Spacer(),
        MfIconButton(
          icon: Icons.my_location_rounded,
          size: 30,
          glyph: 18,
          tooltip: '回到当前',
          onTap: _scrollToCurrent,
        ),
        MfIconButton(
          icon: Icons.delete_outline_rounded,
          size: 30,
          glyph: 18,
          tooltip: _tab == QueueTab.current ? '清空播放列表' : '清空历史',
          onTap: () {
            if (_tab == QueueTab.current) {
              model.clearQueue();
            } else {
              model.clearHistory();
            }
          },
        ),
      ],
    );
  }

  Widget _tabLabel(
    String label, {
    int? count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? Mf.text : Mf.muted,
              fontSize: 17,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (count != null && count > 0)
            Padding(
              padding: const EdgeInsets.only(left: 3, top: 2),
              child: Text(
                '$count',
                style: const TextStyle(color: Mf.muted, fontSize: 10.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _source(AppModel model) {
    final text = _tab == QueueTab.history
        ? '最近播放 ${model.history.length} 首'
        : '来自：${model.queueSource ?? '播放队列'}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Mf.muted, fontSize: 12),
      ),
    );
  }

  Widget _list(AppModel model) {
    final history = _tab == QueueTab.history;
    final items = history ? model.history : model.queue;
    if (items.isEmpty) {
      return Center(
        child: Text(
          history ? '还没有播放记录' : '播放列表是空的',
          style: const TextStyle(color: Mf.muted, fontSize: 13),
        ),
      );
    }
    return Stack(
      children: [
        ReorderableListView.builder(
          scrollController: _scroll,
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 62),
          itemCount: items.length,
          // Keep the classic callback: it is still honoured by older Flutter
          // SDKs (the macOS build machine) and reports the *insertion* index,
          // which is exactly what AppModel.reorderQueue expects. The newer
          // onReorderItem pre-adjusts newIndex and would shift every drag.
          // ignore: deprecated_member_use
          onReorder: history ? (_, _) {} : model.reorderQueue,
          itemBuilder: (context, index) =>
              _row(model, items, index, history),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _footer(model),
        ),
      ],
    );
  }

  Widget _row(AppModel model, List<Track> items, int index, bool history) {
    final track = items[index];
    final active = !history && index == model.queueIndex;
    return Container(
      key: ValueKey('${history ? 'history' : 'queue'}-$index-${track.id}'),
      height: _rowHeight,
      decoration: BoxDecoration(
        color: active
            ? Mf.surfaceAlt.withValues(alpha: 0.9)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          if (active)
            const Padding(
              padding: EdgeInsets.only(left: 10, right: 8),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 17,
                color: Mf.accent,
              ),
            )
          else
            const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                if (history) {
                  await model.playFrom(items, index, source: '历史播放');
                } else {
                  await model.playQueueAt(index);
                }
                if (mounted) setState(() => _tab = QueueTab.current);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: track.title,
                        style: TextStyle(
                          color: active ? Mf.accentHover : Mf.text,
                          fontSize: 14.5,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      TextSpan(
                        text: ' · ${track.artistLine}',
                        style: TextStyle(
                          color: active
                              ? Mf.accent.withValues(alpha: 0.85)
                              : Mf.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (!history) ...[
            MfIconButton(
              icon: Icons.close_rounded,
              size: 30,
              glyph: 16,
              tooltip: '从列表移除',
              onTap: () => model.removeFromQueue(index),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 18,
                  color: Mf.muted,
                ),
              ),
            ),
          ] else
            const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _footer(AppModel model) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00131010), Mf.bg, Mf.bg],
          stops: [0, 0.38, 1],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Pill(
            icon: playModeIcon(model.playMode),
            label: playModeLabel(model.playMode),
            tooltip: '切换播放模式',
            onTap: model.cyclePlayMode,
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.my_location_rounded,
            label: '回到当前',
            tooltip: '定位到正在播放的歌曲',
            onTap: _scrollToCurrent,
          ),
        ],
      ),
    );
  }

  void _scrollToCurrent() {
    setState(() => _tab = QueueTab.current);
    final index = context.read<AppModel>().queueIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final target = (index * _rowHeight - 120).clamp(0.0, max).toDouble();
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

/// One of the two compact chips floating over the queue.
///
/// Both shapes (docked panel and phone sheet) share this widget. They used to
/// be 46px-high pills splitting the full panel width, which dominated the
/// 300-360px desktop sidebar. Now they hug their label: a 30px visual chip
/// inside a 38px tap target, centred as a pair on both layouts.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Center(
            child: Container(
              key: ValueKey('queue-pill-$label'),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: Mf.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Mf.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: Mf.muted),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Mf.textSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
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
