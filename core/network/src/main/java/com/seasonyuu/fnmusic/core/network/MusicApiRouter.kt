package com.seasonyuu.fnmusic.core.network

import com.seasonyuu.fnmusic.core.model.Genre
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.MultipartBody

/**
 * A stable [MusicApi] handle whose backend can change at runtime.
 *
 * Repositories hold long-lived references, so swapping the object graph on a
 * source change would leave them pointing at the old backend. Instead they hold
 * this router and every call is forwarded to the currently active delegate.
 * The fnOS Retrofit implementation stays the default, which keeps all existing
 * behaviour untouched when no alternative source is active.
 */
class MusicApiRouter(initial: MusicApi) : MusicApi {

    @Volatile
    var delegate: MusicApi = initial

    override suspend fun uploadPlaylistCover(file: MultipartBody.Part): ApiEnvelope<PlaylistCoverUploadDto> =
        delegate.uploadPlaylistCover(file)

    override suspend fun passwordLogin(body: LoginRequest): ApiEnvelope<LoginData> =
        delegate.passwordLogin(body)

    override suspend fun systemConfig(): ApiEnvelope<SystemConfigDto> =
        delegate.systemConfig()

    override suspend fun currentUser(): ApiEnvelope<JsonObject> =
        delegate.currentUser()

    override suspend fun changePassword(body: ChangePasswordRequest): ApiEnvelope<JsonObject> =
        delegate.changePassword(body)

    override suspend fun startTranscode(body: JsonObject): ApiEnvelope<JsonObject> =
        delegate.startTranscode(body)

    override suspend fun heartbeatTranscode(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.heartbeatTranscode(body)

    override suspend fun quitTranscode(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.quitTranscode(body)

    override suspend fun authorizedDirectories(): ApiEnvelope<JsonElement> =
        delegate.authorizedDirectories()

    override suspend fun childDirectories(parent: String): ApiEnvelope<JsonElement> =
        delegate.childDirectories(parent)

    override suspend fun folderDetail(guid: String): ApiEnvelope<JsonObject> =
        delegate.folderDetail(guid)

    override suspend fun scanAllFolders(): ApiEnvelope<JsonElement> =
        delegate.scanAllFolders()

    override suspend fun cancelTask(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.cancelTask(body)

    override suspend fun retryTask(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.retryTask(body)

    override suspend fun rebuildSearchIndex(): ApiEnvelope<JsonObject> =
        delegate.rebuildSearchIndex()

    override suspend fun adminTasks(): ApiEnvelope<JsonElement> =
        delegate.adminTasks()

    override suspend fun adminFolders(): ApiEnvelope<JsonElement> =
        delegate.adminFolders()

    override suspend fun adminUsers(): ApiEnvelope<JsonElement> =
        delegate.adminUsers()

    override suspend fun defaultUserSettings(): ApiEnvelope<JsonObject> =
        delegate.defaultUserSettings()

    override suspend fun adminServerSettings(): ApiEnvelope<JsonObject> =
        delegate.adminServerSettings()

    override suspend fun createFolder(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.createFolder(body)

    override suspend fun editFolder(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.editFolder(body)

    override suspend fun deleteFolder(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.deleteFolder(body)

    override suspend fun scanFolder(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.scanFolder(body)

    override suspend fun createUser(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.createUser(body)

    override suspend fun editUser(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.editUser(body)

    override suspend fun saveDefaultUserSettings(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.saveDefaultUserSettings(body)

    override suspend fun saveAdminServerSettings(body: JsonObject): ApiEnvelope<JsonElement> =
        delegate.saveAdminServerSettings(body)

    override suspend fun tracks(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<TrackDto>> =
        delegate.tracks(page, size, sort)

    override suspend fun albums(page: Int, size: Int, sort: String?): ApiEnvelope<PageDto<AlbumDto>> =
        delegate.albums(page, size, sort)

    override suspend fun albumDetail(guid: String): ApiEnvelope<AlbumDto> =
        delegate.albumDetail(guid)

    override suspend fun artistDetail(guid: String): ApiEnvelope<ArtistDto> =
        delegate.artistDetail(guid)

    override suspend fun artists(page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> =
        delegate.artists(page, size)

    override suspend fun albumTracks(albumGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.albumTracks(albumGuid, page, size)

    override suspend fun artistTracks(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.artistTracks(artistGuid, page, size)

    override suspend fun artistAlbums(artistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> =
        delegate.artistAlbums(artistGuid, page, size)

    override suspend fun playlistTracks(playlistGuid: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.playlistTracks(playlistGuid, page, size)

    override suspend fun playlists(): ApiEnvelope<PageDto<PlaylistDto>> =
        delegate.playlists()

    override suspend fun playlistDetail(guid: String): ApiEnvelope<PlaylistDto> =
        delegate.playlistDetail(guid)

    override suspend fun createPlaylist(body: PlaylistCreateRequest): ApiEnvelope<JsonObject> =
        delegate.createPlaylist(body)

    override suspend fun editPlaylist(body: PlaylistEditRequest): ApiEnvelope<JsonObject> =
        delegate.editPlaylist(body)

    override suspend fun deletePlaylist(body: PlaylistGuidRequest): ApiEnvelope<JsonObject> =
        delegate.deletePlaylist(body)

    override suspend fun addPlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> =
        delegate.addPlaylistTracks(body)

    override suspend fun removePlaylistTracks(body: PlaylistTracksRequest): ApiEnvelope<JsonObject> =
        delegate.removePlaylistTracks(body)

    override suspend fun playlistInvalidTrackCount(guid: String): ApiEnvelope<TotalDto> =
        delegate.playlistInvalidTrackCount(guid)

    override suspend fun purgePlaylistTracks(body: PlaylistGuidRequest): ApiEnvelope<JsonObject> =
        delegate.purgePlaylistTracks(body)

    override suspend fun favorites(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.favorites(page, size)

    override suspend fun history(page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.history(page, size)

    override suspend fun trackMetadata(guid: String): ApiEnvelope<TrackMetadataDto> =
        delegate.trackMetadata(guid)

    override suspend fun updateTrackMetadata(body: JsonObject): ApiEnvelope<JsonObject> =
        delegate.updateTrackMetadata(body)

    override suspend fun genres(page: Int, size: Int): ApiEnvelope<PageDto<Genre>> =
        delegate.genres(page, size)

    override suspend fun roamStart(deviceId: String): ApiEnvelope<RoamDto> =
        delegate.roamStart(deviceId)

    override suspend fun roamNext(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> =
        delegate.roamNext(deviceId, relativeRoamId)

    override suspend fun roamPrevious(deviceId: String, relativeRoamId: String): ApiEnvelope<RoamDto> =
        delegate.roamPrevious(deviceId, relativeRoamId)

    override suspend fun lyrics(trackGuid: String): ApiEnvelope<LyricDataDto> =
        delegate.lyrics(trackGuid)

    override suspend fun suggestions(query: String): ApiEnvelope<SearchSuggestionsDto> =
        delegate.suggestions(query)

    override suspend fun searchTracks(query: String, page: Int, size: Int): ApiEnvelope<PageDto<TrackDto>> =
        delegate.searchTracks(query, page, size)

    override suspend fun searchAlbums(query: String, page: Int, size: Int): ApiEnvelope<PageDto<AlbumDto>> =
        delegate.searchAlbums(query, page, size)

    override suspend fun searchArtists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<ArtistDto>> =
        delegate.searchArtists(query, page, size)

    override suspend fun searchPlaylists(query: String, page: Int, size: Int): ApiEnvelope<PageDto<PlaylistDto>> =
        delegate.searchPlaylists(query, page, size)

    override suspend fun createFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> =
        delegate.createFavorite(body)

    override suspend fun deleteFavorite(body: FavoriteRequest): ApiEnvelope<JsonObject> =
        delegate.deleteFavorite(body)

    override suspend fun reportEvent(body: EventReportRequest): ApiEnvelope<JsonObject> =
        delegate.reportEvent(body)
}
