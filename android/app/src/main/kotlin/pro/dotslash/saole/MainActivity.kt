package pro.dotslash.saole

import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.wifi.WifiNetworkSuggestion
import android.os.Handler
import android.os.Looper
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

        MethodChannel(messenger, "saole/beep").setMethodCallHandler { call, result ->
            if (call.method == "beep") {
                result.success(playBeep())
            } else {
                result.notImplemented()
            }
        }
    }

    // 扫码提示音：媒体流上一声短哔；用完延时 release，失败不打扰扫码。
    private fun playBeep(): Boolean {
        return try {
            val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 300)
            true
        } catch (e: Exception) {
            false
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
            val sec = security.uppercase()
            val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
            if (hidden) builder.setIsHiddenSsid(true)
            when {
                sec.startsWith("WPA3") || sec == "SAE" -> builder.setWpa3Passphrase(password)
                sec.startsWith("WPA") -> builder.setWpa2Passphrase(password)
                // nopass / 开放网络：不设密码
            }
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
