package com.seasonyuu.fnmusic.desktop.play

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.DataLine
import javax.sound.sampled.FloatControl
import javax.sound.sampled.SourceDataLine
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.roundToLong

/** Everything the UI needs to draw the transport bar. */
data class AudioState(
    val trackId: String? = null,
    val title: String = "",
    val subtitle: String = "",
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val positionSeconds: Double = 0.0,
    val durationSeconds: Double = 0.0,
    val error: String? = null,
)

/**
 * Plays a Music Free stream on the JVM.
 *
 * Media3 is Android-only, so the desktop build decodes MP3 with
 * `javax.sound.sampled` plus the JLayer SPI. The server transcodes every request
 * (`format=mp3`), which means one decoder covers FLAC, WMA, M4A and MP3 alike.
 *
 * The track is cached as a file first: that keeps seeks exact and makes replay
 * instant, at the cost of waiting for the first byte of a new track.
 */
class DesktopAudioPlayer(
    private val scope: CoroutineScope,
    private val http: OkHttpClient = OkHttpClient(),
) {
    private val _state = MutableStateFlow(AudioState())
    val state: StateFlow<AudioState> = _state.asStateFlow()

    private val cacheDir: File = File(System.getProperty("user.home"), "Library/Caches/FnMusic/audio")
        .apply { mkdirs() }

    private var loadJob: Job? = null
    private var worker: PlaybackWorker? = null
    private var volume = 0.85f

    fun play(trackId: String, title: String, subtitle: String, streamUrl: String, durationSeconds: Double) {
        loadJob?.cancel()
        worker?.stop()
        worker = null
        _state.value = AudioState(
            trackId = trackId,
            title = title,
            subtitle = subtitle,
            buffering = true,
            durationSeconds = durationSeconds,
        )
        loadJob = scope.launch {
            val file = try {
                ensureCached(trackId, streamUrl)
            } catch (error: Throwable) {
                _state.update { it.copy(buffering = false, error = error.message ?: "音频加载失败") }
                return@launch
            }
            startWorker(file, startAt = 0.0, durationSeconds = durationSeconds)
        }
    }

    fun togglePause() {
        val current = worker ?: return
        if (current.isPaused) current.resume() else current.pause()
        _state.update { it.copy(playing = !current.isPaused) }
    }

    fun pause() {
        val current = worker ?: return
        current.pause()
        _state.update { it.copy(playing = false) }
    }

    fun resume() {
        val current = worker ?: return
        current.resume()
        _state.update { it.copy(playing = true) }
    }

    fun seekTo(seconds: Double) {
        val current = worker ?: return
        val target = seconds.coerceIn(0.0, max(0.0, _state.value.durationSeconds - 1))
        current.stop()
        startWorker(current.file, target, current.durationSeconds)
    }

    fun setVolume(value: Float) {
        volume = value.coerceIn(0f, 1f)
        worker?.setVolume(volume)
    }

    fun stop() {
        loadJob?.cancel()
        worker?.stop()
        worker = null
        _state.value = AudioState()
    }

    // ---- Internals --------------------------------------------------------

    private fun startWorker(file: File, startAt: Double, durationSeconds: Double) {
        val current = PlaybackWorker(
            file = file,
            startAt = startAt,
            durationSeconds = durationSeconds,
            initialVolume = volume,
            onProgress = { position ->
                _state.update { it.copy(positionSeconds = position, buffering = false, playing = true) }
            },
            onFinished = {
                _state.update { it.copy(playing = false, positionSeconds = it.durationSeconds) }
            },
            onError = { message ->
                _state.update { it.copy(buffering = false, playing = false, error = message) }
            },
        )
        worker = current
        _state.update { it.copy(buffering = false, playing = true, positionSeconds = startAt) }
        current.start()
    }

    private suspend fun ensureCached(trackId: String, streamUrl: String): File {
        val safe = trackId.replace(Regex("[^A-Za-z0-9-]"), "_")
        val target = File(cacheDir, "$safe.mp3")
        if (target.isFile && target.length() > 0) return target
        val temp = File(cacheDir, "$safe.part")
        withContext(Dispatchers.IO) {
            val request = Request.Builder().url(streamUrl).build()
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("服务器返回 HTTP ${response.code}")
                val contentType = response.header("Content-Type").orEmpty()
                if (contentType.startsWith("text/") || contentType.contains("xml")) {
                    error("服务器没有返回音频流（$contentType）")
                }
                val body = response.body ?: error("响应为空")
                temp.outputStream().use { output -> body.byteStream().copyTo(output) }
            }
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
        }
        return target
    }
}

private class PlaybackWorker(
    val file: File,
    private val startAt: Double,
    val durationSeconds: Double,
    private val initialVolume: Float,
    private val onProgress: (Double) -> Unit,
    private val onFinished: () -> Unit,
    private val onError: (String) -> Unit,
) {
    @Volatile private var paused = false
    @Volatile private var stopped = false
    @Volatile private var gainControl: FloatControl? = null
    @Volatile private var pendingVolume: Float = initialVolume

    val isPaused: Boolean get() = paused

    private val thread = Thread({ run() }, "FnMusic-Audio").apply { isDaemon = true }

    fun start() {
        thread.start()
        setVolume(initialVolume)
    }

    fun pause() {
        paused = true
    }

    fun resume() {
        paused = false
    }

    fun stop() {
        stopped = true
        thread.interrupt()
    }

    fun setVolume(value: Float) {
        pendingVolume = value
        val control = gainControl ?: return
        val db = if (value <= 0.001f) {
            control.minimum
        } else {
            max(control.minimum.toDouble(), 20.0 * log10(value.toDouble())).toFloat()
        }
        runCatching { control.value = db.coerceIn(control.minimum, control.maximum) }
    }

    private fun run() {
        var line: SourceDataLine? = null
        try {
            val decoded = AudioSystem.getAudioInputStream(file)
            val sourceFormat = decoded.format
            val pcm = AudioFormat(
                AudioFormat.Encoding.PCM_SIGNED,
                sourceFormat.sampleRate,
                16,
                sourceFormat.channels,
                sourceFormat.channels * 2,
                sourceFormat.sampleRate,
                false,
            )
            val stream = if (sourceFormat.encoding == AudioFormat.Encoding.PCM_SIGNED) {
                decoded
            } else {
                AudioSystem.getAudioInputStream(pcm, decoded)
            }
            val format = stream.format
            val info = DataLine.Info(SourceDataLine::class.java, format)
            line = (AudioSystem.getLine(info) as SourceDataLine).apply {
                open(format, 256 * 1024)
                start()
            }
            gainControl = runCatching {
                line.getControl(FloatControl.Type.MASTER_GAIN) as FloatControl
            }.getOrNull()
            setVolume(pendingVolume)

            if (startAt > 0) {
                val frames = (startAt * format.frameRate).roundToLong()
                var remaining = frames * format.frameSize
                while (remaining > 0) {
                    val skipped = stream.skip(remaining)
                    if (skipped <= 0) break
                    remaining -= skipped
                }
            }

            val buffer = ByteArray(16 * 1024)
            var written = (startAt * format.frameRate * format.frameSize).toLong()
            var lastReport = 0L
            while (!stopped) {
                if (paused) {
                    line.stop()
                    while (paused && !stopped) Thread.sleep(25)
                    if (!stopped) line.start()
                    continue
                }
                val read = stream.read(buffer, 0, buffer.size)
                if (read <= 0) break
                line.write(buffer, 0, read)
                written += read
                val now = System.currentTimeMillis()
                if (now - lastReport > 200) {
                    lastReport = now
                    val seconds = written.toDouble() / (format.frameSize * format.frameRate)
                    onProgress(seconds)
                }
            }
            line.drain()
            if (!stopped) onFinished()
        } catch (_: InterruptedException) {
            // Stop requested; fall through to cleanup.
        } catch (error: Throwable) {
            if (!stopped) onError(error.message ?: "音频解码失败")
        } finally {
            runCatching { line?.stop() }
            runCatching { line?.close() }
            gainControl = null
        }
    }
}
