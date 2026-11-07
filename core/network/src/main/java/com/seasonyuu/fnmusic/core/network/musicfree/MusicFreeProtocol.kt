package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.network.AlbumDto
import com.seasonyuu.fnmusic.core.network.ArtistDto
import com.seasonyuu.fnmusic.core.network.AudioSpecDto
import com.seasonyuu.fnmusic.core.network.PlaylistDto
import com.seasonyuu.fnmusic.core.network.TrackDto
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Loose readers for Music Free JSON. The server returns two shapes: a
 * `subsonic-response` envelope (most /rest endpoints) and bare JSON objects
 * (login and play-history). Field names also differ between the OpenSubsonic
 * Child representation and the server's own compact song map, so both are
 * normalised here instead of binding rigid DTO classes.
 */
internal fun JsonObject.text(vararg names: String): String? =
    names.firstNotNullOfOrNull { name ->
        (get(name) as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
    }

internal fun JsonObject.number(vararg names: String): Double? =
    names.firstNotNullOfOrNull { name ->
        val element = get(name) as? JsonPrimitive ?: return@firstNotNullOfOrNull null
        element.doubleOrNull ?: element.contentOrNull?.toDoubleOrNull()
    }

internal fun JsonObject.integer(vararg names: String): Int? = number(*names)?.toInt()

internal fun JsonObject.longValue(vararg names: String): Long? =
    names.firstNotNullOfOrNull { name ->
        val element = get(name) as? JsonPrimitive ?: return@firstNotNullOfOrNull null
        element.longOrNull ?: element.contentOrNull?.toLongOrNull()
    }

internal fun JsonObject.flag(vararg names: String): Boolean =
    names.any { name -> (get(name) as? JsonPrimitive)?.booleanOrNull == true }

internal fun JsonObject.child(vararg names: String): JsonObject? =
    names.firstNotNullOfOrNull { name -> get(name) as? JsonObject }

internal fun JsonObject.list(vararg names: String): JsonArray? =
    names.firstNotNullOfOrNull { name -> get(name) as? JsonArray }

internal fun JsonElement?.asObjects(): List<JsonObject> =
    (this as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }

/** Music Free reports duration in seconds; fnOS TrackDto expects milliseconds. */
internal fun JsonObject.durationMs(): Double = (number("duration") ?: 0.0) * 1_000.0

internal fun JsonObject.toArtistDto(): ArtistDto = ArtistDto(
    guid = text("id", "artistId", "guid") ?: "",
    name = text("name", "artist") ?: "",
    coverId = text("coverArt", "coverId"),
    // /rest/api/v1/artists only exposes albumCount. Some compatible servers
    // and search3 results include a song count, so read it when available.
    trackCount = integer("songCount", "trackCount") ?: 0,
    albumCount = integer("albumCount") ?: 0,
)

/** getArtist.view carries a song count on each album; sum it for the artist header. */
internal fun JsonObject.artistTrackCount(): Int =
    list("album").asObjects().sumOf { album -> album.integer("songCount", "trackCount") ?: 0 }

private fun JsonObject.embeddedArtist(): List<ArtistDto> {
    // The library list sends "artist" as a string, while play history embeds a
    // full artist object under the same key. Accept both shapes.
    val nested = get("artist") as? JsonObject
    val name = text("artist") ?: nested?.text("name")
    val id = text("artistId") ?: nested?.text("id")
    return when {
        name.isNullOrBlank() -> emptyList()
        else -> listOf(ArtistDto(guid = id ?: name, name = name))
    }
}

private fun JsonObject.embeddedAlbum(): AlbumDto? {
    // Same story as embeddedArtist: string in the library list, object in history.
    val nested = get("album") as? JsonObject
    val name = text("album") ?: nested?.text("name") ?: return null
    val id = text("albumId") ?: nested?.text("id") ?: name
    return AlbumDto(guid = id, name = name, coverId = text("coverArt") ?: nested?.text("coverArt"))
}

internal fun JsonObject.toTrackDto(): TrackDto {
    val id = text("id", "guid") ?: ""
    // Navidrome-shaped rows (/api/song) only flag `hasCoverArt` and omit the
    // cover id entirely; getCoverArt accepts an album id, so fall back to it.
    val cover = text("coverArt", "coverId") ?: text("albumId")
    val bitrate = longValue("bitRate", "bitrate")
    val size = longValue("size")
    val durationMs = durationMs()
    return TrackDto(
        guid = id,
        title = text("title", "name") ?: "",
        artists = embeddedArtist(),
        album = embeddedAlbum(),
        audioSpec = AudioSpecDto(
            // Play-history songs expose the container as "Format", not "suffix".
            format = text("suffix", "format", "Format"),
            size = size,
            duration = durationMs.takeIf { it > 0 },
            bitrate = bitrate,
            path = text("path"),
        ),
        coverId = cover,
        // TrackDto.toDomain() divides duration by 1000, so pass milliseconds here.
        duration = durationMs,
        isFavorite = containsKey("starred") || flag("isFavorite"),
        year = integer("year"),
        trackNo = integer("track", "trackNo", "trackNumber"),
        discNo = integer("discNumber", "disc", "discNo"),
    )
}

internal fun JsonObject.toAlbumDto(): AlbumDto = AlbumDto(
    guid = text("id", "guid") ?: "",
    name = text("name", "album", "title") ?: "",
    artists = embeddedArtist(),
    coverId = text("coverArt", "coverId"),
    releaseDate = text("year"),
    trackCount = integer("songCount", "trackCount") ?: 0,
)

internal fun JsonObject.toPlaylistDto(): PlaylistDto = PlaylistDto(
    guid = text("id", "guid") ?: "",
    name = text("name", "title") ?: "",
    coverId = text("coverArt", "coverId"),
    trackCount = integer("songCount", "trackCount"),
)

/** Play-history entries carry a nested song; fall back to the entry itself. */
internal fun JsonObject.historyTrackDto(): TrackDto =
    (child("Song", "song") ?: this).toTrackDto()

internal fun JsonObject.containsUsableTrackId(): Boolean {
    val id = text("id", "guid") ?: return false
    // Music Free marks unmatched playlist entries with a `pls-` stub id.
    return !id.startsWith("pls-")
}
