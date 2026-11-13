/// The "当前播放" bottom sheet: the live queue, recently played songs, row
/// removal / drag reordering and the two bottom mode pills.
///
/// Layout follows a mobile player's playlist: drag handle, two tabs with a
/// count, a "来自：…" line, full-width rows with a close button and a drag
/// handle, and two large rounded buttons floating over the end of the list.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';

enum QueueTab { current, history }

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
  const QueueSheet({super.key, this.initialTab = QueueTab.current});

  final QueueTab initialTab;

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
              child: Column(
                children: [
                  _handle(),
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
              ),
            ),
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 82),
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              icon: playModeIcon(model.playMode),
              label: playModeLabel(model.playMode),
              tooltip: '切换播放模式',
              onTap: model.cyclePlayMode,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Pill(
              icon: Icons.my_location_rounded,
              label: '回到当前',
              tooltip: '定位到正在播放的歌曲',
              onTap: _scrollToCurrent,
            ),
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

/// One of the two large rounded buttons floating over the queue.
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
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: Mf.surfaceAlt.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Mf.textSoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Mf.textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
