package pro.dotslash.saole

import android.content.Intent
import android.net.wifi.WifiNetworkSuggestion
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var launchMode: String = "normal"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchMode = intent.getStringExtra("mode") ?: "normal"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchMode = intent?.getStringExtra("mode") ?: "normal"
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "saole/launch").setMethodCallHandler { call, result ->
            when (call.method) {
                "getMode" -> result.success(launchMode)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "saole/wifi").setMethodCallHandler { call, result ->
            if (call.method == "connect") {
                result.success(
                    connectWifi(
                        call.argument<String>("ssid") ?: "",
                        call.argument<String>("password") ?: "",
                        call.argument<String>("security") ?: "nopass",
                        call.argument<Boolean>("hidden") ?: false,
                    )
                )
            } else {
                result.notImplemented()
            }
        }
    }

    // minSdk 31：ACTION_WIFI_ADD_NETWORKS 恒可用，拉起系统"添加网络"面板预填凭据
    // （无需定位权限）。WEP 已弃用、WifiNetworkSuggestion 不支持 → 回退 WiFi 设置页。
    private fun connectWifi(
        ssid: String, password: String, security: String, hidden: Boolean,
    ): Boolean {
        return try {
            if (security.uppercase() == "WEP") {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                return true
            }
            val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
            if (hidden) builder.setIsHiddenSsid(true)
            if (security.uppercase() == "WPA") builder.setWpa2Passphrase(password)
            val suggestions = arrayListOf(builder.build())
            val addIntent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).apply {
                putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, suggestions)
            }
            startActivity(addIntent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
