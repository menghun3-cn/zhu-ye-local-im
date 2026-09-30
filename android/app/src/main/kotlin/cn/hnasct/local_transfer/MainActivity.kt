package cn.hnasct.local_transfer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The application's own platform channel.
 *
 * This project ships no plugins, so the one Android fact Dart cannot read for
 * itself — where this app may keep files — is answered here. The channel
 * answers that and nothing else: it is a door, and it opens onto one string.
 *
 * The Dart side treats a missing answer as "nowhere to write" and runs with
 * its identity in memory, so a platform that has not implemented this channel
 * (Windows, where the environment already says where to write) is not an error.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cn.hnasct.local_transfer/paths",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appDataDirectory" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
