package io.menghun3_cn.zhu_ye_local_im

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The application's own platform channel.
 *
 * This project ships no plugins, so the Android facts Dart cannot answer for
 * itself come through the channels registered here: where this app may keep
 * files, what the system's installers and handlers can be handed, and nothing
 * else — each is a door onto one question.
 *
 * The Dart side treats a missing answer as "nowhere to write" and runs with
 * its identity in memory, so a platform that has not implemented this channel
 * (Windows, where the environment already says where to write) is not an error.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The service only exists to keep this process — and the sockets and
        // Dart timers inside it — at foreground priority while the app is
        // alive. Starting it here is legal because an Activity's onCreate is
        // always foreground; Android 12+ forbids the same call from the
        // background. It stops itself when the user swipes the app away.
        ContextCompat.startForegroundService(
            this,
            Intent(this, LocalTransferForegroundService::class.java),
        )
    }

    override fun onResume() {
        super.onResume()
        askNotificationPermissionOnce()
    }

    /**
     * Android 13+ hides an app's foreground-service notification until the
     * POST_NOTIFICATIONS runtime permission is granted. The service still
     * runs without it — only the shade entry is missing — but a user who
     * never sees the notification has no idea the app is deliberately
     * staying online, so the permission is asked once, here, where the app
     * is already in front of them.
     */
    private fun askNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (prefs.getBoolean(KEY_NOTIFICATIONS_ASKED, false)) return
        prefs.edit().putBoolean(KEY_NOTIFICATIONS_ASKED, true).apply()
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

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
            "cn.hnasct.local_transfer/files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> openPath(call, result, directory = false)
                "openFolder" -> openPath(call, result, directory = true)
                "share" -> sharePaths(call, result)
                "copyFiles" -> copyPaths(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cn.hnasct.local_transfer/browser",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> openUrl(call, result)
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
     * Hands a file — or the folder holding it — to Android's own handlers.
     *
     * Both go through the FileProvider because another application may be
     * handed a `content://` URI with a read grant and nothing else: a
     * `file://` path is one Android refuses to open for us. A file is offered
     * as its real MIME type, so an APK reaches the package installer and a
     * document reaches whatever application claims it; a folder is offered as
     * `resource/folder` for the file managers that understand it — and for
     * the ones that do not, and for the app's private directories none of
     * them can browse, the answer is simply false.
     */
    private fun openPath(call: MethodCall, result: MethodChannel.Result, directory: Boolean) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("bad_arguments", "openFile/openFolder expect a path", null)
            return
        }
        val target = File(path)
        val usable = if (directory) target.isDirectory else target.isFile
        if (!usable) {
            result.error("missing_path", "nothing to open at $path", path)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_file_provider",
                target,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, if (directory) "resource/folder" else mimeOf(target))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (packageManager.queryIntentActivities(intent, 0).isEmpty()) {
                result.success(false)
                return
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("open_failed", error.message, path)
        }
    }

    /**
     * Hands files to Android's share sheet — the chooser that lists WeChat and
     * every other application that takes one.
     *
     * Every path becomes a `content://` URI through the same FileProvider
     * `openPath` uses: `update_paths.xml` exposes filesDir, cacheDir and
     * external storage, which covers where this app keeps received and picked
     * files. One file goes as `ACTION_SEND` under its real MIME type; several
     * go as `ACTION_SEND_MULTIPLE` under a wildcard MIME type, and the
     * chooser decides what it will take.
     *
     * There is deliberately no `queryIntentActivities` pre-check: on Android
     * 11+ package visibility would filter the answer unless the manifest
     * declared the schemes, and a filtered-empty answer would report "nothing
     * can take this" while WeChat sits right there. `startActivity` resolves
     * the sheet itself; an empty one throws and is answered as an error, which
     * Dart reads as false — the same sentence either way.
     */
    private fun sharePaths(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<List<String>>("paths")
        val files = raw.orEmpty().map { File(it) }.filter { it.isFile }
        if (files.isEmpty()) {
            result.success(false)
            return
        }
        try {
            val uris = files.map {
                FileProvider.getUriForFile(
                    this,
                    "$packageName.update_file_provider",
                    it,
                )
            }
            val intent = if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = mimeOf(files[0])
                    putExtra(Intent.EXTRA_STREAM, uris[0])
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "*/*"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                }
            }
            // The grant flag alone covers the intent, but receivers read the
            // URIs through the clip data — carrying every URI there is what
            // makes a multi-file share readable by all of them, not just the
            // first.
            val clip = ClipData.newUri(contentResolver, null, uris.first())
            for (uri in uris.drop(1)) {
                clip.addItem(ClipData.Item(uri))
            }
            intent.clipData = clip
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("share_failed", error.message, null)
        }
    }

    /**
     * Puts files on the clipboard the way a file manager's copy does: as
     * `content://` URIs another application may be granted to read.
     *
     * The URIs come from the same FileProvider `sharePaths` uses, so every
     * directory a received or picked file can live in is already covered. No
     * grant flag is set here: Android's ClipboardService grants read on a
     * clip's URIs to each package that pulls `getPrimaryClip`, which is the
     * same mechanism the pasteboard plugin's image copy relies on.
     */
    private fun copyPaths(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<List<String>>("paths")
        val files = raw.orEmpty().map { File(it) }.filter { it.isFile }
        if (files.isEmpty()) {
            result.success(false)
            return
        }
        try {
            val uris = files.map {
                FileProvider.getUriForFile(
                    this,
                    "$packageName.update_file_provider",
                    it,
                )
            }
            val clip = ClipData.newUri(contentResolver, null, uris.first())
            for (uri in uris.drop(1)) {
                clip.addItem(ClipData.Item(uri))
            }
            val clipboard =
                getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(clip)
            result.success(true)
        } catch (error: Exception) {
            result.error("copy_failed", error.message, null)
        }
    }

    /**
     * Hands a web address to whatever browser the user has.
     *
     * The address comes out of a received message, so it is checked here as
     * well as on the Dart side: only http and https with a real host are
     * offered to `ACTION_VIEW`, and anything else answers false rather than
     * firing an intent at a scheme the system would have to guess about.
     */
    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("url")
        val uri = raw?.let { runCatching { Uri.parse(it) }.getOrNull() }
        if (uri == null ||
            (uri.scheme != "http" && uri.scheme != "https") ||
            uri.host.isNullOrEmpty()
        ) {
            result.success(false)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (packageManager.queryIntentActivities(intent, 0).isEmpty()) {
                result.success(false)
                return
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("open_failed", error.message, raw)
        }
    }

    /**
     * The MIME type [file] is offered under. `MimeTypeMap` knows the common
     * ones; the APK type is named here because it is the one this app most
     * expects to be opened — a received update is exactly that file.
     */
    private fun mimeOf(file: File): String {
        val extension = file.extension.lowercase()
        if (extension == "apk") return "application/vnd.android.package-archive"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "*/*"
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

    private companion object {
        const val PREFS_NAME = "local_transfer"
        const val KEY_NOTIFICATIONS_ASKED = "notification_permission_asked"
        const val REQUEST_POST_NOTIFICATIONS = 1
    }
}
