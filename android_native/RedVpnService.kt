package com.redvpn.red_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
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
                // اندروید می‌خواهد startForeground فوراً و قبل از هر کار دیگری صدا زده شود،
                // وگرنه برنامه را با ForegroundServiceDidNotStartInTimeException می‌کُشد.
                lastError = null
                synchronized(logBuffer) { logBuffer.clear() }
                val promoted = showForeground()
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (promoted && config != null) {
                    startBox(config)
                } else {
                    if (!promoted && lastError == null) lastError = "startForeground failed"
                    stopBox()
                }
            }
            else -> stopBox()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseBox()
        super.onDestroy()
    }

    // ------------------------------------------------------------- lifecycle

    private fun startBox(config: String) {
        releaseBox()
        synchronized(logBuffer) { logBuffer.clear() }
        appLog("[app] starting sing-box, config ${config.length} bytes")
        try {
            setupOnce()
            val service = Libbox.newService(config, this)
            appLog("[app] service created, starting...")
            service.start()
            box = service
            running = true
            appLog("[app] service started OK")
        } catch (t: Throwable) {
            // خطا را ذخیره می‌کنیم تا برنامه به‌جای کرش، آن را نشان دهد
            lastError = "${t.javaClass.name}: ${t.message}\n" +
                t.stackTrace.take(8).joinToString("\n") { "  at $it" }
            running = false
            appLog("[app] FAILED: $lastError")
            stopBox()
        }
    }

    /** هسته و TUN را می‌بندد، بدون اینکه خود سرویس را متوقف کند. */
    private fun releaseBox() {
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
    }

    private fun stopBox() {
        releaseBox()
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

    /** سرویس را به حالت پیش‌زمینه می‌برد؛ در صورت شکست، خطا را ذخیره و false برمی‌گرداند. */
    private fun showForeground(): Boolean {
        return try {
            promoteToForeground()
            true
        } catch (t: Throwable) {
            lastError = "startForeground: ${t.javaClass.name}: ${t.message}"
            false
        }
    }

    private fun promoteToForeground() {
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
        // نکته: خود اپ را از VPN مستثنا نمی‌کنیم تا «تست اینترنت» از مسیر VPN برود.
        // سوکت‌های خود هسته با protect() از VPN بیرون می‌مانند، پس حلقه ایجاد نمی‌شود.
        val pfd = builder.establish() ?: error("VPN establish failed")
        tun = pfd
        val fd = pfd.detachFd()
        appLog("[TheVil] TUN ساخته شد (fd=$fd)")
        return fd
    }

    /** سوکت‌های خروجی هسته از VPN رد نشوند. */
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    // ------------------------------------------------ اینترفیس پیش‌فرض شبکه
    // هسته باید بداند اینترنت واقعی (وای‌فای/دیتا) از کدام اینترفیس می‌رود، تا سوکت‌های
    // خودش را به آن وصل کند و وارد تونل نشود.

    private var netCallback: ConnectivityManager.NetworkCallback? = null

    private fun connectivity() =
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    /** بهترین شبکه‌ی واقعی (غیر VPN، دارای اینترنت)؛ شبکه‌ی تأییدشده اولویت دارد. */
    @Suppress("DEPRECATION")
    private fun pickNetwork(cm: ConnectivityManager): Network? =
        cm.allNetworks
            .filter { n ->
                val c = cm.getNetworkCapabilities(n) ?: return@filter false
                c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    c.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            }
            .sortedByDescending { n ->
                if (cm.getNetworkCapabilities(n)
                        ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
                ) 1 else 0
            }
            .firstOrNull()

    private fun reportDefault(listener: InterfaceUpdateListener) {
        try {
            val cm = connectivity()
            val n = pickNetwork(cm)
            if (n == null) {
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            val name = cm.getLinkProperties(n)?.interfaceName ?: return
            val index = NetworkInterface.getByName(name)?.index ?: return
            appLog("[TheVil] اینترفیس پیش‌فرض: $name (index=$index)")
            listener.updateDefaultInterface(name, index, false, false)
        } catch (t: Throwable) {
            appLog("[TheVil] reportDefault خطا: $t")
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cm = connectivity()
        reportDefault(listener)
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = reportDefault(listener)
            override fun onLost(network: Network) = reportDefault(listener)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                reportDefault(listener)
        }
        try {
            cm.registerNetworkCallback(request, cb)
            netCallback = cb
        } catch (t: Throwable) {
            appLog("[TheVil] registerNetworkCallback خطا: $t")
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val cb = netCallback ?: return
        try {
            connectivity().unregisterNetworkCallback(cb)
        } catch (_: Throwable) {
        }
        netCallback = null
    }

    /** فهرست اینترفیس‌های شبکه برای هسته (بدون این، هسته «no such network interface» می‌دهد). */
    @Suppress("DEPRECATION")
    override fun getInterfaces(): NetworkInterfaceIterator {
        val cm = connectivity()
        val javaInterfaces = try {
            NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
        val result = mutableListOf<io.nekohasekai.libbox.NetworkInterface>()
        for (network in cm.allNetworks) {
            val lp = cm.getLinkProperties(network) ?: continue
            val caps = cm.getNetworkCapabilities(network) ?: continue
            val name = lp.interfaceName ?: continue
            val ni = javaInterfaces.find { it.name == name } ?: continue

            val box = io.nekohasekai.libbox.NetworkInterface()
            box.name = name
            box.index = ni.index
            runCatching { box.mtu = ni.mtu }
            box.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            box.addresses = stringIterator(
                ni.interfaceAddresses.mapNotNull { a ->
                    val host = a.address.hostAddress?.substringBefore('%') ?: return@mapNotNull null
                    "$host/${a.networkPrefixLength}"
                }
            )
            box.dnsServer = stringIterator(lp.dnsServers.mapNotNull { it.hostAddress })

            var flags = 0
            if (runCatching { ni.isUp }.getOrDefault(true)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (runCatching { ni.isLoopback }.getOrDefault(false)) flags = flags or OsConstants.IFF_LOOPBACK
            if (runCatching { ni.isPointToPoint }.getOrDefault(false)) flags = flags or OsConstants.IFF_POINTOPOINT
            if (runCatching { ni.supportsMulticast() }.getOrDefault(false)) flags = flags or OsConstants.IFF_MULTICAST
            box.flags = flags
            box.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            result.add(box)
        }
        appLog("[TheVil] getInterfaces: ${result.size} اینترفیس")
        val it = result.iterator()
        return object : NetworkInterfaceIterator {
            override fun hasNext(): Boolean = it.hasNext()
            override fun next(): io.nekohasekai.libbox.NetworkInterface = it.next()
        }
    }

    private fun stringIterator(items: List<String>): StringIterator {
        val it = items.iterator()
        return object : StringIterator {
            override fun hasNext(): Boolean = it.hasNext()
            override fun len(): Int = items.size
            override fun next(): String = it.next()
        }
    }

    // --- بقیه‌ی متدها: پیاده‌سازی حداقلی

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
        appLog(message)
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

        private val logBuffer = ArrayList<String>()

        fun appLog(message: String) {
            android.util.Log.d("TheVil", message)
            synchronized(logBuffer) {
                logBuffer.add(message)
                if (logBuffer.size > 400) logBuffer.removeAt(0)
            }
        }

        fun logsText(): String = synchronized(logBuffer) { logBuffer.joinToString("\n") }

        @Volatile
        var running = false

        @Volatile
        var lastError: String? = null
        private var didSetup = false
    }
}
