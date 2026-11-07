package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.model.Genre
import com.seasonyuu.fnmusic.core.network.ApiEnvelope
import com.seasonyuu.fnmusic.core.network.AlbumDto
import com.seasonyuu.fnmusic.core.network.ArtistDto
import com.seasonyuu.fnmusic.core.network.AudioSpecDto
import com.seasonyuu.fnmusic.core.network.ChangePasswordRequest
import com.seasonyuu.fnmusic.core.network.EventReportRequest
import com.seasonyuu.fnmusic.core.network.FavoriteRequest
import com.seasonyuu.fnmusic.core.network.LyricDataDto
import com.seasonyuu.fnmusic.core.network.LoginData
import com.seasonyuu.fnmusic.core.network.LoginRequest
import com.seasonyuu.fnmusic.core.network.MusicApi
import com.seasonyuu.fnmusic.core.network.PageDto
import com.seasonyuu.fnmusic.core.network.PlaylistCoverUploadDto
import com.seasonyuu.fnmusic.core.network.PlaylistCreateRequest
import com.seasonyuu.fnmusic.core.network.PlaylistDto
import com.seasonyuu.fnmusic.core.network.PlaylistEditRequest
import com.seasonyuu.fnmusic.core.network.PlaylistGuidRequest
import com.seasonyuu.fnmusic.core.network.PlaylistTracksRequest
import com.seasonyuu.fnmusic.core.network.RoamDto
import com.seasonyuu.fnmusic.core.network.SearchSuggestionsDto
import com.seasonyuu.fnmusic.core.network.SuggestionGroupDto
import com.seasonyuu.fnmusic.core.network.SystemConfigDto
import com.seasonyuu.fnmusic.core.network.TotalDto
import com.seasonyuu.fnmusic.core.network.TrackDto
import com.seasonyuu.fnmusic.core.network.TrackMetadataDto
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.MultipartBody

/**
 * Neutral fallback for fnOS-only capabilities (administration, transcoding,
 * folder authorization, metadata editing, roaming). Returning empty successes
 * keeps the shared UI in its normal empty state instead of throwing, so the
 * six supported library domains can reuse the existing screens unchanged.
 */
internal open class UnsupportedMusicApi : MusicApi {
    protected fun <T> ok(value: T): ApiEnvelope<T> = ApiEnvelope(code = 0, data = value)
    protected fun emptyObject(): JsonObject = JsonObject(emptyMap())
    protected fun <T> emptyPage(): ApiEnvelope<PageDto<T>> = ok(PageDto(emptyList(), 0))

    override suspend fun uploadPlaylistCover(file: MultipartBody.Part): ApiEnvelope<PlaylistCoverUploadDto> =
        ok(PlaylistCoverUploadDto(""))

    override suspend fun passwordLogin(body: LoginRequest): ApiEnvelope<LoginData> = ok(LoginData(""))
    override suspend fun systemConfig(): ApiEnvelope<SystemConfigDto> = ok(SystemConfigDto())
    override suspend fun currentUser(): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun changePassword(body: ChangePasswordRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun startTranscode(body: JsonObject): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun heartbeatTranscode(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun quitTranscode(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun authorizedDirectories(): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun childDirectories(parent: String): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun folderDetail(guid: String): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun scanAllFolders(): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun cancelTask(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun retryTask(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun rebuildSearchIndex(): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun adminTasks(): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun adminFolders(): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun adminUsers(): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun defaultUserSettings(): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun adminServerSettings(): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun createFolder(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun editFolder(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun deleteFolder(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun scanFolder(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun createUser(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun editUser(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun saveDefaultUserSettings(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())
    override suspend fun saveAdminServerSettings(body: JsonObject): ApiEnvelope<JsonElement> = ok(emptyObject())

    override suspend fun tracks(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun albums(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<AlbumDto>> = emptyPage()
    override suspend fun albumDetail(guid: String): ApiEnvelope<AlbumDto> = ok(AlbumDto(guid))
    override suspend fun artistDetail(guid: String): ApiEnvelope<ArtistDto> = ok(ArtistDto(guid))
    override suspend fun artists(page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> = emptyPage()
    override suspend fun albumTracks(albumGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun artistTracks(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun artistAlbums(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> = emptyPage()
    override suspend fun playlistTracks(playlistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun playlists(): ApiEnvelope<PageDto<PlaylistDto>> = emptyPage()
    override suspend fun playlistDetail(guid: String): ApiEnvelope<PlaylistDto> = ok(PlaylistDto(guid))
    override suspend fun createPlaylist(body: PlaylistCreateRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun editPlaylist(body: PlaylistEditRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun deletePlaylist(body: PlaylistGuidRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun addPlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun removePlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun playlistInvalidTrackCount(guid: String): ApiEnvelope<TotalDto> = ok(TotalDto(0))
    override suspend fun purgePlaylistTracks(body: PlaylistGuidRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun favorites(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun history(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun trackMetadata(guid: String): ApiEnvelope<TrackMetadataDto> =
        ok(TrackMetadataDto(TrackDto(guid), AudioSpecDto()))
    override suspend fun updateTrackMetadata(body: JsonObject): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun genres(page: Int, size: Int): ApiEnvelope<PageDto<Genre>> = emptyPage()
    override suspend fun roamStart(deviceId: String): ApiEnvelope<RoamDto> = ok(RoamDto())
    override suspend fun roamNext(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> = ok(RoamDto())
    override suspend fun roamPrevious(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> = ok(RoamDto())
    override suspend fun lyrics(trackGuid: String): ApiEnvelope<LyricDataDto> = ok(LyricDataDto())
    override suspend fun suggestions(query: String): ApiEnvelope<SearchSuggestionsDto> =
        ok(SearchSuggestionsDto(SuggestionGroupDto(), SuggestionGroupDto(), SuggestionGroupDto(), SuggestionGroupDto()))
    override suspend fun searchTracks(query: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> = emptyPage()
    override suspend fun searchAlbums(query: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> = emptyPage()
    override suspend fun searchArtists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> = emptyPage()
    override suspend fun searchPlaylists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<PlaylistDto>> = emptyPage()
    override suspend fun createFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun deleteFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
    override suspend fun reportEvent(body: EventReportRequest): ApiEnvelope<JsonObject> = ok(emptyObject())
}
