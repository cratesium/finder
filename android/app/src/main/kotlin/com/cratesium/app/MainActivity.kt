package com.cratesium.app

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the Flutter UI.
 *
 * The engine (and with it the Dart download queue) is owned by
 * [FinderEngine], not by this Activity, so closing or recreating the
 * Activity never stops downloads. yt-dlp (with its own Python runtime) and
 * FFmpeg ship inside the APK through youtubedl-android and are run by
 * [Toolchain]; [DownloadService] keeps the process alive while they work.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = FinderEngine.obtain(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FinderEngine.attach(this)
    }

    override fun onDestroy() {
        FinderEngine.detach(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        FinderEngine.onRequestPermissionsResult(requestCode, grantResults)
    }
}
