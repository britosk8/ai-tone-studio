package com.aitone.studio

import android.app.Activity
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Plays only a bounded app-private preview. No network, microphone or pedal commands. */
@Suppress("DEPRECATION")
class AudioPreviewBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ai_tone/preview")
    private val audio = activity.getSystemService(Activity.AUDIO_SERVICE) as AudioManager
    private var player: MediaPlayer? = null
    private var owner: String? = null
    private var pending: MethodChannel.Result? = null
    private var duration = 0
    private var error: String? = null
    private val focus = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) stop()
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val id = call.argument<String>("id")
                    val path = call.argument<String>("path")
                    if (id.isNullOrBlank() || path.isNullOrBlank()) {
                        result.error("preview", "Prévia inválida", null)
                    } else {
                        try {
                            val file = File(path).canonicalFile
                            val allowed = listOf(activity.cacheDir, activity.filesDir).any {
                                file.path.startsWith(it.canonicalPath + File.separator)
                            }
                            require(allowed && file.isFile && file.length() >= 44L && file.length() <= 8_000_000L) { "Arquivo de prévia inválido" }
                            stop()
                            owner = id; error = null; duration = 0; pending = result
                            val next = MediaPlayer()
                            player = next
                            next.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                            next.setDataSource(file.path)
                            next.setOnPreparedListener {
                                if (player === next) {
                                    try {
                                    if (audio.requestAudioFocus(focus, AudioManager.STREAM_MUSIC,
                                            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                                        release("Não foi possível obter a saída de áudio")
                                    } else {
                                        if (player !== next) return@setOnPreparedListener
                                        duration = next.duration
                                        next.start()
                                        val callback = pending; pending = null
                                        callback?.success(mapOf("duration_ms" to duration))
                                    }
                                    } catch (e: Exception) { release(e.message ?: "Falha na reprodução") }
                                }
                            }
                            next.setOnCompletionListener { if (player === next) release() }
                            next.setOnErrorListener { _, _, _ ->
                                if (player === next) release("Não foi possível reproduzir este trecho")
                                true
                            }
                            next.prepareAsync()
                        } catch (e: Exception) {
                            if (pending === result) release(e.message ?: "Falha na reprodução")
                            else result.error("preview", e.message, null)
                        }
                    }
                }
                "status" -> {
                    val same = owner == call.argument<String>("id")
                    val current = player
                    result.success(mapOf("playing" to (same && current?.isPlaying == true),
                        "position_ms" to if (same && current != null) current.currentPosition else 0,
                        "duration_ms" to if (same) duration else 0, "error" to if (same) error else null))
                }
                "stop" -> {
                    if (owner == call.argument<String>("id")) stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun release(message: String? = null) {
        val next = player; player = null
        val callback = pending; pending = null
        next?.release()
        audio.abandonAudioFocus(focus)
        if (message != null) error = message
        callback?.error("preview", message ?: "Reprodução cancelada", null)
    }
    fun stop() { release(); owner = null }
    fun dispose() { stop(); channel.setMethodCallHandler(null) }
}
