package io.menghun3_cn.zhu_ye_local_im

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
            "io.menghun3_cn.zhu_ye_local_im/paths",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "appDataDirectory" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cn.hnasct.local_transfer/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Hands a checked APK to Android's package installer.
     *
     * The file lives under filesDir/update, which the FileProvider in the
     * manifest exposes by that name. Android 8 and later may first require the
     * user to allow this app to install unknown apps; opening that settings
     * page is answered as "permission" so Dart can explain the next step.
     */
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_arguments", "installApk expects a path", null)
            return
        }
        val packageFile = File(path)
        if (!packageFile.isFile) {
            result.error("missing_apk", "the update APK is not there", path)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                startActivity(settings)
                result.success("permission")
                return
            }
            val apk = FileProvider.getUriForFile(
                this,
                "$packageName.update_file_provider",
                packageFile,
            )
            val installer = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apk, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installer)
            result.success("started")
        } catch (error: Exception) {
            result.error("install_failed", error.message, path)
        }
    }
}
