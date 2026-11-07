/// Device picker and remote control for casting.
///
/// Opened from the cast button in the transport: before a session it lists
/// discovered DLNA renderers, after connecting it becomes the remote —
/// progress, play/pause, queue stepping, volume and disconnect.
library;

import 'dart:async';

import 'package:dart_cast/dart_cast.dart' show SessionState;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart' show formatClock;
import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart' show MfSpinner;

/// Opens the cast sheet and kicks off a fresh device scan.
Future<void> showCastSheet(BuildContext context) {
  final model = context.read<AppModel>();
  unawaited(model.startCastScan());
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Mf.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      side: BorderSide(color: Mf.border),
    ),
    builder: (_) => ChangeNotifierProvider<AppModel>.value(
      value: model,
      child: const CastSheet(),
    ),
  );
}

class CastSheet extends StatelessWidget {
  const CastSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: model.casting
            ? const _CastRemote()
            : const _CastDevicePicker(),
      ),
    );
  }
}

// ---- Device picker ----------------------------------------------------------

class _CastDevicePicker extends StatelessWidget {
  const _CastDevicePicker();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHeader(title: '投屏', showRescan: true),
        const SizedBox(height: 4),
        if (model.castScanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MfSpinner(size: 14),
                  SizedBox(width: 10),
                  Text(
                    '正在搜索局域网内的投屏设备…',
                    style: TextStyle(color: Mf.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else if (model.castDevices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: Text(
                model.castScanDone
                    ? '未发现投屏设备，请确认设备与本机在同一局域网'
                    : '尚未扫描',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Mf.muted, fontSize: 13),
              ),
            ),
          )
        else
          for (final device in model.castDevices)
            _DeviceRow(
              name: device.name,
              subtitle: 'DLNA · ${device.address.address}',
              onTap: () => context.read<AppModel>().connectCast(device),
            ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.showRescan = false});

  final String title;
  final bool showRescan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cast_rounded, size: 18, color: Mf.textSoft),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: Mf.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (showRescan)
          MfIconButton(
            icon: Icons.refresh_rounded,
            size: 28,
            glyph: 16,
            tooltip: '重新扫描',
            onTap: () => context.read<AppModel>().startCastScan(),
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Mf.accentWash,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.speaker_rounded,
                size: 17,
                color: Mf.accentHover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Mf.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Mf.faint, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Mf.faint),
          ],
        ),
      ),
    );
  }
}

// ---- Remote -----------------------------------------------------------------

class _CastRemote extends StatelessWidget {
  const _CastRemote();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final state = model.castState;
    final playing =
        state == SessionState.playing ||
        state == SessionState.buffering ||
        state == SessionState.loading;
    final stateLabel = switch (state) {
      SessionState.playing => '正在播放',
      SessionState.buffering => '缓冲中',
      SessionState.loading => '加载中',
      SessionState.paused => '已暂停',
      SessionState.idle => '已停止',
      _ => '已连接',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Mf.accentHover, Mf.accent],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.cast_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.castDevice?.name ?? '投屏设备',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Mf.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stateLabel,
                    style: const TextStyle(color: Mf.faint, fontSize: 11),
                  ),
                ],
              ),
            ),
            MfIconButton(
              icon: Icons.link_off_rounded,
              size: 30,
              glyph: 16,
              tooltip: '断开投屏',
              onTap: () {
                context.read<AppModel>().disconnectCast();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          model.currentTrack?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Mf.textSoft, fontSize: 13),
        ),
        const SizedBox(height: 8),
        const _CastProgress(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MfIconButton(
              icon: Icons.skip_previous_rounded,
              size: 34,
              glyph: 22,
              tooltip: '上一首',
              onTap: model.previous,
            ),
            const SizedBox(width: 10),
            MfPrimaryButton(
              label: playing ? '暂停' : '播放',
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onTap: model.togglePlay,
            ),
            const SizedBox(width: 10),
            MfIconButton(
              icon: Icons.skip_next_rounded,
              size: 34,
              glyph: 22,
              tooltip: '下一首',
              onTap: model.next,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.volume_up_rounded, size: 16, color: Mf.faint),
            const SizedBox(width: 8),
            Expanded(
              child: MfScrubber(
                fraction: model.castVolume,
                thumbColor: Mf.textSoft,
                activeColor: Mf.muted,
                onScrub: model.setVolume,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Remote position bar. The renderer reports position once a second through
/// the session stream; dragging previews locally and seeks on release.
class _CastProgress extends StatefulWidget {
  const _CastProgress();

  @override
  State<_CastProgress> createState() => _CastProgressState();
}

class _CastProgressState extends State<_CastProgress> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final session = model.castSession;
    if (session == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: session.positionStream,
      initialData: session.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = session.duration;
        final seconds = duration.inMilliseconds / 1000.0;
        final fraction = _preview ??
            (seconds > 0
                ? (position.inMilliseconds / 1000.0 / seconds).clamp(0.0, 1.0)
                : 0.0);
        return Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    formatClock(_preview != null
                        ? _preview! * seconds
                        : position.inMilliseconds / 1000.0),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Mf.faint,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MfScrubber(
                    fraction: fraction,
                    onScrub: (value) => setState(() => _preview = value),
                    onCommit: () {
                      final target = _preview;
                      setState(() => _preview = null);
                      if (target != null && seconds > 0) {
                        model.seek(Duration(
                          milliseconds: (target * seconds * 1000).round(),
                        ));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 38,
                  child: Text(
                    formatClock(seconds),
                    style: const TextStyle(
                      color: Mf.faint,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
