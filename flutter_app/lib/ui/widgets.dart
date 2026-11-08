/// Shared presentation pieces: cover art and the track row used by every list.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/fn_connect.dart';
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
    this.onFailed,
  });

  final String? url;
  final double? size;
  final double radius;
  final bool circular;
  final double? iconSize;

  /// Called when the remote image cannot be decoded — the server answers
  /// missing art with an XML error document, so this is the usual signal to
  /// retry against a different cover id.
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) {
    final shape = circular
        ? const BorderRadius.all(Radius.circular(999))
        : BorderRadius.all(Radius.circular(radius));
    // The app's vinyl logo doubles as the "no art" placeholder. Its dark disc
    // melts into the dark surface (same trick as the splash) while the orange
    // label keeps it recognizable.
    final logoSize = iconSize ?? (size == null ? null : size! * 0.55);
    final fallback = Container(
      color: Mf.surfaceAlt,
      alignment: Alignment.center,
      padding: logoSize == null
          ? EdgeInsets.zero
          : EdgeInsets.all(logoSize * 0.25),
      child: Opacity(
        opacity: 0.9,
        child: Image.asset(
          'assets/logo.png',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
        ),
      ),
    );

    final image = url == null || url!.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 140),
            // Feiniu relay links (Fn Connect) expect their cookie on cover
            // requests; other servers never see it.
            httpHeaders: fnRelayHeadersFor(url!),
            placeholder: (_, _) => Container(color: Mf.surfaceAlt),
            errorWidget: (_, _, _) => fallback,
            errorListener: onFailed == null ? null : (_) => onFailed!(),
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
    this.coverUrl,
    this.fallbackCoverUrl,
    this.showCover = true,
    this.active = false,
    this.playing = false,
    this.showAlbum = true,
    this.onToggleFavorite,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;

  /// When provided, a tappable heart sits before the duration: filled accent
  /// when the song is starred, an outline when not. Without it the row keeps
  /// the old passive heart that only marks already-favourite songs.
  final VoidCallback? onToggleFavorite;

  /// Artwork carried by the song itself; servers only answer some of these.
  final String? coverUrl;

  /// Album-level artwork, used when [coverUrl] comes back empty.
  final String? fallbackCoverUrl;
  final bool showCover;
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
          height: widget.showCover ? 72 : 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? Mf.raised.withValues(alpha: 0.7) : Colors.transparent,
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
                        color: Mf.accent,
                      )
                    : Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                          color: Mf.faint,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              if (widget.showCover) ...[
                _TrackThumb(
                  url: widget.coverUrl,
                  fallbackUrl: widget.fallbackCoverUrl,
                  hovered: _hovered,
                  active: accent,
                ),
                const SizedBox(width: 12),
              ],
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
                        color: accent ? Mf.accent : Mf.text,
                        fontSize: 13.5,
                        fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.track.artistLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Mf.faint, fontSize: 11.5),
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
                      style: const TextStyle(color: Mf.muted, fontSize: 12),
                    ),
                  ),
                ),
              if (widget.onToggleFavorite != null)
                _FavoriteButton(
                  favorite: widget.track.isFavorite,
                  onTap: widget.onToggleFavorite!,
                )
              else if (widget.track.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.favorite, size: 13, color: Mf.accent),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 40,
                child: Text(
                  widget.track.durationLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Mf.faint,
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

/// Tappable heart at the tail of a track row. Owns its own hit target so a
/// tap never reaches the row's play handler.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.favorite, required this.onTap});

  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: favorite ? '取消收藏' : '收藏',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Icon(
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 16,
            color: favorite ? Mf.accent : Mf.faint,
          ),
        ),
      ),
    );
  }
}

/// 56px cover used at the head of a track row. Hovering dims the art and
/// reveals a play glyph; the current track keeps a thin accent ring instead.
///
/// Music Free tags most songs with their own artwork but only stores a file
/// for some of them, so a failed load quietly falls back to the album cover.
class _TrackThumb extends StatefulWidget {
  const _TrackThumb({
    required this.url,
    required this.fallbackUrl,
    required this.hovered,
    required this.active,
  });

  final String? url;
  final String? fallbackUrl;
  final bool hovered;
  final bool active;

  @override
  State<_TrackThumb> createState() => _TrackThumbState();
}

class _TrackThumbState extends State<_TrackThumb> {
  static const _size = 56.0;
  static const _radius = 8.0;

  bool _songArtFailed = false;

  String? get _url {
    final song = widget.url;
    if (!_songArtFailed && song != null && song.isNotEmpty) return song;
    final album = widget.fallbackUrl;
    return album == null || album.isEmpty ? null : album;
  }

  @override
  void didUpdateWidget(covariant _TrackThumb old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _songArtFailed = false;
  }

  void _onFailed() {
    // The image load may outlive this row (fast scrolling recycles rows);
    // ignore late failures from the discarded image stream.
    if (!mounted || _songArtFailed || widget.fallbackUrl == null) return;
    setState(() => _songArtFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(
            url: _url,
            radius: _radius,
            iconSize: 22,
            onFailed: _onFailed,
          ),
          if (widget.hovered)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Mf.bg.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 26,
                  color: Mf.cream,
                ),
              ),
            )
          else if (widget.active)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(color: Mf.accent, width: 1.2),
                ),
              ),
            ),
        ],
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
          Icon(icon, size: 34, color: Mf.border),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: Mf.muted, fontSize: 13.5)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              style: const TextStyle(color: Mf.faint, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class MfSpinner extends StatelessWidget {
  const MfSpinner({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        color: Mf.muted,
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
        color: Mf.faint,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }
}
