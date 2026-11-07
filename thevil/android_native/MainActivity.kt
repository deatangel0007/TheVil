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
