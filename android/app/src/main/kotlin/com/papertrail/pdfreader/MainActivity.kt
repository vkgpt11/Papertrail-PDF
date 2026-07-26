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
                if (pendingPdf == null) {
                    pendingPdf = cachePdf(intent)
                    if (pendingPdf != null) setIntent(Intent())
                }
                result.success(pendingPdf)
                pendingPdf = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val pdf = cachePdf(intent) ?: return
        setIntent(Intent())
        pendingPdf = pdf
        channel?.invokeMethod("openPdf", pdf, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingPdf == pdf) pendingPdf = null
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                // Keep the cached PDF pending so Flutter can recover it later.
            }

            override fun notImplemented() {
                // Keep the cached PDF pending so Flutter can recover it later.
            }
        })
    }

    private fun cachePdf(intent: Intent?): Map<String, String>? {
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return null
        var target: File? = null
        return try {
            val uri: Uri = if (intent.action == Intent.ACTION_SEND) {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: intent.clipData?.getItemAt(0)?.uri
            } else {
                intent.data
            } ?: return null
            val name = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: uri.lastPathSegment ?: "document.pdf"
            val cachedFile = File(cacheDir, "incoming-${System.currentTimeMillis()}.pdf")
            target = cachedFile
            contentResolver.openInputStream(uri)?.use { input ->
                cachedFile.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            mapOf("path" to cachedFile.absolutePath, "name" to name)
        } catch (_: Exception) {
            target?.delete()
            null
        }
    }
}
