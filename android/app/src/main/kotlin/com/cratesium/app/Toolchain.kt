package com.cratesium.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/**
 * Process-wide owner of the embedded yt-dlp/FFmpeg runtime.
 *
 * It lives as long as the app process does, not as long as an Activity does.
 * While anything runs, [DownloadService] keeps the process in the foreground,
 * so downloads keep going when the app is backgrounded, the screen is turned
 * off or the task is swiped away.
 */
object Toolchain {
    private val main = Handler(Looper.getMainLooper())
    private val initExecutor = Executors.newSingleThreadExecutor()
    private val runExecutor = Executors.newCachedThreadPool()
    private val running = ConcurrentHashMap<Int, Future<*>>()

    @Volatile private var ready: Future<*>? = null
    private lateinit var app: Context

    /** Receives `{id, type: out|exit, …}` and `{type: cancelAll}` events (main thread). */
    @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null

    val runningCount: Int get() = running.size

    /** Starts unpacking Python/yt-dlp/FFmpeg once (the first launch takes a few seconds). */
    @Synchronized
    fun init(context: Context) {
        if (ready != null) return
        app = context.applicationContext
        ready = initExecutor.submit {
            YoutubeDL.getInstance().init(app)
            FFmpeg.getInstance().init(app)
        }
    }

    private fun awaitReady() {
        ready!!.get()
    }

    fun emit(event: Map<String, Any?>) = main.post { listener?.invoke(event) }

    /** Runs yt-dlp with [args]; emits each stdout line, then the exit status. */
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
                // execute() throws on a non-zero exit; the message is stderr.
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
                main.post { DownloadService.sync(app) }
            }
        }
        DownloadService.sync(app)
    }

    fun stop(id: Int) {
        YoutubeDL.getInstance().destroyProcessById(id.toString())
    }

    /** Last resort when nobody on the Dart side can cancel downloads properly. */
    fun stopAll() {
        for (id in running.keys) stop(id)
    }

    fun ffmpegVersion(): String {
        awaitReady()
        val ffmpeg = File(app.applicationInfo.nativeLibraryDir, "libffmpeg.so")
        val libs = File(app.noBackupFilesDir, "youtubedl-android/packages/ffmpeg/usr/lib")
        val process = ProcessBuilder(ffmpeg.absolutePath, "-hide_banner", "-version")
            .redirectErrorStream(true)
            .also { it.environment()["LD_LIBRARY_PATH"] = libs.absolutePath }
            .start()
        val out = process.inputStream.bufferedReader().readText()
        if (!process.waitFor(20, TimeUnit.SECONDS)) process.destroy()
        return out
    }

    fun updateYtDlp(): String {
        awaitReady()
        return when (YoutubeDL.getInstance().updateYoutubeDL(app, YoutubeDL.UpdateChannel.STABLE)) {
            YoutubeDL.UpdateStatus.DONE -> "done"
            else -> "alreadyUpToDate"
        }
    }

    /** Runs [work] off the main thread and delivers its result on the main thread. */
    fun background(onResult: (Result<Any?>) -> Unit, work: () -> Any?) {
        runExecutor.execute {
            val r = runCatching(work)
            main.post { onResult(r) }
        }
    }
}
