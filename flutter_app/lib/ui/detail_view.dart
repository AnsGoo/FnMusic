/// Album and playlist detail: a cover header plus its track list.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

class DetailView extends StatefulWidget {
  const DetailView({super.key, required this.detail, required this.wide});

  final Detail detail;
  final bool wide;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final detail = widget.detail;
    final audio = model.player.state.value;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.wide ? 24 : 16,
            18,
            widget.wide ? 24 : 16,
            14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FnIconButton(
                icon: Icons.arrow_back,
                size: 30,
                glyph: 17,
                tooltip: '返回',
                onTap: model.back,
              ),
              const SizedBox(width: 14),
              CoverImage(
                url: model.coverUrl(detail.coverId),
                size: widget.wide ? 150 : 104,
                radius: 10,
              ),
              SizedBox(width: widget.wide ? 20 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(detail.isAlbum ? '专辑' : '歌单'),
                    const SizedBox(height: 6),
                    Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Fn.text,
                        fontSize: widget.wide ? 26 : 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Fn.muted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FnPrimaryButton(
                          label: '播放全部',
                          height: 34,
                          onTap: detail.tracks.isEmpty
                              ? null
                              : () => model.playFrom(detail.tracks, 0),
                          enabled: detail.tracks.isNotEmpty,
                        ),
                        const SizedBox(width: 10),
                        if (detail.loading) const FnSpinner(size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Fn.border),
        Expanded(
          child: detail.loading && detail.tracks.isEmpty
              ? const Center(child: FnSpinner())
              : detail.tracks.isEmpty
              ? EmptyState(
                  icon: Icons.music_note_outlined,
                  title: detail.isAlbum ? '这张专辑还没有曲目' : '这个歌单还没有曲目',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: detail.tracks.length,
                  itemBuilder: (context, index) {
                    final track = detail.tracks[index];
                    return TrackRow(
                      track: track,
                      index: index,
                      active: audio.trackId == track.id,
                      playing: audio.trackId == track.id && audio.playing,
                      showAlbum: false,
                      onTap: () => model.playFrom(detail.tracks, index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
