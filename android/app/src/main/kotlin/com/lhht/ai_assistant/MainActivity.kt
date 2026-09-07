package com.lhht.ai_assistant

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.lhht.ai_assistant/ota"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    val success = installApk(filePath)
                    result.success(success)
                } else {
                    result.error("INVALID_PATH", "File path is null", null)
                }
            } else if (call.method == "openNavigation") {
                val destination = call.argument<String>("destination") ?: ""
                val success = openNavigation(destination)
                result.success(success)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val intent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this@MainActivity,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                } else {
                    Uri.fromFile(file)
                }
                setDataAndType(uri, "application/vnd.android.package-archive")
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun openNavigation(destination: String): Boolean {
        // 1. Thử mở Google Maps app trực tiếp
        try {
            if (destination.isNotBlank()) {
                val uriStr = "google.navigation:q=" + Uri.encode(destination)
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uriStr)).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    setPackage("com.google.android.apps.maps")
                }
                startActivity(intent)
                return true
            } else {
                val launchIntent = packageManager.getLaunchIntentForPackage("com.google.android.apps.maps")
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launchIntent)
                    return true
                }
            }
        } catch (e: Exception) {
            // tiếp tục fallback
        }

        // 2. Thử mở bằng geo intent chung (hỗ trợ bất kỳ app bản đồ nào cài trên xe)
        try {
            val geoUriStr = if (destination.isNotBlank()) {
                "geo:0,0?q=" + Uri.encode(destination)
            } else {
                "geo:52.3759,9.7320?z=15"
            }
            val geoIntent = Intent(Intent.ACTION_VIEW, Uri.parse(geoUriStr)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(geoIntent)
            return true
        } catch (e2: Exception) {
            // tiếp tục fallback
        }
                // 3. Fallback mở Google Maps trên trình duyệt web
                try {
                    val fallbackUri = if (destination.isNotBlank()) {
                        "https://www.google.com/maps/dir/?api=1&destination=" + Uri.encode(destination)
                    } else {
                        "https://www.google.com/maps"
                    }
                    val fallbackIntent = Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUri)).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(fallbackIntent)
                    return true
                } catch (e3: Exception) {
                    e3.printStackTrace()
                    return false
                }
            }
        }
    }
}

