package com.redvpn.red_vpn

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.TrafficStats
import android.net.VpnService
import android.os.Process
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var pendingIntent: Intent? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // اگر برنامه کرش کرد، متن خطا را ذخیره می‌کنیم تا دفعه‌ی بعد نشان داده شود
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                java.io.File(filesDir, "crash.txt").writeText(
                    "${throwable.javaClass.name}: ${throwable.message}\n" +
                        throwable.stackTrace.take(12).joinToString("\n") { "  at $it" }
                )
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, throwable)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red_vpn/core")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config == null) {
                            result.error("NO_CONFIG", "config is null", null)
                            return@setMethodCallHandler
                        }
                        val appMode = call.argument<String>("appMode") ?: "off"
                        val appPackages =
                            call.argument<List<String>>("appPackages") ?: emptyList()
                        val serviceIntent = Intent(this, RedVpnService::class.java)
                            .setAction(RedVpnService.ACTION_START)
                            .putExtra(RedVpnService.EXTRA_CONFIG, config)
                            .putExtra(RedVpnService.EXTRA_APP_MODE, appMode)
                            .putStringArrayListExtra(
                                RedVpnService.EXTRA_APP_PACKAGES,
                                ArrayList(appPackages)
                            )
                        // اندروید قبل از اولین اتصال، مجوز VPN را از کاربر می‌گیرد
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingIntent = serviceIntent
                            pendingResult = result
                            startActivityForResult(intent, REQ_VPN)
                        } else {
                            startForegroundService(serviceIntent)
                            result.success(null)
                        }
                    }
                    "status" -> {
                        result.success(
                            mapOf(
                                "running" to RedVpnService.running,
                                "error" to RedVpnService.lastError,
                            )
                        )
                    }
                    "traffic" -> {
                        val uid = Process.myUid()
                        result.success(
                            mapOf(
                                "rx" to TrafficStats.getUidRxBytes(uid),
                                "tx" to TrafficStats.getUidTxBytes(uid),
                                "running" to RedVpnService.running,
                            )
                        )
                    }
                    "listApps" -> listApps(result)
                    "scanQr" -> scanQr(result)
                    "logs" -> result.success(RedVpnService.logsText())
                    "takeCrash" -> {
                        val f = java.io.File(filesDir, "crash.txt")
                        val text = if (f.exists()) f.readText() else null
                        f.delete()
                        result.success(text)
                    }
                    "stop" -> {
                        startService(
                            Intent(this, RedVpnService::class.java)
                                .setAction(RedVpnService.ACTION_STOP)
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_VPN) return
        val result = pendingResult
        val serviceIntent = pendingIntent
        pendingResult = null
        pendingIntent = null
        if (resultCode == Activity.RESULT_OK && serviceIntent != null) {
            startForegroundService(serviceIntent)
            result?.success(null)
        } else {
            result?.error("DENIED", "VPN permission denied", null)
        }
    }

    /** فهرست برنامه‌های نصب‌شده (در ترد پس‌زمینه، چون ممکن است کند باشد). */
    @Suppress("DEPRECATION")
    private fun listApps(result: MethodChannel.Result) {
        Thread {
            try {
                val pm = packageManager
                val list = pm.getInstalledApplications(0)
                    .filter { it.packageName != packageName }
                    .map { ai ->
                        val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                            pm.getLaunchIntentForPackage(ai.packageName) == null
                        mapOf(
                            "package" to ai.packageName,
                            "label" to (runCatching { ai.loadLabel(pm).toString() }
                                .getOrDefault(ai.packageName)),
                            "system" to isSystem,
                        )
                    }
                runOnUiThread { result.success(list) }
            } catch (t: Throwable) {
                runOnUiThread { result.error("LIST_APPS", t.toString(), null) }
            }
        }.start()
    }

    /** اسکن QR با Google Code Scanner (بدون نیاز به مجوز دوربین؛ نیاز به Google Play Services). */
    private fun scanQr(result: MethodChannel.Result) {
        try {
            val options = GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            GmsBarcodeScanning.getClient(this, options)
                .startScan()
                .addOnSuccessListener { barcode -> result.success(barcode.rawValue) }
                .addOnCanceledListener { result.success(null) }
                .addOnFailureListener { e ->
                    result.error(
                        "SCAN",
                        "اسکن QR ناموفق بود (به Google Play Services نیاز دارد): ${e.message}",
                        null
                    )
                }
        } catch (t: Throwable) {
            result.error("SCAN", "اسکنر QR در دسترس نیست: $t", null)
        }
    }

    companion object {
        private const val REQ_VPN = 4001
    }
}
