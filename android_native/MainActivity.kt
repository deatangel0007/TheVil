package com.redvpn.red_vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var pendingConfig: String? = null
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
                        // اندروید قبل از اولین اتصال، مجوز VPN را از کاربر می‌گیرد
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingConfig = config
                            pendingResult = result
                            startActivityForResult(intent, REQ_VPN)
                        } else {
                            startVpn(config)
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
        val config = pendingConfig
        pendingResult = null
        pendingConfig = null
        if (resultCode == Activity.RESULT_OK && config != null) {
            startVpn(config)
            result?.success(null)
        } else {
            result?.error("DENIED", "VPN permission denied", null)
        }
    }

    private fun startVpn(config: String) {
        val i = Intent(this, RedVpnService::class.java)
            .setAction(RedVpnService.ACTION_START)
            .putExtra(RedVpnService.EXTRA_CONFIG, config)
        startForegroundService(i)
    }

    companion object {
        private const val REQ_VPN = 4001
    }
}
