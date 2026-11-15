package com.turses.turses

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

/**
 * Yerel ağ için sade ses motoru.
 * Biçim: 16 kHz, mono, 16 bit PCM; 20 ms = 640 baytlık parçalar.
 * Rehber: mikrofon -> parçalar Dart'a (EventChannel) -> WebSocket ile dinleyicilere.
 * Turist: WebSocket'ten gelen parçalar -> kısa tampon -> hoparlör/kulaklık.
 */
class AudioEngine {

    companion object {
        const val RATE = 16000
        const val FRAME_BYTES = 640

        /** Çalmaya başlamadan önce biriktirilecek parça (60 ms): küçük dalgalanmaları emer. */
        private const val PREBUFFER = 3

        /** Bundan fazla parça birikirse eskileri atılır: gecikme 240 ms'yi geçmesin. */
        private const val MAX_QUEUE = 12
    }

    private val main = Handler(Looper.getMainLooper())

    // ------------------------------------------------------------ mikrofon

    @Volatile
    private var capturing = false
    var sink: EventChannel.EventSink? = null

    @SuppressLint("MissingPermission") // izin Dart tarafında alınıyor
    fun startCapture(): Boolean {
        if (capturing) return true
        val min = AudioRecord.getMinBufferSize(
            RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (min <= 0) return false
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(min, FRAME_BYTES * 8)
            )
        } catch (e: Exception) {
            return false
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            return false
        }
        val effects = ArrayList<AudioEffect>()
        try {
            if (NoiseSuppressor.isAvailable()) {
                NoiseSuppressor.create(rec.audioSessionId)?.let { it.enabled = true; effects.add(it) }
            }
        } catch (e: Exception) {
        }
        try {
            if (AutomaticGainControl.isAvailable()) {
                AutomaticGainControl.create(rec.audioSessionId)?.let { it.enabled = true; effects.add(it) }
            }
        } catch (e: Exception) {
        }
        try {
            rec.startRecording()
        } catch (e: Exception) {
            rec.release()
            return false
        }
        capturing = true
        Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buf = ByteArray(FRAME_BYTES)
            while (capturing) {
                var off = 0
                while (off < FRAME_BYTES && capturing) {
                    val n = rec.read(buf, off, FRAME_BYTES - off)
                    if (n <= 0) {
                        Thread.sleep(5)
                        break
                    }
                    off += n
                }
                if (off == FRAME_BYTES) {
                    val frame = buf.copyOf()
                    main.post { sink?.success(frame) }
                }
            }
            try {
                rec.stop()
            } catch (e: Exception) {
            }
            rec.release()
            for (fx in effects) {
                try {
                    fx.release()
                } catch (e: Exception) {
                }
            }
        }.start()
        return true
    }

    fun stopCapture() {
        capturing = false
    }

    // -------------------------------------------------------------- çalma

    @Volatile
    private var playing = false
    private val queue = LinkedBlockingDeque<ByteArray>()

    fun startPlayback(): Boolean {
        if (playing) return true
        val min = AudioTrack.getMinBufferSize(
            RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (min <= 0) return false
        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(maxOf(min, FRAME_BYTES * 4))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            return false
        }
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            return false
        }
        queue.clear()
        playing = true
        Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            try {
                track.play()
                var primed = false
                while (playing) {
                    if (!primed) {
                        if (queue.size < PREBUFFER) {
                            Thread.sleep(5)
                            continue
                        }
                        primed = true
                    }
                    val frame = queue.poll(200, TimeUnit.MILLISECONDS)
                    if (frame == null) {
                        primed = false // ses kesildi: yeniden biriktir
                        continue
                    }
                    while (queue.size > MAX_QUEUE) queue.pollFirst()
                    track.write(frame, 0, frame.size)
                }
            } catch (e: Exception) {
            } finally {
                try {
                    track.stop()
                } catch (e: Exception) {
                }
                track.release()
            }
        }.start()
        return true
    }

    fun play(frame: ByteArray) {
        if (playing) queue.offer(frame)
    }

    fun stopPlayback() {
        playing = false
        queue.clear()
    }
}
