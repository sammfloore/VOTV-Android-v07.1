from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path.cwd()
ANDROID = ROOT / "android"
MANIFEST = ANDROID / "app/src/main/AndroidManifest.xml"


def insert_after_android_opening(content: str, block: str) -> str:
    marker = "android {"
    if block.strip() in content:
        return content
    position = content.find(marker)
    if position == -1:
        raise RuntimeError("No se encontró el bloque android en Gradle")
    insert_at = position + len(marker)
    return content[:insert_at] + "\n" + block + content[insert_at:]


def patch_manifest() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
        '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />',
        '<uses-permission android:name="android.permission.WAKE_LOCK" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    ]
    features = [
        '<uses-feature android:name="android.software.leanback" android:required="false" />',
        '<uses-feature android:name="android.hardware.touchscreen" android:required="false" />',
    ]
    for declaration in [*permissions, *features]:
        if declaration not in text:
            first_close = text.find(">")
            text = (
                text[: first_close + 1]
                + "\n    "
                + declaration
                + text[first_close + 1 :]
            )

    text = re.sub(r'android:label="[^"]*"', 'android:label="AVO TV"', text, count=1)
    text = re.sub(r'\s+android:extractNativeLibs="(?:true|false)"', "", text)

    application_attributes = [
        'android:usesCleartextTraffic="true"',
        'android:networkSecurityConfig="@xml/network_security_config"',
        'android:allowBackup="false"',
        'android:hardwareAccelerated="true"',
        'android:roundIcon="@mipmap/ic_launcher_round"',
        'android:banner="@drawable/avo_tv_banner"',
    ]
    for attribute in application_attributes:
        if attribute not in text:
            text = text.replace("<application", f"<application\n        {attribute}", 1)

    activity_pattern = re.compile(
        r'<activity\b(?=[^>]*android:name="(?:\.MainActivity|mx\.avotv\.avo_tv\.MainActivity)")[^>]*>',
        re.S,
    )
    match = activity_pattern.search(text)
    if match is None:
        raise RuntimeError("No se encontró MainActivity en AndroidManifest.xml")
    activity_tag = match.group(0)
    activity_attributes = [
        'android:resizeableActivity="true"',
    ]
    for attribute in activity_attributes:
        if attribute not in activity_tag:
            activity_tag = activity_tag[:-1] + f"\n            {attribute}>"

    config_match = re.search(r'android:configChanges="([^"]*)"', activity_tag)
    required_changes = [
        "orientation",
        "screenSize",
        "smallestScreenSize",
        "screenLayout",
    ]
    if config_match is None:
        activity_tag = activity_tag[:-1] + (
            '\n            android:configChanges="'
            + "|".join(required_changes)
            + '">'
        )
    else:
        changes = [value for value in config_match.group(1).split("|") if value]
        for value in required_changes:
            if value not in changes:
                changes.append(value)
        activity_tag = (
            activity_tag[: config_match.start(1)]
            + "|".join(changes)
            + activity_tag[config_match.end(1) :]
        )
    text = text[: match.start()] + activity_tag + text[match.end() :]

    leanback_filter = """
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
"""
    if "android.intent.category.LEANBACK_LAUNCHER" not in text:
        main_close = text.find("</activity>", match.start())
        if main_close == -1:
            raise RuntimeError("No se encontró el cierre de MainActivity")
        text = text[:main_close] + leanback_filter + text[main_close:]

    player_activity = """
        <activity
            android:name=".PlayerActivity"
            android:theme="@style/LaunchTheme"
            android:exported="false"
            android:launchMode="singleTask"
            android:excludeFromRecents="true"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:supportsPictureInPicture="true"
            android:resizeableActivity="true"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
        </activity>
"""
    if 'android:name=".PlayerActivity"' not in text:
        text = text.replace("</application>", player_activity + "    </application>", 1)

    receiver = """
        <receiver
            android:name=".PipActionReceiver"
            android:enabled="true"
            android:exported="false" />
"""
    if 'android:name=".PipActionReceiver"' not in text:
        text = text.replace("</application>", receiver + "    </application>", 1)

    recording_service = """
        <service
            android:name=".RecordingService"
            android:enabled="true"
            android:exported="false"
            android:stopWithTask="false"
            android:foregroundServiceType="dataSync" />
"""
    if 'android:name=".RecordingService"' not in text:
        text = text.replace(
            "</application>",
            recording_service + "    </application>",
            1,
        )

    MANIFEST.write_text(text, encoding="utf-8")

    network_config = ANDROID / "app/src/main/res/xml/network_security_config.xml"
    network_config.parent.mkdir(parents=True, exist_ok=True)
    network_config.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
</network-security-config>
""",
        encoding="utf-8",
    )


def patch_gradle() -> None:
    kts = ANDROID / "app/build.gradle.kts"
    if kts.exists():
        content = kts.read_text(encoding="utf-8")
        content = content.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
        block = """    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }
"""
        if "useLegacyPackaging = true" not in content:
            content = insert_after_android_opening(content, block)
        kts.write_text(content, encoding="utf-8")

    groovy = ANDROID / "app/build.gradle"
    if groovy.exists():
        content = groovy.read_text(encoding="utf-8")
        content = content.replace(
            "minSdkVersion flutter.minSdkVersion",
            "minSdkVersion 24",
        )
        block = """    packagingOptions {
        jniLibs {
            useLegacyPackaging true
        }
    }
"""
        if "useLegacyPackaging true" not in content and "useLegacyPackaging = true" not in content:
            content = insert_after_android_opening(content, block)
        groovy.write_text(content, encoding="utf-8")

    settings_kts = ANDROID / "settings.gradle.kts"
    if settings_kts.exists():
        content = settings_kts.read_text(encoding="utf-8")
        content = re.sub(
            r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"[^"]+"',
            'id("org.jetbrains.kotlin.android") version "2.1.0"',
            content,
        )
        settings_kts.write_text(content, encoding="utf-8")

    settings = ANDROID / "settings.gradle"
    if settings.exists():
        content = settings.read_text(encoding="utf-8")
        content = re.sub(
            r'id\s+["\']org\.jetbrains\.kotlin\.android["\']\s+version\s+["\'][^"\']+["\']',
            'id "org.jetbrains.kotlin.android" version "2.1.0"',
            content,
        )
        settings.write_text(content, encoding="utf-8")

    root_gradle = ANDROID / "build.gradle"
    if root_gradle.exists():
        content = root_gradle.read_text(encoding="utf-8")
        content = re.sub(
            r"ext\.kotlin_version\s*=\s*['\"][^'\"]+['\"]",
            "ext.kotlin_version = '2.1.0'",
            content,
        )
        root_gradle.write_text(content, encoding="utf-8")


def copy_branding() -> None:
    source_root = ROOT / "assets/branding/android"
    target_root = ANDROID / "app/src/main/res"
    for source_dir in source_root.glob("mipmap-*"):
        target_dir = target_root / source_dir.name
        target_dir.mkdir(parents=True, exist_ok=True)
        for filename in ("ic_launcher.png", "ic_launcher_round.png"):
            source = source_dir / filename
            if source.exists():
                shutil.copy2(source, target_dir / filename)

    banner = ROOT / "assets/branding/avo_tv_tv_banner.png"
    drawable = target_root / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    if banner.exists():
        shutil.copy2(banner, drawable / "avo_tv_banner.png")


def write_main_activity() -> None:
    main_activity = ANDROID / "app/src/main/kotlin/mx/avotv/avo_tv/MainActivity.kt"
    main_activity.parent.mkdir(parents=True, exist_ok=True)
    main_activity.write_text(
        r'''package mx.avotv.avo_tv

import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "mx.avotv/platform"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openPlayer" -> {
                    val payload = call.argument<String>("payload")
                    val bringToFront = call.argument<Boolean>("bringToFront") != false
                    if (payload.isNullOrBlank()) {
                        result.error("PLAYER_DATA", "No se recibieron los datos del video", null)
                    } else {
                        val activePlayer = PlayerActivity.activeInstance
                        if (activePlayer != null && !activePlayer.isFinishing) {
                            activePlayer.replacePayload(payload)
                            if (bringToFront) {
                                startActivity(
                                    Intent(this, PlayerActivity::class.java).apply {
                                        addFlags(
                                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                        )
                                    },
                                )
                            }
                        } else {
                            startActivity(
                                Intent(this, PlayerActivity::class.java).apply {
                                    putExtra(PlayerActivity.EXTRA_PAYLOAD, payload)
                                },
                            )
                        }
                        result.success(true)
                    }
                }
                "hasActivePlayer" -> {
                    val activePlayer = PlayerActivity.activeInstance
                    result.success(activePlayer != null && !activePlayer.isFinishing)
                }
                "openCastSettings" -> openCastSettings(result)
                "isTelevision" -> result.success(isTelevision())
                "isPipSupported" -> result.success(isPipSupported())
                "isPipAllowed" -> result.success(isPipAllowed())
                "isInPipMode" -> result.success(false)
                "configurePip" -> result.success(null)
                "enterPip" -> result.success(false)
                "openPipSettings" -> openPipSettings(result)
                "closePipActivity" -> result.success(null)
                "getPlayerPayload" -> result.success(null)
                else -> if (!RecordingBridge.handle(this, call, result)) {
                    result.notImplemented()
                }
            }
        }
    }

    fun notifyPlaybackStateChanged() {
        runOnUiThread {
            methodChannel?.invokeMethod("playbackStateChanged", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (RecordingPermissionBroker.onResult(requestCode, permissions, grantResults)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        methodChannel = null
        super.onDestroy()
    }

    companion object {
        var activeInstance: MainActivity? = null
            private set
    }

    private fun isTelevision(): Boolean {
        val televisionUiMode =
            (resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK) ==
                Configuration.UI_MODE_TYPE_TELEVISION
        return televisionUiMode ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun openCastSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
            result.success(null)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                result.success(null)
            } catch (error: Exception) {
                result.error("CAST_SETTINGS", error.message, null)
            }
        }
    }

    private fun isPipSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun isPipAllowed(): Boolean {
        if (!isPipSupported()) return false
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    }

    private fun openPipSettings(result: MethodChannel.Result) {
        try {
            val pipSettingsIntent = Intent(
                "android.settings.PICTURE_IN_PICTURE_SETTINGS",
                Uri.parse("package:$packageName"),
            )
            val intent = if (pipSettingsIntent.resolveActivity(packageManager) != null) {
                pipSettingsIntent
            } else {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("PIP_SETTINGS", error.message, null)
        }
    }
}

class PlayerActivity : FlutterActivity() {
    private val channelName = "mx.avotv/platform"
    private var methodChannel: MethodChannel? = null
    private var pipEnabled = false
    private var pipAutoEnter = false
    private var pipIsPlaying = false
    private var pipHasNext = false
    private var pipTitle = "AVO TV"
    private var pipSubtitle = ""

    override fun getDartEntrypointFunctionName(): String = "playerMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        activeInstance = this
        super.onCreate(savedInstanceState)
    }

    fun replacePayload(payload: String) {
        intent.putExtra(EXTRA_PAYLOAD, payload)
        runOnUiThread {
            methodChannel?.invokeMethod(
                "replacePlayerPayload",
                mapOf("payload" to payload),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        PipActionReceiver.callback = { action ->
            runOnUiThread {
                methodChannel?.invokeMethod(
                    "pipAction",
                    mapOf("action" to action),
                )
            }
        }
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPlayerPayload" -> result.success(
                    intent.getStringExtra(EXTRA_PAYLOAD),
                )
                "openPlayer" -> result.success(false)
                "hasActivePlayer" -> result.success(true)
                "openCastSettings" -> openCastSettings(result)
                "isTelevision" -> result.success(isTelevision())
                "isPipSupported" -> result.success(isPipSupported())
                "isPipAllowed" -> result.success(isPipAllowed())
                "isInPipMode" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                        isInPictureInPictureMode,
                )
                "configurePip" -> {
                    pipEnabled = call.argument<Boolean>("enabled") == true
                    pipAutoEnter = call.argument<Boolean>("autoEnter") == true
                    pipIsPlaying = call.argument<Boolean>("isPlaying") == true
                    pipHasNext = call.argument<Boolean>("hasNext") == true
                    pipTitle = call.argument<String>("title") ?: "AVO TV"
                    pipSubtitle = call.argument<String>("subtitle") ?: ""
                    updatePictureInPictureParams()
                    result.success(null)
                }
                "enterPip" -> result.success(enterPip())
                "openPipSettings" -> openPipSettings(result)
                "closePipActivity" -> {
                    MainActivity.activeInstance?.notifyPlaybackStateChanged()
                    result.success(null)
                    finish()
                    @Suppress("DEPRECATION")
                    overridePendingTransition(0, 0)
                }
                else -> if (!RecordingBridge.handle(this, call, result)) {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isTelevision(): Boolean {
        val televisionUiMode =
            (resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK) ==
                Configuration.UI_MODE_TYPE_TELEVISION
        return televisionUiMode ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun openCastSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
            result.success(null)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                result.success(null)
            } catch (error: Exception) {
                result.error("CAST_SETTINGS", error.message, null)
            }
        }
    }

    private fun isPipSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun isPipAllowed(): Boolean {
        if (!isPipSupported()) return false
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    }

    private fun openPipSettings(result: MethodChannel.Result) {
        if (!isPipSupported()) {
            result.error("PIP_UNSUPPORTED", "Picture-in-Picture no está disponible", null)
            return
        }
        try {
            val pipSettingsIntent = Intent(
                "android.settings.PICTURE_IN_PICTURE_SETTINGS",
                Uri.parse("package:$packageName"),
            )
            val intent = if (pipSettingsIntent.resolveActivity(packageManager) != null) {
                pipSettingsIntent
            } else {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("PIP_SETTINGS", error.message, null)
        }
    }

    private fun enterPip(): Boolean {
        if (!pipEnabled || !isPipAllowed() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return try {
            updatePictureInPictureParams()
            enterPictureInPictureMode(buildPictureInPictureParams())
        } catch (_: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S &&
            pipEnabled && pipAutoEnter && pipIsPlaying
        ) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod(
            "pipModeChanged",
            mapOf("isInPip" to isInPictureInPictureMode),
        )
    }

    private fun updatePictureInPictureParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPipSupported()) return
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (_: Exception) {
            // Algunos fabricantes rechazan cambios durante una transición.
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(buildPipActions())

        val sourceRect = Rect()
        if (window.decorView.getGlobalVisibleRect(sourceRect)) {
            builder.setSourceRectHint(sourceRect)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(
                pipEnabled && pipAutoEnter && pipIsPlaying,
            )
            builder.setSeamlessResizeEnabled(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            builder.setTitle(pipTitle)
            builder.setSubtitle(pipSubtitle)
        }
        return builder.build()
    }

    private fun buildPipActions(): List<RemoteAction> {
        val actions = mutableListOf<RemoteAction>()
        actions += pipAction(
            action = PipActionReceiver.ACTION_TOGGLE,
            requestCode = 110,
            iconResource = if (pipIsPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            },
            title = if (pipIsPlaying) "Pausar" else "Reproducir",
        )
        if (pipHasNext) {
            actions += pipAction(
                action = PipActionReceiver.ACTION_NEXT,
                requestCode = 111,
                iconResource = android.R.drawable.ic_media_next,
                title = "Siguiente episodio",
            )
        }
        actions += pipAction(
            action = PipActionReceiver.ACTION_CLOSE,
            requestCode = 112,
            iconResource = android.R.drawable.ic_menu_close_clear_cancel,
            title = "Cerrar reproducción",
        )
        return actions
    }

    private fun pipAction(
        action: String,
        requestCode: Int,
        iconResource: Int,
        title: String,
    ): RemoteAction {
        val intent = Intent(this, PipActionReceiver::class.java).apply {
            this.action = action
            setPackage(packageName)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val icon = Icon.createWithResource(this, iconResource)
        return RemoteAction(icon, title, title, pendingIntent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (RecordingPermissionBroker.onResult(requestCode, permissions, grantResults)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        MainActivity.activeInstance?.notifyPlaybackStateChanged()
        if (activeInstance === this) activeInstance = null
        PipActionReceiver.callback = null
        methodChannel = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_PAYLOAD = "mx.avotv.player.PAYLOAD"
        var activeInstance: PlayerActivity? = null
            private set
    }
}

class PipActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val mapped = when (intent?.action) {
            ACTION_TOGGLE -> "toggle"
            ACTION_NEXT -> "next"
            ACTION_CLOSE -> "close"
            else -> return
        }
        callback?.invoke(mapped)
    }

    companion object {
        const val ACTION_TOGGLE = "mx.avotv.action.PIP_TOGGLE"
        const val ACTION_NEXT = "mx.avotv.action.PIP_NEXT"
        const val ACTION_CLOSE = "mx.avotv.action.PIP_CLOSE"
        var callback: ((String) -> Unit)? = null
    }
}
''',
        encoding="utf-8",
    )


def write_recording_service() -> None:
    recording_service = ANDROID / "app/src/main/kotlin/mx/avotv/avo_tv/RecordingService.kt"
    recording_service.parent.mkdir(parents=True, exist_ok=True)
    recording_service.write_text(
        r'''package mx.avotv.avo_tv

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

private const val RECORDING_PREFS = "avo_recording_state"
private const val ACTIVE_RECORDING_KEY = "active_id"
private const val RECORDING_DIRECTORY = "recordings"
private const val MINIMUM_FREE_BYTES = 3L * 1024L * 1024L * 1024L
private const val STORAGE_RESERVE_BYTES = 1L * 1024L * 1024L * 1024L

internal data class RecordingMeta(
    val id: String,
    val sourceChannelId: String,
    val title: String,
    val channelTitle: String,
    val posterUrl: String,
    val localPath: String,
    val startedAt: Long,
    val endedAt: Long,
    val durationSeconds: Long,
    val sizeBytes: Long,
    val status: String,
    val errorMessage: String,
    val maxDurationMinutes: Int,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("sourceChannelId", sourceChannelId)
        put("title", title)
        put("channelTitle", channelTitle)
        put("posterUrl", posterUrl)
        put("localPath", localPath)
        put("startedAt", startedAt)
        put("endedAt", endedAt)
        put("durationSeconds", durationSeconds)
        put("sizeBytes", sizeBytes)
        put("status", status)
        put("errorMessage", errorMessage)
        put("maxDurationMinutes", maxDurationMinutes)
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "sourceChannelId" to sourceChannelId,
        "title" to title,
        "channelTitle" to channelTitle,
        "posterUrl" to posterUrl,
        "localPath" to localPath,
        "startedAt" to startedAt,
        "endedAt" to endedAt,
        "durationSeconds" to durationSeconds,
        "sizeBytes" to sizeBytes,
        "status" to status,
        "errorMessage" to errorMessage,
        "maxDurationMinutes" to maxDurationMinutes,
    )

    companion object {
        fun fromJson(json: JSONObject): RecordingMeta = RecordingMeta(
            id = json.optString("id"),
            sourceChannelId = json.optString("sourceChannelId"),
            title = json.optString("title", "Grabación"),
            channelTitle = json.optString("channelTitle", "Canal en vivo"),
            posterUrl = json.optString("posterUrl"),
            localPath = json.optString("localPath"),
            startedAt = json.optLong("startedAt"),
            endedAt = json.optLong("endedAt"),
            durationSeconds = json.optLong("durationSeconds"),
            sizeBytes = json.optLong("sizeBytes"),
            status = json.optString("status", "interrupted"),
            errorMessage = json.optString("errorMessage"),
            maxDurationMinutes = json.optInt("maxDurationMinutes", 180),
        )
    }
}

internal object RecordingRepository {
    fun directory(context: Context): File =
        File(context.filesDir, RECORDING_DIRECTORY).apply { mkdirs() }

    fun packageDirectory(context: Context, id: String): File =
        File(directory(context), id).apply { mkdirs() }

    fun sidecar(context: Context, id: String): File =
        File(directory(context), "$id.avo.json")

    fun write(context: Context, meta: RecordingMeta) {
        val target = sidecar(context, meta.id)
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(meta.toJson().toString())
        if (!temporary.renameTo(target)) {
            target.writeText(meta.toJson().toString())
            temporary.delete()
        }
    }

    fun read(context: Context, id: String): RecordingMeta? {
        val file = sidecar(context, id)
        if (!file.exists()) return null
        return try {
            RecordingMeta.fromJson(JSONObject(file.readText()))
        } catch (_: Exception) {
            null
        }
    }

    fun mediaSize(meta: RecordingMeta): Long {
        val path = File(meta.localPath)
        val packageRoot = path.parentFile?.takeIf { it.name == meta.id }
        if (packageRoot != null && packageRoot.exists()) {
            return packageRoot.walkTopDown()
                .filter { it.isFile && !it.name.endsWith(".m3u8") }
                .sumOf { it.length() }
        }
        return if (path.exists()) path.length() else 0L
    }

    fun list(context: Context): List<RecordingMeta> {
        val activeId = activeId(context)
        val serviceRunning = RecordingService.isRunning()
        return directory(context)
            .listFiles { file -> file.name.endsWith(".avo.json") }
            ?.mapNotNull { file ->
                try {
                    var meta = repairStoredMedia(
                        context,
                        RecordingMeta.fromJson(JSONObject(file.readText())),
                    )
                    val size = mediaSize(meta)
                    val elapsed = if (meta.status == "recording") {
                        max(0L, (System.currentTimeMillis() - meta.startedAt) / 1000L)
                    } else {
                        meta.durationSeconds
                    }
                    val startupGraceActive = activeId == meta.id &&
                        System.currentTimeMillis() - meta.startedAt <= 20_000L
                    if (meta.status == "recording" &&
                        (!serviceRunning || activeId != meta.id) &&
                        !startupGraceActive
                    ) {
                        meta = meta.copy(
                            endedAt = System.currentTimeMillis(),
                            durationSeconds = elapsed,
                            sizeBytes = size,
                            status = if (size >= 1024L) "interrupted" else "failed",
                            errorMessage = "La grabación se interrumpió antes de finalizar.",
                        )
                        write(context, meta)
                        if (activeId == meta.id) clearActive(context, meta.id)
                    } else if (size != meta.sizeBytes || elapsed != meta.durationSeconds) {
                        meta = meta.copy(sizeBytes = size, durationSeconds = elapsed)
                    }
                    if (size <= 0L && meta.status != "recording") null else meta
                } catch (_: Exception) {
                    null
                }
            }
            ?.sortedByDescending { it.startedAt }
            ?: emptyList()
    }

    private fun repairStoredMedia(context: Context, original: RecordingMeta): RecordingMeta {
        var meta = original
        val media = File(meta.localPath)
        if (meta.status != "recording" && media.isFile &&
            media.extension.equals("ts", ignoreCase = true)
        ) {
            try {
                val header = media.inputStream().buffered().use { input ->
                    val bytes = ByteArray(256)
                    val count = input.read(bytes)
                    if (count > 0) String(bytes, 0, count, Charsets.UTF_8).trimStart() else ""
                }
                if (header.startsWith("#EXTM3U")) {
                    val corrected = File(media.parentFile, "${media.nameWithoutExtension}.m3u8")
                    if (!media.renameTo(corrected)) {
                        media.copyTo(corrected, overwrite = true)
                        media.delete()
                    }
                    meta = meta.copy(localPath = corrected.absolutePath)
                    write(context, meta)
                }
            } catch (_: Exception) {
            }
        }

        val localPath = File(meta.localPath)
        val packageRoot = localPath.parentFile?.takeIf { it.name == meta.id }
        if (meta.status != "recording" && packageRoot != null && packageRoot.exists()) {
            packageRoot.listFiles { file -> file.name.endsWith(".part") }
                ?.forEach { part ->
                    val completed = File(part.parentFile, part.name.removeSuffix(".part"))
                    if (!part.renameTo(completed)) {
                        try {
                            part.copyTo(completed, overwrite = true)
                            part.delete()
                        } catch (_: Exception) {
                        }
                    }
                }
            if (!localPath.exists()) {
                val directFiles = packageRoot.listFiles { file ->
                    file.isFile && file.name.matches(Regex("direct_\\d+\\.ts"))
                }?.sortedBy { it.name }.orEmpty()
                if (directFiles.isNotEmpty()) {
                    val perFileDuration = max(
                        0.1,
                        meta.durationSeconds.toDouble() / directFiles.size.toDouble(),
                    )
                    val playlist = buildString {
                        appendLine("#EXTM3U")
                        appendLine("#EXT-X-VERSION:3")
                        appendLine("#EXT-X-PLAYLIST-TYPE:VOD")
                        appendLine("#EXT-X-TARGETDURATION:${ceil(perFileDuration).toInt().coerceAtLeast(1)}")
                        appendLine("#EXT-X-MEDIA-SEQUENCE:0")
                        directFiles.forEach { file ->
                            appendLine("#EXTINF:${String.format(Locale.US, "%.3f", perFileDuration)},")
                            appendLine(file.name)
                        }
                        appendLine("#EXT-X-ENDLIST")
                    }
                    localPath.writeText(playlist)
                }
            }
        }
        return meta
    }

    fun active(context: Context): RecordingMeta? {
        val id = activeId(context) ?: return null
        return list(context).firstOrNull { it.id == id && it.status == "recording" }
    }

    fun delete(context: Context, id: String): Boolean {
        if (activeId(context) == id && RecordingService.isActive(id)) return false
        val meta = read(context, id)
        var ok = true
        if (meta != null) {
            val media = File(meta.localPath)
            val packageRoot = media.parentFile?.takeIf { it.name == id }
            if (packageRoot != null && packageRoot.exists()) {
                if (!packageRoot.deleteRecursively()) ok = false
            } else if (media.exists() && !media.delete()) {
                ok = false
            }
        }
        val sidecar = sidecar(context, id)
        if (sidecar.exists() && !sidecar.delete()) ok = false
        return ok
    }

    fun setActive(context: Context, id: String) {
        context.getSharedPreferences(RECORDING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ACTIVE_RECORDING_KEY, id)
            .apply()
    }

    fun clearActive(context: Context, id: String) {
        val prefs = context.getSharedPreferences(RECORDING_PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(ACTIVE_RECORDING_KEY, null) == id) {
            prefs.edit().remove(ACTIVE_RECORDING_KEY).apply()
        }
    }

    fun activeId(context: Context): String? =
        context.getSharedPreferences(RECORDING_PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_RECORDING_KEY, null)

    fun capability(context: Context): Map<String, Any?> {
        val isTelevision = isTelevision(context)
        val available = StatFs(context.filesDir.absolutePath).availableBytes
        val permissionGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        val supported = !isTelevision && available >= MINIMUM_FREE_BYTES
        val reason = when {
            isTelevision -> "La grabación local está disponible en teléfonos y tabletas con almacenamiento suficiente."
            available < MINIMUM_FREE_BYTES ->
                "Se necesitan al menos 3 GB libres para proteger el almacenamiento del dispositivo."
            else -> ""
        }
        return mapOf(
            "supported" to supported,
            "isTelevision" to isTelevision,
            "availableBytes" to available,
            "minimumRequiredBytes" to MINIMUM_FREE_BYTES,
            "reserveBytes" to STORAGE_RESERVE_BYTES,
            "notificationPermissionGranted" to permissionGranted,
            "reason" to reason,
        )
    }

    private fun isTelevision(context: Context): Boolean {
        val televisionUiMode =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK) ==
                Configuration.UI_MODE_TYPE_TELEVISION
        return televisionUiMode ||
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }
}

internal object RecordingPermissionBroker {
    private const val requestCode = 7318
    private var pendingResult: MethodChannel.Result? = null

    @Synchronized
    fun request(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingResult != null) {
            result.success(false)
            return
        }
        pendingResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            requestCode,
        )
    }

    @Synchronized
    fun onResult(
        code: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (code != requestCode) return false
        val granted = permissions.indices.any { index ->
            permissions[index] == Manifest.permission.POST_NOTIFICATIONS &&
                grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
        }
        pendingResult?.success(granted)
        pendingResult = null
        return true
    }
}

internal object RecordingBridge {
    fun handle(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ): Boolean {
        when (call.method) {
            "recordingCapability" -> result.success(RecordingRepository.capability(activity))
            "requestRecordingNotificationPermission" ->
                RecordingPermissionBroker.request(activity, result)
            "openRecordingNotificationSettings" -> {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                }
                try {
                    activity.startActivity(intent)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("NOTIFICATION_SETTINGS", error.message, null)
                }
            }
            "listLiveRecordings" -> result.success(
                RecordingRepository.list(activity).map { it.toMap() },
            )
            "activeLiveRecording" -> result.success(
                RecordingRepository.active(activity)?.toMap(),
            )
            "deleteLiveRecording" -> {
                val id = call.argument<String>("id").orEmpty()
                result.success(id.isNotBlank() && RecordingRepository.delete(activity, id))
            }
            "startLiveRecording" -> start(activity, call, result)
            "stopLiveRecording" -> stop(activity, result)
            else -> return false
        }
        return true
    }

    private fun start(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val capability = RecordingRepository.capability(activity)
        if (capability["supported"] != true) {
            result.success(
                mapOf(
                    "success" to false,
                    "message" to (capability["reason"] ?: "Grabación no disponible."),
                ),
            )
            return
        }
        val current = RecordingRepository.active(activity)
        if (current != null) {
            result.success(
                mapOf(
                    "success" to false,
                    "message" to "Ya existe una grabación en curso.",
                ),
            )
            return
        }
        val urls = call.argument<List<*>>("urls")
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.startsWith("http://") || it.startsWith("https://") }
            ?.distinct()
            .orEmpty()
        if (urls.isEmpty()) {
            result.success(
                mapOf(
                    "success" to false,
                    "message" to "Este canal no ofrece una señal compatible para grabar.",
                ),
            )
            return
        }
        val id = "rec-${System.currentTimeMillis()}-${UUID.randomUUID().toString().take(8)}"
        val title = call.argument<String>("title")?.trim().orEmpty().ifBlank { "Grabación" }
        val channelTitle = call.argument<String>("channelTitle")?.trim().orEmpty()
            .ifBlank { "Canal en vivo" }
        val packageDirectory = RecordingRepository.packageDirectory(activity, id)
        val output = File(packageDirectory, "index.m3u8")
        val maxMinutes = (call.argument<Int>("maxDurationMinutes") ?: 180)
            .coerceIn(30, 240)
        val meta = RecordingMeta(
            id = id,
            sourceChannelId = call.argument<String>("sourceChannelId").orEmpty(),
            title = title,
            channelTitle = channelTitle,
            posterUrl = call.argument<String>("posterUrl").orEmpty(),
            localPath = output.absolutePath,
            startedAt = System.currentTimeMillis(),
            endedAt = 0L,
            durationSeconds = 0L,
            sizeBytes = 0L,
            status = "recording",
            errorMessage = "",
            maxDurationMinutes = maxMinutes,
        )
        RecordingRepository.write(activity, meta)
        RecordingRepository.setActive(activity, id)
        val intent = Intent(activity, RecordingService::class.java).apply {
            action = RecordingService.ACTION_START
            putExtra(RecordingService.EXTRA_ID, id)
            putStringArrayListExtra(
                RecordingService.EXTRA_URLS,
                java.util.ArrayList<String>().apply { addAll(urls) },
            )
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
            result.success(
                mapOf(
                    "success" to true,
                    "message" to "Grabación iniciada.",
                    "id" to id,
                ),
            )
        } catch (error: Exception) {
            RecordingRepository.clearActive(activity, id)
            RecordingRepository.delete(activity, id)
            result.success(
                mapOf(
                    "success" to false,
                    "message" to (error.message ?: "Android no pudo iniciar la grabación."),
                ),
            )
        }
    }

    private fun stop(activity: Activity, result: MethodChannel.Result) {
        val current = RecordingRepository.active(activity)
        if (current == null) {
            result.success(
                mapOf(
                    "success" to false,
                    "message" to "No existe una grabación activa.",
                ),
            )
            return
        }
        val intent = Intent(activity, RecordingService::class.java).apply {
            action = RecordingService.ACTION_STOP
            putExtra(RecordingService.EXTRA_ID, current.id)
        }
        activity.startService(intent)
        result.success(mapOf("success" to true, "message" to "Deteniendo grabación…"))
    }
}

class RecordingService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val stopRequested = AtomicBoolean(false)
    @Volatile private var currentConnection: HttpURLConnection? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var currentMeta: RecordingMeta? = null
    @Volatile private var finalized = false
    private var interruptedReason: String? = null
    private var lastMetaUpdate = 0L
    private var lastNotificationUpdate = 0L
    private val localSegments = mutableListOf<LocalSegment>()
    private var initFileName: String? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                val requestedId = intent.getStringExtra(EXTRA_ID).orEmpty()
                stopRequested.set(true)
                currentConnection?.disconnect()
                if (!isRunning()) {
                    val meta = currentMeta
                        ?: requestedId.takeIf { it.isNotBlank() }
                            ?.let { RecordingRepository.read(this, it) }
                    if (meta == null) {
                        stopSelf(startId)
                    } else {
                        currentMeta = meta
                        loadLocalPlaylist(meta)
                        val size = RecordingRepository.mediaSize(meta)
                        finalizeRecording(
                            meta.copy(
                                endedAt = System.currentTimeMillis(),
                                durationSeconds = elapsedSeconds(meta),
                                sizeBytes = size,
                                status = if (size >= 1024L) "completed" else "failed",
                                errorMessage = if (size >= 1024L) "" else
                                    "La señal no alcanzó a guardar datos compatibles.",
                            ),
                        )
                    }
                }
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_ID).orEmpty()
                val urls = intent.getStringArrayListExtra(EXTRA_URLS).orEmpty()
                if (id.isBlank() || urls.isEmpty()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (isRunning() && activeId != id) return START_NOT_STICKY
                if (isRunning() && activeId == id) return START_REDELIVER_INTENT
                val meta = RecordingRepository.read(this, id)
                if (meta == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                stopRequested.set(false)
                finalized = false
                interruptedReason = null
                lastMetaUpdate = 0L
                lastNotificationUpdate = 0L
                currentMeta = meta
                loadLocalPlaylist(meta)
                running = true
                activeId = id
                RecordingRepository.setActive(this, id)
                return try {
                    acquireLocks(meta.maxDurationMinutes)
                    startAsForeground(meta)
                    executor.execute { runRecording(meta, urls) }
                    START_REDELIVER_INTENT
                } catch (error: Throwable) {
                    val size = RecordingRepository.mediaSize(meta)
                    finalizeRecording(
                        meta.copy(
                            endedAt = System.currentTimeMillis(),
                            durationSeconds = elapsedSeconds(meta),
                            sizeBytes = size,
                            status = if (size >= 1024L) "interrupted" else "failed",
                            errorMessage = error.message?.takeIf { it.isNotBlank() }
                                ?: "Android no permitió iniciar la grabación en segundo plano.",
                        ),
                    )
                    START_NOT_STICKY
                }
            }
        }
        stopSelf()
        return START_NOT_STICKY
    }

    private fun runRecording(initialMeta: RecordingMeta, urls: List<String>) {
        var lastError: Throwable? = null
        try {
            for (candidate in urls) {
                if (shouldStop(initialMeta)) break
                val sizeBeforeCandidate = RecordingRepository.mediaSize(initialMeta)
                try {
                    recordCandidate(candidate, initialMeta)
                    if (shouldStop(initialMeta)) break
                    if (RecordingRepository.mediaSize(initialMeta) > sizeBeforeCandidate) break
                } catch (error: Throwable) {
                    lastError = error
                    if (RecordingRepository.mediaSize(initialMeta) > sizeBeforeCandidate) break
                }
            }
            writeLocalPlaylist(initialMeta, endList = true)
            val size = RecordingRepository.mediaSize(initialMeta)
            val reason = interruptedReason
            val status = when {
                reason != null -> if (size >= 1024L) "interrupted" else "failed"
                stopRequested.get() || reachedMaximum(initialMeta) ->
                    if (size >= 1024L) "completed" else "failed"
                size >= 1024L -> "interrupted"
                else -> "failed"
            }
            val errorMessage = when {
                reason != null -> reason
                status == "failed" ->
                    friendlyError(lastError) ?: "La señal no entregó datos compatibles."
                status == "interrupted" ->
                    friendlyError(lastError) ?: "La señal terminó antes de lo esperado."
                else -> ""
            }
            finalizeRecording(
                initialMeta.copy(
                    endedAt = System.currentTimeMillis(),
                    durationSeconds = elapsedSeconds(initialMeta),
                    sizeBytes = size,
                    status = status,
                    errorMessage = errorMessage,
                ),
            )
        } catch (error: Throwable) {
            writeLocalPlaylist(initialMeta, endList = true)
            val size = RecordingRepository.mediaSize(initialMeta)
            finalizeRecording(
                initialMeta.copy(
                    endedAt = System.currentTimeMillis(),
                    durationSeconds = elapsedSeconds(initialMeta),
                    sizeBytes = size,
                    status = if (size >= 1024L) "interrupted" else "failed",
                    errorMessage = friendlyError(error)
                        ?: "La grabación se interrumpió inesperadamente.",
                ),
            )
        }
    }

    private fun recordCandidate(url: String, meta: RecordingMeta) {
        if (url.lowercase().substringBefore('?').endsWith(".m3u8")) {
            recordHls(url, meta)
        } else {
            recordDirectOrHls(url, meta)
        }
    }

    private fun recordDirectOrHls(url: String, meta: RecordingMeta) {
        var connection: HttpURLConnection? = null
        try {
            val activeConnection = openConnection(url, readTimeout = 25_000)
            connection = activeConnection
            currentConnection = activeConnection
            val input = BufferedInputStream(activeConnection.inputStream, 64 * 1024)
            input.use { stream ->
                stream.mark(16 * 1024)
                val probe = ByteArray(8 * 1024)
                val probeCount = stream.read(probe)
                stream.reset()
                val probeText = if (probeCount > 0) {
                    String(probe, 0, probeCount, Charsets.UTF_8).trimStart()
                } else {
                    ""
                }
                val contentType = activeConnection.contentType.orEmpty().lowercase()
                if (probeText.startsWith("#EXTM3U") ||
                    contentType.contains("mpegurl") ||
                    contentType.contains("m3u")
                ) {
                    val resolved = activeConnection.url.toString()
                    activeConnection.disconnect()
                    currentConnection = null
                    recordHls(resolved, meta)
                    return
                }

                val packageDirectory = File(meta.localPath).parentFile
                    ?: throw IOException("No se pudo preparar la carpeta de grabación.")
                val index = nextDirectIndex(packageDirectory)
                val part = File(packageDirectory, "direct_${index.toString().padStart(5, '0')}.ts.part")
                val completed = File(packageDirectory, part.name.removeSuffix(".part"))
                val started = System.currentTimeMillis()
                var wroteBytes = false
                try {
                    BufferedOutputStream(FileOutputStream(part, true), 64 * 1024).use { out ->
                        val buffer = ByteArray(64 * 1024)
                        while (!shouldStop(meta)) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            if (count == 0) continue
                            out.write(buffer, 0, count)
                            wroteBytes = true
                            updateProgress(meta)
                        }
                        out.flush()
                    }
                } finally {
                    if (part.exists() && part.length() > 0L) {
                        if (!part.renameTo(completed)) {
                            part.copyTo(completed, overwrite = true)
                            part.delete()
                        }
                        val duration = max(
                            0.1,
                            (System.currentTimeMillis() - started).toDouble() / 1000.0,
                        )
                        localSegments += LocalSegment(completed.name, duration, false)
                        writeLocalPlaylist(meta, endList = false)
                    } else {
                        part.delete()
                    }
                }
                if (!wroteBytes) throw IOException("La señal no entregó datos de video.")
                if (!shouldStop(meta)) {
                    throw IOException("La señal directa terminó inesperadamente.")
                }
            }
        } finally {
            connection?.disconnect()
            currentConnection = null
        }
    }

    private fun recordHls(url: String, meta: RecordingMeta) {
        var playlistUrl = resolveMediaPlaylist(url)
        var firstPlaylist = localSegments.none { it.fileName.startsWith("hls_") }
        var nextSequence = localSegments
            .mapNotNull { segmentSequence(it.fileName) }
            .maxOrNull()
            ?.plus(1L)
        var consecutiveFailures = 0
        var emptyCycles = 0

        while (!shouldStop(meta)) {
            try {
                val fetched = fetchText(playlistUrl)
                playlistUrl = fetched.second
                val playlist = parseMediaPlaylist(fetched.first, playlistUrl)
                if (playlist.encrypted) {
                    throw IOException(
                        "La señal utiliza cifrado y no permite una grabación local compatible.",
                    )
                }
                val packageDirectory = File(meta.localPath).parentFile
                    ?: throw IOException("No se pudo preparar la carpeta de grabación.")
                if (playlist.mapUrl != null && initFileName == null) {
                    val extension = fileExtension(playlist.mapUrl, "mp4")
                    val name = "init.$extension"
                    downloadFile(playlist.mapUrl, File(packageDirectory, name), meta)
                    initFileName = name
                }
                if (firstPlaylist) {
                    val startIndex = max(0, playlist.segments.size - 2)
                    nextSequence = playlist.mediaSequence + startIndex
                    firstPlaylist = false
                }
                var wroteSegment = false
                playlist.segments.forEachIndexed { index, segment ->
                    if (shouldStop(meta)) return@forEachIndexed
                    val sequence = playlist.mediaSequence + index
                    if (sequence < (nextSequence ?: sequence)) return@forEachIndexed
                    val extension = fileExtension(
                        segment.url,
                        if (playlist.mapUrl != null) "m4s" else "ts",
                    )
                    val fileName = "hls_${sequence}.$extension"
                    val target = File(packageDirectory, fileName)
                    if (!target.exists() || target.length() <= 0L) {
                        downloadFile(segment.url, target, meta)
                    }
                    if (target.exists() && target.length() > 0L &&
                        localSegments.none { it.fileName == fileName }
                    ) {
                        localSegments += LocalSegment(
                            fileName = fileName,
                            duration = segment.duration.coerceAtLeast(0.1),
                            discontinuity = segment.discontinuity,
                        )
                    }
                    nextSequence = sequence + 1L
                    wroteSegment = true
                    writeLocalPlaylist(meta, endList = false)
                }
                consecutiveFailures = 0
                if (wroteSegment) {
                    emptyCycles = 0
                } else {
                    emptyCycles++
                }
                if (playlist.endList && !wroteSegment) return
                if (emptyCycles >= 12) {
                    throw IOException("La señal dejó de publicar segmentos nuevos.")
                }
                val delay = (playlist.targetDurationSeconds * 500L)
                    .coerceIn(1_000L, 5_000L)
                sleepInterruptibly(delay)
            } catch (error: IOException) {
                if (shouldStop(meta)) return
                consecutiveFailures++
                if (consecutiveFailures >= 8) throw error
                sleepInterruptibly(min(6_000L, 900L * consecutiveFailures))
            }
        }
    }

    private fun loadLocalPlaylist(meta: RecordingMeta) {
        localSegments.clear()
        initFileName = null
        val playlist = File(meta.localPath)
        if (!playlist.exists()) return
        var pendingDuration = 0.0
        var pendingDiscontinuity = false
        playlist.readLines().forEach { raw ->
            val line = raw.trim()
            when {
                line.startsWith("#EXT-X-MAP:", ignoreCase = true) -> {
                    initFileName = Regex("URI=\"([^\"]+)\"", RegexOption.IGNORE_CASE)
                        .find(line)
                        ?.groupValues
                        ?.getOrNull(1)
                }
                line.startsWith("#EXTINF:", ignoreCase = true) -> {
                    pendingDuration = line.substringAfter(":")
                        .substringBefore(",")
                        .trim()
                        .toDoubleOrNull()
                        ?: 0.0
                }
                line.equals("#EXT-X-DISCONTINUITY", ignoreCase = true) -> {
                    pendingDiscontinuity = true
                }
                line.isNotBlank() && !line.startsWith("#") -> {
                    localSegments += LocalSegment(
                        fileName = line,
                        duration = pendingDuration.coerceAtLeast(0.1),
                        discontinuity = pendingDiscontinuity,
                    )
                    pendingDuration = 0.0
                    pendingDiscontinuity = false
                }
            }
        }
    }

    private fun writeLocalPlaylist(meta: RecordingMeta, endList: Boolean) {
        if (localSegments.isEmpty()) return
        val target = File(meta.localPath)
        target.parentFile?.mkdirs()
        val maximumDuration = localSegments.maxOfOrNull { it.duration } ?: 1.0
        val builder = StringBuilder()
        builder.appendLine("#EXTM3U")
        builder.appendLine(if (initFileName == null) "#EXT-X-VERSION:3" else "#EXT-X-VERSION:7")
        builder.appendLine("#EXT-X-PLAYLIST-TYPE:${if (endList) "VOD" else "EVENT"}")
        builder.appendLine("#EXT-X-TARGETDURATION:${ceil(maximumDuration).toInt().coerceAtLeast(1)}")
        builder.appendLine("#EXT-X-MEDIA-SEQUENCE:0")
        initFileName?.let { builder.appendLine("#EXT-X-MAP:URI=\"$it\"") }
        localSegments.forEach { segment ->
            if (segment.discontinuity) builder.appendLine("#EXT-X-DISCONTINUITY")
            builder.appendLine("#EXTINF:${String.format(Locale.US, "%.3f", segment.duration)},")
            builder.appendLine(segment.fileName)
        }
        if (endList) builder.appendLine("#EXT-X-ENDLIST")
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(builder.toString())
        if (!temporary.renameTo(target)) {
            target.writeText(builder.toString())
            temporary.delete()
        }
    }

    private fun resolveMediaPlaylist(initialUrl: String): String {
        var current = initialUrl
        repeat(3) {
            val fetched = fetchText(current)
            val variants = parseMasterVariants(fetched.first, fetched.second)
            if (variants.isEmpty()) return fetched.second
            current = variants.maxByOrNull { it.bandwidth }?.url ?: variants.first().url
        }
        return current
    }

    private fun parseMasterVariants(text: String, baseUrl: String): List<HlsVariant> {
        val lines = text.lineSequence().map { it.trim() }.toList()
        val variants = mutableListOf<HlsVariant>()
        var pendingBandwidth: Long? = null
        for (line in lines) {
            if (line.startsWith("#EXT-X-STREAM-INF", ignoreCase = true)) {
                pendingBandwidth = Regex("BANDWIDTH=(\\d+)", RegexOption.IGNORE_CASE)
                    .find(line)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.toLongOrNull()
                    ?: 0L
            } else if (pendingBandwidth != null && line.isNotBlank() && !line.startsWith("#")) {
                variants += HlsVariant(resolveUrl(baseUrl, line), pendingBandwidth)
                pendingBandwidth = null
            }
        }
        return variants
    }

    private fun parseMediaPlaylist(text: String, baseUrl: String): HlsPlaylist {
        val lines = text.lineSequence().map { it.trim() }.toList()
        var mediaSequence = 0L
        var targetDuration = 4
        var encrypted = false
        var mapUrl: String? = null
        var pendingDuration = 0.0
        var pendingDiscontinuity = false
        val segments = mutableListOf<HlsSegment>()
        for (line in lines) {
            when {
                line.startsWith("#EXT-X-MEDIA-SEQUENCE:", ignoreCase = true) -> {
                    mediaSequence = line.substringAfter(":").trim().toLongOrNull() ?: 0L
                }
                line.startsWith("#EXT-X-TARGETDURATION:", ignoreCase = true) -> {
                    targetDuration = line.substringAfter(":").trim().toIntOrNull() ?: 4
                }
                line.startsWith("#EXTINF:", ignoreCase = true) -> {
                    pendingDuration = line.substringAfter(":")
                        .substringBefore(",")
                        .trim()
                        .toDoubleOrNull()
                        ?: targetDuration.toDouble()
                }
                line.equals("#EXT-X-DISCONTINUITY", ignoreCase = true) -> {
                    pendingDiscontinuity = true
                }
                line.startsWith("#EXT-X-KEY:", ignoreCase = true) -> {
                    val method = Regex("METHOD=([^,]+)", RegexOption.IGNORE_CASE)
                        .find(line)
                        ?.groupValues
                        ?.getOrNull(1)
                        ?.uppercase()
                    if (method != null && method != "NONE") encrypted = true
                }
                line.startsWith("#EXT-X-MAP:", ignoreCase = true) -> {
                    val uri = Regex("URI=\"([^\"]+)\"", RegexOption.IGNORE_CASE)
                        .find(line)
                        ?.groupValues
                        ?.getOrNull(1)
                    if (!uri.isNullOrBlank()) mapUrl = resolveUrl(baseUrl, uri)
                }
                line.isNotBlank() && !line.startsWith("#") -> {
                    segments += HlsSegment(
                        url = resolveUrl(baseUrl, line),
                        duration = pendingDuration.takeIf { it > 0.0 }
                            ?: targetDuration.toDouble(),
                        discontinuity = pendingDiscontinuity,
                    )
                    pendingDuration = 0.0
                    pendingDiscontinuity = false
                }
            }
        }
        return HlsPlaylist(
            mediaSequence = mediaSequence,
            targetDurationSeconds = targetDuration,
            segments = segments,
            mapUrl = mapUrl,
            encrypted = encrypted,
            endList = lines.any { it.equals("#EXT-X-ENDLIST", ignoreCase = true) },
        )
    }

    private fun downloadFile(url: String, target: File, meta: RecordingMeta) {
        val temporary = File(target.parentFile, "${target.name}.part")
        temporary.delete()
        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(url, readTimeout = 25_000)
            currentConnection = connection
            BufferedInputStream(connection.inputStream, 64 * 1024).use { input ->
                BufferedOutputStream(FileOutputStream(temporary), 64 * 1024).use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (!shouldStop(meta)) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        out.write(buffer, 0, count)
                        updateProgress(meta)
                    }
                    out.flush()
                }
            }
            if (shouldStop(meta)) {
                temporary.delete()
                return
            }
            if (temporary.length() <= 0L) {
                temporary.delete()
                throw IOException("El segmento de video llegó vacío.")
            }
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
        } finally {
            connection?.disconnect()
            currentConnection = null
        }
    }

    private fun fetchText(url: String): Pair<String, String> {
        var connection: HttpURLConnection? = null
        return try {
            connection = openConnection(url, readTimeout = 15_000)
            currentConnection = connection
            val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            text to connection.url.toString()
        } finally {
            connection?.disconnect()
            currentConnection = null
        }
    }

    private fun openConnection(url: String, readTimeout: Int): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15_000
        connection.readTimeout = readTimeout
        connection.useCaches = false
        connection.setRequestProperty(
            "User-Agent",
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.7.1",
        )
        connection.setRequestProperty("Accept", "*/*")
        connection.connect()
        val code = connection.responseCode
        if (code !in 200..299) {
            connection.disconnect()
            throw IOException("El servidor respondió con el código $code.")
        }
        return connection
    }

    private fun resolveUrl(base: String, child: String): String {
        return try {
            URI(base).resolve(child).toString()
        } catch (_: Exception) {
            if (child.startsWith("http://") || child.startsWith("https://")) child else base
        }
    }

    private fun fileExtension(url: String, fallback: String): String {
        val path = try {
            URI(url).path.orEmpty()
        } catch (_: Exception) {
            url.substringBefore('?')
        }
        val extension = path.substringAfterLast('.', "").lowercase()
        val supported = setOf("ts", "m4s", "mp4", "aac", "mp3", "webm", "vtt")
        return extension.takeIf { it in supported } ?: fallback
    }

    private fun segmentSequence(fileName: String): Long? =
        Regex("^hls_(\\d+)\\.").find(fileName)?.groupValues?.getOrNull(1)?.toLongOrNull()

    private fun nextDirectIndex(directory: File): Int =
        directory.listFiles()
            ?.mapNotNull { file ->
                Regex("^direct_(\\d+)\\.ts(?:\\.part)?$")
                    .find(file.name)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.toIntOrNull()
            }
            ?.maxOrNull()
            ?.plus(1)
            ?: 0

    private fun shouldStop(meta: RecordingMeta): Boolean {
        if (stopRequested.get()) return true
        if (reachedMaximum(meta)) return true
        val available = StatFs(filesDir.absolutePath).availableBytes
        if (available <= STORAGE_RESERVE_BYTES) {
            interruptedReason =
                "La grabación se detuvo para reservar 1 GB y proteger el almacenamiento del dispositivo."
            stopRequested.set(true)
            currentConnection?.disconnect()
            return true
        }
        return false
    }

    private fun reachedMaximum(meta: RecordingMeta): Boolean {
        val limit = meta.maxDurationMinutes.coerceIn(30, 240) * 60L
        return elapsedSeconds(meta) >= limit
    }

    private fun elapsedSeconds(meta: RecordingMeta): Long =
        max(0L, (System.currentTimeMillis() - meta.startedAt) / 1000L)

    private fun updateProgress(meta: RecordingMeta) {
        val now = System.currentTimeMillis()
        if (now - lastMetaUpdate >= 2_000L) {
            lastMetaUpdate = now
            val updated = meta.copy(
                durationSeconds = elapsedSeconds(meta),
                sizeBytes = RecordingRepository.mediaSize(meta),
                status = "recording",
            )
            currentMeta = updated
            RecordingRepository.write(this, updated)
        }
        if (now - lastNotificationUpdate >= 5_000L) {
            lastNotificationUpdate = now
            currentMeta?.let { updateNotification(it) }
        }
    }

    @Synchronized
    private fun finalizeRecording(meta: RecordingMeta) {
        if (finalized) return
        finalized = true
        writeLocalPlaylist(meta, endList = true)
        val finalMeta = meta.copy(sizeBytes = RecordingRepository.mediaSize(meta))
        currentMeta = finalMeta
        RecordingRepository.write(this, finalMeta)
        RecordingRepository.clearActive(this, finalMeta.id)
        running = false
        activeId = null
        releaseLocks()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startAsForeground(meta: RecordingMeta) {
        val notification = buildNotification(meta)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(meta: RecordingMeta) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(meta))
    }

    private fun buildNotification(meta: RecordingMeta): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            8101,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, RecordingService::class.java).apply {
            action = ACTION_STOP
            putExtra(EXTRA_ID, meta.id)
        }
        val stopPending = PendingIntent.getService(
            this,
            8102,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val stopIcon = Icon.createWithResource(
            this,
            android.R.drawable.ic_menu_close_clear_cancel,
        )
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("AVO TV está grabando")
            .setContentText(
                "${meta.title} · ${formatDuration(elapsedSeconds(meta))} · ${formatBytes(RecordingRepository.mediaSize(meta))}",
            )
            .setSubText(meta.channelTitle)
            .setContentIntent(openPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setWhen(meta.startedAt)
            .setUsesChronometer(true)
            .addAction(
                Notification.Action.Builder(
                    stopIcon,
                    "Detener",
                    stopPending,
                ).build(),
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            "Grabaciones de AVO TV",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Muestra el estado y los controles de las grabaciones en vivo."
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireLocks(maxMinutes: Int) {
        val timeout = (maxMinutes.coerceIn(30, 240) + 10L) * 60L * 1000L
        try {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "AVOTV:LiveRecording",
            ).apply { acquire(timeout) }
        } catch (_: Exception) {
            wakeLock = null
        }
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "AVOTV:LiveRecordingWifi",
            ).apply { acquire() }
        } catch (_: Exception) {
            wifiLock = null
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }

    private fun sleepInterruptibly(milliseconds: Long) {
        var remaining = milliseconds
        while (remaining > 0L && !stopRequested.get()) {
            val step = min(250L, remaining)
            Thread.sleep(step)
            remaining -= step
        }
    }

    private fun friendlyError(error: Throwable?): String? {
        val message = error?.message?.trim().orEmpty()
        if (message.isBlank()) return null
        return when {
            message.contains("cifrado", ignoreCase = true) -> message
            message.contains("código", ignoreCase = true) -> message
            message.contains("segmentos nuevos", ignoreCase = true) -> message
            else -> "La señal del canal dejó de responder."
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        val meta = currentMeta
        interruptedReason =
            "Android alcanzó el límite permitido para tareas de grabación en segundo plano."
        stopRequested.set(true)
        currentConnection?.disconnect()
        if (meta == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
            return
        }
        finalizeRecording(
            meta.copy(
                endedAt = System.currentTimeMillis(),
                durationSeconds = elapsedSeconds(meta),
                sizeBytes = RecordingRepository.mediaSize(meta),
                status = if (RecordingRepository.mediaSize(meta) >= 1024L) {
                    "interrupted"
                } else {
                    "failed"
                },
                errorMessage = interruptedReason.orEmpty(),
            ),
        )
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        currentConnection?.disconnect()
        if (!finalized) {
            val meta = currentMeta
            if (meta != null) {
                writeLocalPlaylist(meta, endList = true)
                val size = RecordingRepository.mediaSize(meta)
                val interrupted = meta.copy(
                    endedAt = System.currentTimeMillis(),
                    durationSeconds = elapsedSeconds(meta),
                    sizeBytes = size,
                    status = if (size >= 1024L) "interrupted" else "failed",
                    errorMessage = "Android detuvo la grabación antes de finalizar.",
                )
                RecordingRepository.write(this, interrupted)
                RecordingRepository.clearActive(this, meta.id)
            }
            running = false
            activeId = null
        }
        releaseLocks()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "mx.avotv.action.START_RECORDING"
        const val ACTION_STOP = "mx.avotv.action.STOP_RECORDING"
        const val EXTRA_ID = "recording_id"
        const val EXTRA_URLS = "recording_urls"
        private const val NOTIFICATION_CHANNEL = "avo_tv_recordings"
        private const val NOTIFICATION_ID = 6808

        @Volatile private var running = false
        @Volatile private var activeId: String? = null

        fun isRunning(): Boolean = running
        fun isActive(id: String): Boolean = running && activeId == id
    }
}

private data class LocalSegment(
    val fileName: String,
    val duration: Double,
    val discontinuity: Boolean,
)

private data class HlsVariant(val url: String, val bandwidth: Long)

private data class HlsSegment(
    val url: String,
    val duration: Double,
    val discontinuity: Boolean,
)

private data class HlsPlaylist(
    val mediaSequence: Long,
    val targetDurationSeconds: Int,
    val segments: List<HlsSegment>,
    val mapUrl: String?,
    val encrypted: Boolean,
    val endList: Boolean,
)

private fun formatDuration(seconds: Long): String {
    val hours = seconds / 3600L
    val minutes = (seconds % 3600L) / 60L
    val secs = seconds % 60L
    return String.format("%02d:%02d:%02d", hours, minutes, secs)
}

private fun formatBytes(bytes: Long): String {
    return when {
        bytes >= 1024L * 1024L * 1024L ->
            String.format("%.1f GB", bytes.toDouble() / (1024.0 * 1024.0 * 1024.0))
        bytes >= 1024L * 1024L ->
            String.format("%.0f MB", bytes.toDouble() / (1024.0 * 1024.0))
        else -> String.format("%.0f KB", bytes.toDouble() / 1024.0)
    }
}
''',
        encoding="utf-8",
    )

if not MANIFEST.exists():
    raise SystemExit("No existe AndroidManifest.xml; ejecuta flutter create primero")

patch_manifest()
patch_gradle()
copy_branding()
write_main_activity()
write_recording_service()

manifest_text = MANIFEST.read_text(encoding="utf-8")
if "extractNativeLibs" in manifest_text:
    raise SystemExit("extractNativeLibs todavía aparece en AndroidManifest.xml")
if "AVO TV" not in manifest_text:
    raise SystemExit("No se aplicó el nombre AVO TV")
if 'android:name=".PlayerActivity"' not in manifest_text:
    raise SystemExit("No se declaró PlayerActivity")
if 'android:supportsPictureInPicture="true"' not in manifest_text:
    raise SystemExit("No se activó Picture-in-Picture en PlayerActivity")
if 'android.intent.category.LEANBACK_LAUNCHER' not in manifest_text:
    raise SystemExit("No se declaró el lanzador de Android TV")
if 'android.software.leanback' not in manifest_text:
    raise SystemExit("No se declaró compatibilidad con Android TV")
if 'android:name=".RecordingService"' not in manifest_text:
    raise SystemExit("No se declaró RecordingService")
if 'android.permission.FOREGROUND_SERVICE_DATA_SYNC' not in manifest_text:
    raise SystemExit("No se declaró el permiso de grabación en segundo plano")

recording_source = ANDROID / "app/src/main/kotlin/mx/avotv/avo_tv/RecordingService.kt"
if not recording_source.exists():
    raise SystemExit("No se generó RecordingService.kt")

print("Android preparado para AVO TV v0.7.1: rediseño premium, reproductor minimalista y TV en vivo optimizada.")
