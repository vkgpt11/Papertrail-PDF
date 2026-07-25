package com.papertrail.pdfreader

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.papertrail.pdfreader/open_pdf"
    private var channel: MethodChannel? = null
    private var pendingPdf: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialPdf") {
                if (pendingPdf == null) pendingPdf = cachePdf(intent)
                result.success(pendingPdf)
                pendingPdf = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val pdf = cachePdf(intent) ?: return
        channel?.invokeMethod("openPdf", pdf)
    }

    private fun cachePdf(intent: Intent?): Map<String, String>? {
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return null
        val uri: Uri = if (intent.action == Intent.ACTION_SEND) {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        } else {
            intent.data
        } ?: return null
        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "document.pdf"
        val target = File(cacheDir, "incoming-${System.currentTimeMillis()}.pdf")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        return mapOf("path" to target.absolutePath, "name" to name)
    }
}
