/// Shared presentation pieces: cover art and the track row used by every list.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import 'theme.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.size,
    this.radius = 6,
    this.circular = false,
    this.iconSize,
  });

  final String? url;
  final double? size;
  final double radius;
  final bool circular;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final shape = circular
        ? const BorderRadius.all(Radius.circular(999))
        : BorderRadius.all(Radius.circular(radius));
    final fallback = Container(
      color: Fn.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        Icons.album_outlined,
        size: iconSize ?? (size == null ? 28 : size! * 0.42),
        color: Fn.faint,
      ),
    );

    final image = url == null || url!.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 140),
            placeholder: (_, _) => Container(color: Fn.surfaceAlt),
            errorWidget: (_, _, _) => fallback,
          );

    return ClipRRect(
      borderRadius: shape,
      child: size == null
          ? image
          : SizedBox(width: size, height: size, child: image),
    );
  }
}

class TrackRow extends StatefulWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.onTap,
    this.active = false,
    this.playing = false,
    this.showAlbum = true,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;
  final bool active;
  final bool playing;
  final bool showAlbum;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? Fn.raised.withValues(alpha: 0.7) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: accent
                    ? Icon(
                        widget.playing
                            ? Icons.volume_up_rounded
                            : Icons.play_arrow_rounded,
                        size: 15,
                        color: Fn.accent,
                      )
                    : Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                          color: Fn.faint,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent ? Fn.accent : Fn.text,
                        fontSize: 13.5,
                        fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.track.artistLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Fn.faint, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (widget.showAlbum)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      widget.track.album?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Fn.muted, fontSize: 12),
                    ),
                  ),
                ),
              if (widget.track.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.favorite, size: 13, color: Fn.accent),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 40,
                child: Text(
                  widget.track.durationLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Fn.faint,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
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

/// Centred hint used by empty listings and search misses.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: Fn.border),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: Fn.muted, fontSize: 13.5)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              style: const TextStyle(color: Fn.faint, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class FnSpinner extends StatelessWidget {
  const FnSpinner({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        color: Fn.muted,
      ),
    );
  }
}

/// Section label above a listing, matching the Compose build.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Fn.faint,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }
}
