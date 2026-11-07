package com.seasonyuu.fnmusic.core.network.musicfree

import com.seasonyuu.fnmusic.core.model.MusicError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A Navidrome-style list response: a bare JSON array plus `X-Total-Count`. */
internal data class MusicFreeList(
    val items: List<JsonObject>,
    val total: Long?,
)

/**
 * Minimal HTTP front-end for a Music Free server.
 *
 * Everything goes to absolute URLs so the fnOS [DynamicBaseUrlInterceptor] leaves
 * them alone. The shared client still contributes its cleartext-host policy,
 * which the session activates before any request is made.
 */
internal class MusicFreeClient(
    private val http: OkHttpClient,
    private val json: Json,
    private val baseUrl: HttpUrl,
    private val auth: () -> MusicFreeAuth?,
) {
    suspend fun get(path: String, params: Map<String, String> = emptyMap()): JsonObject =
        objectOf(raw(getRequest(path, params)))

    suspend fun post(path: String, payload: JsonObject? = null, params: Map<String, String> = emptyMap()): JsonObject =
        objectOf(
            raw(
                Request.Builder()
                    .url(url(path, params))
                    .post((payload?.toString() ?: "{}").toRequestBody(JSON_MEDIA_TYPE))
                    .build()
            ),
        )

    suspend fun put(path: String, payload: JsonObject? = null, params: Map<String, String> = emptyMap()): JsonObject =
        objectOf(
            raw(
                Request.Builder()
                    .url(url(path, params))
                    .put((payload?.toString() ?: "{}").toRequestBody(JSON_MEDIA_TYPE))
                    .build()
            ),
        )

    suspend fun delete(path: String, params: Map<String, String> = emptyMap()): JsonObject =
        objectOf(raw(Request.Builder().url(url(path, params)).delete().build()))

    /**
     * The Navidrome-compatible `/api` routes answer with a bare JSON array and
     * report the grand total through `X-Total-Count` rather than a body field.
     */
    suspend fun getArray(path: String, params: Map<String, String> = emptyMap()): MusicFreeList {
        val response = raw(getRequest(path, params, subsonicParams = false))
        val array = response.element as? JsonArray
            ?: throw MusicError.Protocol("Music Free 返回了非列表内容")
        return MusicFreeList(
            items = array.mapNotNull { it as? JsonObject },
            total = response.headers["X-Total-Count"]?.trim()?.toLongOrNull(),
        )
    }

    /** A single bare JSON object, as returned by `/api/artist/{id}`. */
    suspend fun getObject(path: String, params: Map<String, String> = emptyMap()): JsonObject =
        objectOf(raw(getRequest(path, params, subsonicParams = false)))

    private fun getRequest(
        path: String,
        params: Map<String, String>,
        subsonicParams: Boolean = true,
    ): Request = Request.Builder().url(url(path, params, subsonicParams)).get().build()

    private fun url(path: String, params: Map<String, String>, subsonicParams: Boolean = true): HttpUrl {
        val builder = baseUrl.newBuilder()
            .addPathSegments(path.trimStart('/'))
        if (subsonicParams) {
            builder
                .addQueryParameter("f", "json")
                .addQueryParameter("v", "1.16.1")
                .addQueryParameter("c", "FnMusic")
        }
        params.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build()
    }

    private fun objectOf(response: RawResponse): JsonObject {
        val root = response.element as? JsonObject
            ?: throw MusicError.Protocol("Music Free 返回了无法解析的内容")
        return unwrap(root, response.code)
    }

    private suspend fun raw(request: Request): RawResponse = withContext(Dispatchers.IO) {
        val bearer = auth()?.token
        val call = if (bearer.isNullOrBlank()) request else request.newBuilder()
            .header("Authorization", "Bearer $bearer")
            .build()
        http.newCall(call).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful && body.isBlank()) {
                throw MusicError.Protocol("Music Free 返回 HTTP ${response.code}")
            }
            val element = runCatching { json.parseToJsonElement(body) }.getOrNull()
                ?: throw MusicError.Protocol("Music Free 返回了无法解析的内容")
            RawResponse(element, response.code, response.headers)
        }
    }

    /**
     * Most endpoints wrap their payload in `subsonic-response`; login and
     * play-history return a bare object. Both shapes are accepted here.
     */
    private fun unwrap(root: JsonObject, httpCode: Int): JsonObject {
        val envelope = root.child("subsonic-response") ?: return root
        if (envelope.text("status")?.equals("failed", ignoreCase = true) == true) {
            val error = envelope.child("error")
            val code = error?.integer("code") ?: httpCode
            if (code == 40 || code == 50) throw MusicError.Authentication(error?.text("message") ?: "Music Free 登录状态已失效")
            throw MusicError.Business(code, error?.text("message") ?: "Music Free 请求失败")
        }
        return envelope
    }

    private class RawResponse(
        val element: JsonElement,
        val code: Int,
        val headers: Headers,
    )

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
