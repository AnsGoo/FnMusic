package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.model.MusicError
import com.seasonyuu.fnmusic.core.network.MediaUrlResolver
import com.seasonyuu.fnmusic.core.network.md5
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import java.security.SecureRandom

/**
 * Everything needed to authenticate a Music Free session. It is persisted in
 * the existing encrypted credential vault as an opaque JSON string, so older
 * saved logins keep their original shape and still decode.
 */
@Serializable
data class MusicFreeAuth(
    val token: String,
    val username: String,
    val subsonicToken: String,
    val subsonicSalt: String,
    val clientSalt: String,
) {
    fun encode(json: Json): String = json.encodeToString(this)

    companion object {
        fun decode(json: Json, raw: String?): MusicFreeAuth? = raw?.let {
            runCatching { json.decodeFromString<MusicFreeAuth>(it) }.getOrNull()
        }
    }
}

internal object MusicFreeAuthGateway {
    suspend fun login(
        http: OkHttpClient,
        json: Json,
        baseUrl: HttpUrl,
        username: String,
        password: String,
    ): MusicFreeAuth {
        val client = MusicFreeClient(http, json, baseUrl) { null }
        val payload = buildJsonObject {
            put("username", username)
            put("password", password)
        }
        val root = client.post("rest/api/v1/auth/login", payload)
        val token = root.text("token")
            ?: throw MusicError.Authentication("Music Free 登录失败，请检查账号和密码")
        // A stable salt keeps media URLs cacheable for the whole session.
        val salt = ByteArray(8).also(SecureRandom()::nextBytes).joinToString("") { "%02x".format(it) }
        return MusicFreeAuth(
            token = token,
            username = root.text("username") ?: username,
            subsonicToken = root.text("subsonicToken").orEmpty(),
            subsonicSalt = root.text("subsonicSalt").orEmpty(),
            clientSalt = salt,
        )
    }
}

/**
 * Media3 and Coil receive plain URL strings with no way to attach headers, so
 * Music Free media URLs carry Subsonic `u/t/s` credentials in the query.
 * The server accepts `t = md5(storedPasswordHex + s)` (its legacy branch).
 */
class MusicFreeUrls(
    private val baseUrl: HttpUrl,
    private val auth: () -> MusicFreeAuth?,
) : MediaUrlResolver {

    override fun streamUrl(trackId: String): String =
        url("rest/stream", linkedMapOf("id" to trackId))

    override fun coverUrl(coverId: String, size: Int): String? {
        if (coverId.isBlank()) return null
        return url("rest/getCoverArt", linkedMapOf("id" to coverId, "size" to size.coerceIn(1, 2048).toString()))
    }

    private fun url(path: String, params: Map<String, String>): String {
        val builder = baseUrl.newBuilder()
            .addPathSegments(path)
            .addQueryParameter("v", "1.16.1")
            .addQueryParameter("c", "FnMusic")
        params.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        val current = auth()
        if (current != null && current.subsonicToken.isNotBlank()) {
            builder.addQueryParameter("u", current.username)
                .addQueryParameter("t", (current.subsonicToken + current.clientSalt).md5())
                .addQueryParameter("s", current.clientSalt)
        }
        return builder.build().toString()
    }
}
