package com.redvpn.red_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.NetworkInterface

/**
 * سرویس VPN که هسته‌ی sing-box (libbox) را اجرا می‌کند.
 *
 * ⚠️ این فایل بدون کامپایل نوشته شده. اسم و امضای متدهای PlatformInterface
 * به نسخه‌ی libbox بستگی دارد؛ اگر کامپایل خطا داد، امضاها را با نسخه‌ی
 * libbox.aar خودتان تطبیق دهید (راهنما: ANDROID_SETUP.md).
 */
class RedVpnService : VpnService(), PlatformInterface {

    private var box: BoxService? = null
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config != null) startBox(config) else stopSelf()
            }
            ACTION_STOP -> stopBox()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopBox()
        super.onDestroy()
    }

    // ------------------------------------------------------------- lifecycle

    private fun startBox(config: String) {
        stopBox()
        lastError = null
        try {
            showForeground()
            setupOnce()
            val service = Libbox.newService(config, this)
            service.start()
            box = service
            running = true
        } catch (t: Throwable) {
            // خطا را ذخیره می‌کنیم تا برنامه به‌جای کرش، آن را نشان دهد
            lastError = "${t.javaClass.name}: ${t.message}\n" +
                t.stackTrace.take(8).joinToString("\n") { "  at $it" }
            running = false
            stopBox()
        }
    }

    private fun stopBox() {
        try {
            box?.close()
        } catch (_: Throwable) {
        }
        box = null
        try {
            tun?.close()
        } catch (_: Throwable) {
        }
        tun = null
        running = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    private fun setupOnce() {
        if (didSetup) return
        val options = SetupOptions().apply {
            basePath = filesDir.path
            workingPath = filesDir.path
            tempPath = cacheDir.path
        }
        Libbox.setup(options)
        didSetup = true
    }

    private fun showForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "TheVil", NotificationManager.IMPORTANCE_LOW)
        )
        val n = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("TheVil")
            .setContentText("متصل است")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
    }

    // ------------------------------------------------------- PlatformInterface

    /** ساخت رابط TUN و برگرداندن file descriptor آن به هسته. */
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("TheVil")
            .setMtu(1500)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1") // کوئری‌های DNS با hijack-dns توسط هسته گرفته می‌شود
        try {
            // خود اپ از VPN مستثنا شود تا حلقه‌ی ترافیک ایجاد نشود
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {
        }
        val pfd = builder.establish() ?: error("VPN establish failed")
        tun = pfd
        return pfd.detachFd()
    }

    /** سوکت‌های خروجی هسته از VPN رد نشوند. */
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    // --- پایش اینترفیس پیش‌فرض (⚠️ امضای updateDefaultInterface وابسته به نسخه است)
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return
        val name = cm.getLinkProperties(network)?.interfaceName ?: return
        val index = NetworkInterface.getByName(name)?.index ?: return
        listener.updateDefaultInterface(name, index, false, false)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {}

    // --- بقیه‌ی متدها: پیاده‌سازی حداقلی
    override fun getInterfaces(): NetworkInterfaceIterator = object : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = false
        override fun next(): io.nekohasekai.libbox.NetworkInterface =
            throw NoSuchElementException()
    }

    override fun systemCertificates(): StringIterator = object : StringIterator {
        override fun hasNext(): Boolean = false
        override fun len(): Int = 0
        override fun next(): String = throw NoSuchElementException()
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int = throw UnsupportedOperationException("per-app rules not supported yet")

    override fun packageNameByUid(uid: Int): String =
        packageManager.getPackagesForUid(uid)?.firstOrNull()
            ?: throw NoSuchElementException("no package for uid $uid")

    @Suppress("DEPRECATION")
    override fun uidByPackageName(packageName: String): Int =
        packageManager.getApplicationInfo(packageName, 0).uid

    override fun writeLog(message: String) {
        android.util.Log.d("TheVil", message)
    }

    override fun localDNSTransport(): io.nekohasekai.libbox.LocalDNSTransport? = null
    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}

    companion object {
        const val ACTION_START = "com.redvpn.START"
        const val ACTION_STOP = "com.redvpn.STOP"
        const val EXTRA_CONFIG = "config"
        private const val CHANNEL_ID = "red_vpn"

        @Volatile
        var running = false

        @Volatile
        var lastError: String? = null
        private var didSetup = false
    }
}
