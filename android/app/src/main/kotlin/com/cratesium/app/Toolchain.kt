package com.cratesium.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/** Embedded yt-dlp + FFmpeg (youtubedl-android), shared for the app process. */
object Toolchain {
    private val main = Handler(Looper.getMainLooper())
    private val initExecutor = Executors.newSingleThreadExecutor()
    private val runExecutor = Executors.newCachedThreadPool()
    private val running = ConcurrentHashMap<Int, Future<*>>()

    @Volatile private var ready: Future<*>? = null
    private lateinit var app: Context

    @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null

    @Synchronized
    fun init(context: Context) {
        if (ready != null) return
        app = context.applicationContext
        ready = initExecutor.submit {
            YoutubeDL.getInstance().init(app)
            FFmpeg.getInstance().init(app)
        }
    }

    fun ensureReady() {
        val f = ready ?: error("Toolchain was not initialized")
        if (!f.get(5, TimeUnit.MINUTES)) {
            throw IllegalStateException("The built-in download engine took too long to start.")
        }
    }

    private fun awaitReady() = ensureReady()

    fun emit(event: Map<String, Any?>) = main.post { listener?.invoke(event) }

    fun start(id: Int, args: List<String>) {
        running[id] = runExecutor.submit {
            var code = 0
            var stderr = ""
            try {
                awaitReady()
                val request = YoutubeDLRequest(emptyList<String>()).addCommands(args)
                val response = YoutubeDL.getInstance().execute(request, id.toString()) { _, _, line ->
                    emit(mapOf("id" to id, "type" to "out", "line" to line))
                }
                code = response.exitCode
                stderr = response.err
            } catch (e: YoutubeDL.CanceledException) {
                code = 130
            } catch (e: YoutubeDLException) {
                code = 1
                stderr = e.message ?: ""
            } catch (e: InterruptedException) {
                code = 130
            } catch (e: Exception) {
                code = 1
                stderr = "ERROR: ${e.message ?: e}"
            } finally {
                running.remove(id)
                emit(mapOf("id" to id, "type" to "exit", "code" to code, "stderr" to stderr))
            }
        }
    }

    fun stop(id: Int) {
        YoutubeDL.getInstance().destroyProcessById(id.toString())
    }

    fun updateYtDlp(): String {
        awaitReady()
        return when (YoutubeDL.getInstance().updateYoutubeDL(app, YoutubeDL.UpdateChannel.STABLE)) {
            YoutubeDL.UpdateStatus.DONE -> "done"
            else -> "alreadyUpToDate"
        }
    }

    fun background(result: MethodChannel.Result, work: () -> Any?) {
        runExecutor.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("toolchain", e.message ?: e.toString(), null) }
            }
        }
    }
}