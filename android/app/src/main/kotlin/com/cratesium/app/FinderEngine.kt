package com.cratesium.app

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

/**
 * The app's single Flutter engine, kept alive independently of any Activity.
 *
 * The Dart download queue runs in this engine. Because it survives the
 * Activity (Back, rotation, swiping the task away while [DownloadService]
 * keeps the process alive), downloads, their progress and the history keep
 * being tracked in the background, and the UI reattaches when the app is
 * reopened.
 *
 * Channels (contract shared with lib/services/android/android_toolchain.dart):
 *   `finder/toolchain`         start, stop, ffmpegVersion, updateYtDlp,
 *                                 downloadsDirectory, ensureStoragePermission,
 *                                 ensureNotificationPermission, openFile,
 *                                 openFolder, setForegroundStatus
 *   `finder/toolchain/events`  {id, type: out, line} · {id, type: exit, code, stderr}
 *                                 · {type: cancelAll} (from the notification)
 */
object FinderEngine {
    private const val ENGINE_ID = "finder"
    private const val STORAGE_REQUEST = 4101
    private const val NOTIFICATION_REQUEST = 4102

    private lateinit var app: Context
    private var activity = WeakReference<Activity>(null)
    private var pendingStorage: MethodChannel.Result? = null
    private var pendingNotification: MethodChannel.Result? = null
    private var notificationAsked = false

    fun obtain(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        app = context.applicationContext
        Toolchain.init(app)
        // Plugins are registered automatically by the engine.
        val engine = FlutterEngine(app)
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "finder/toolchain").setMethodCallHandler(::onCall)
        EventChannel(messenger, "finder/toolchain/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                Toolchain.listener = { sink?.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                Toolchain.listener = null
            }
        })
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    fun attach(a: Activity) {
        activity = WeakReference(a)
        // A permission request made before any Activity existed (Dart's main()
        // runs as soon as the engine starts) is asked now.
        if (pendingStorage != null) requestStorage(a)
    }

    fun detach(a: Activity) {
        if (activity.get() === a) activity = WeakReference(null)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                Toolchain.start(call.argument<Int>("id")!!, call.argument<List<String>>("args")!!)
                result.success(null)
            }
            "stop" -> {
                Toolchain.stop(call.argument<Int>("id")!!)
                result.success(null)
            }
            "ensureReady" -> background(result) {
                Toolchain.ensureReady()
                "ready"
            }
            "ffmpegVersion" -> background(result) { Toolchain.ffmpegVersion() }
            "updateYtDlp" -> background(result) { Toolchain.updateYtDlp() }
            "downloadsDirectory" -> {
                @Suppress("DEPRECATION")
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Finder")
                result.success(dir.absolutePath)
            }
            "ensureStoragePermission" -> ensureStoragePermission(result)
            "ensureNotificationPermission" -> ensureNotificationPermission(result)
            "setForegroundStatus" -> {
                DownloadService.updateStatus(
                    app,
                    DownloadService.Status(
                        active = call.argument<Int>("active") ?: 0,
                        queued = call.argument<Int>("queued") ?: 0,
                        title = call.argument<String>("title"),
                        progress = call.argument<Double>("progress"),
                        completed = call.argument<Int>("completed") ?: 0,
                        total = call.argument<Int>("total") ?: 0,
                    ),
                )
                result.success(null)
            }
            "openFile" -> openFile(call.argument<String>("path")!!, result)
            "openFolder" -> openFolder(result)
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Toolchain.background({ r ->
            r.fold(
                { result.success(it) },
                { result.error("toolchain", it.message ?: it.toString(), null) },
            )
        }, work)
    }

    /** Android 9 and older need WRITE_EXTERNAL_STORAGE for Download/Finder. */
    private fun ensureStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingStorage?.success(false)
        pendingStorage = result
        activity.get()?.let(::requestStorage)
    }

    private fun requestStorage(a: Activity) {
        ActivityCompat.requestPermissions(a, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
    }

    /**
     * Android 13+: asks once per launch for permission to post notifications
     * (download progress in the background, completion/failure alerts).
     * Downloads work either way.
     */
    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        val a = activity.get()
        if (a == null || notificationAsked) {
            result.success(false)
            return
        }
        notificationAsked = true
        pendingNotification?.success(false)
        pendingNotification = result
        ActivityCompat.requestPermissions(a, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            STORAGE_REQUEST -> {
                pendingStorage?.success(granted)
                pendingStorage = null
            }
            NOTIFICATION_REQUEST -> {
                pendingNotification?.success(granted)
                pendingNotification = null
            }
        }
    }

    /** Starts [intent] from the visible Activity, or as a new task from the background. */
    private fun launch(intent: Intent) {
        val a = activity.get()
        if (a != null) a.startActivity(intent) else app.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openFile(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            launch(Intent.createChooser(intent, null))
            result.success(null)
        } catch (e: Exception) {
            result.error("open", e.message, null)
        }
    }

    /** Opens the system Downloads view (Android has no generic folder viewer). */
    private fun openFolder(result: MethodChannel.Result) {
        try {
            launch(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("open", e.message, null)
        }
    }
}
