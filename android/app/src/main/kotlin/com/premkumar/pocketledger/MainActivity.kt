package com.premkumar.pocketledger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var statementResult: MethodChannel.Result? = null
    private val reader = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocket_ledger/statement_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickStatement") {
                    result.notImplemented()
                } else if (statementResult != null) {
                    result.error("picker_busy", "A statement is already being selected.", null)
                } else {
                    statementResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "*/*"
                            // CATEGORY_OPENABLE excludes native Google Sheets (virtual documents).
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            // Providers use inconsistent MIME types for CSV/Excel.
                            // Validate the selected name/export rather than hiding files.
                        }
                        startActivityForResult(intent, PICK_STATEMENT)
                    } catch (_: Exception) {
                        statementResult = null
                        result.error("picker_unavailable", "Could not open the document picker.", null)
                    }
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_STATEMENT) return
        val result = statementResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            statementResult = null
            result.success(null)
            return
        }
        // Provider downloads and exports must not block Flutter's UI thread.
        reader.execute {
            try {
                val document = readStatement(uri)
                runOnUiThread {
                    statementResult = null
                    result.success(document)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    statementResult = null
                    result.error("statement_read_failed", error.message ?: "Could not read this document.", null)
                }
            }
        }
    }

    private fun readStatement(uri: Uri): Map<String, Any> {
        val resolver = contentResolver
        var name = "statement"
        var virtual = false
        resolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameColumn >= 0) name = cursor.getString(nameColumn) ?: name
                val flagsColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_FLAGS)
                if (flagsColumn >= 0) {
                    virtual = cursor.getLong(flagsColumn) and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT.toLong() != 0L
                }
            }
        }
        val nativeSheet = resolver.getType(uri) == SHEETS
        val stream = if (virtual || nativeSheet) {
            val formats = resolver.getStreamTypes(uri, "*/*")?.toSet() ?: emptySet()
            val format = listOf(XLSX, "text/csv", "text/comma-separated-values", XLS).firstOrNull { it in formats }
                ?: throw IllegalArgumentException("This provider cannot export the selected sheet as Excel or CSV.")
            val suffix = when (format) { XLSX -> ".xlsx"; XLS -> ".xls"; else -> ".csv" }
            name = name.replace(Regex("\\.(gsheet|xlsx|xls|csv)$", RegexOption.IGNORE_CASE), "") + suffix
            val descriptor = resolver.openTypedAssetFileDescriptor(uri, format, null)
                ?: throw IllegalArgumentException("Could not download the selected sheet.")
            try { descriptor.createInputStream() } catch (error: Exception) { descriptor.close(); throw error }
        } else {
            resolver.openInputStream(uri) ?: throw IllegalArgumentException("Could not open the selected file.")
        }
        val bytes = stream.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > MAX_BYTES) throw IllegalArgumentException("Choose a statement smaller than 20 MB.")
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        require(bytes.isNotEmpty()) { "The selected document is empty." }
        return mapOf("name" to name, "bytes" to bytes)
    }

    companion object {
        private const val PICK_STATEMENT = 7412
        private const val MAX_BYTES = 20 * 1024 * 1024
        private const val SHEETS = "application/vnd.google-apps.spreadsheet"
        private const val XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        private const val XLS = "application/vnd.ms-excel"
    }
}
