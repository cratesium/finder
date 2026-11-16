package com.cratesium.app

import android.Manifest
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Standard Flutter host. Platform channels run the yt-dlp / FFmpeg build that
 * ships inside the APK (youtubedl-android).
 */
class MainActivity : FlutterActivity() {

    private var pendingStorage: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Toolchain.init(applicationContext)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "finder/toolchain").setMethodCallHandler(::onCall)
        EventChannel(messenger, "finder/toolchain/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                Toolchain.listener = { sink?.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                Toolchain.listener = null
            }
        })
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_REQUEST) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            pendingStorage?.success(granted)
            pendingStorage = null
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                Toolchain.start(call.argument<Int>("id")!!, call.argument<List<String>>("args")!!)
                result.success(null)
            }
            "stop" -> Toolchain.stop(call.argument<Int>("id")!!).let { result.success(null) }
            "ensureReady" -> Toolchain.background(result) {
                Toolchain.ensureReady()
                "ready"
            }
            "updateYtDlp" -> Toolchain.background(result) { Toolchain.updateYtDlp() }
            "downloadsDirectory" -> {
                @Suppress("DEPRECATION")
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "Finder",
                )
                result.success(dir.absolutePath)
            }
            "ensureStoragePermission" -> ensureStoragePermission(result)
            "openFile" -> openFile(call.argument<String>("path")!!, result)
            "openFolder" -> openFolder(result)
            else -> result.notImplemented()
        }
    }

    /** Android 9 and older need storage permission for Download/Finder. */
    private fun ensureStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingStorage?.success(false)
        pendingStorage = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_REQUEST,
        )
    }

    private fun openFile(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(this, "${packageName}.files", file)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(intent, null))
            result.success(null)
        } catch (e: Exception) {
            result.error("open", e.message, null)
        }
    }

    private fun openFolder(result: MethodChannel.Result) {
        try {
            startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("open", e.message, null)
        }
    }

    companion object {
        private const val STORAGE_REQUEST = 4101
    }
}