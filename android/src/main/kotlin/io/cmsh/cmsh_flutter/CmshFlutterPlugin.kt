package io.cmsh.cmsh_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.atomic.AtomicBoolean

/** Reads the Play Install Referrer, which carries the click through an install. */
class CmshFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "cmsh_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getInstallReferrer") {
            readInstallReferrer(result)
        } else {
            result.notImplemented()
        }
    }

    private fun readInstallReferrer(result: Result) {
        val client = InstallReferrerClient.newBuilder(context).build()
        val mainThread = Handler(Looper.getMainLooper())
        // The service can report both a response and a disconnect.
        val answered = AtomicBoolean(false)

        fun answer(value: String?) {
            if (answered.compareAndSet(false, true)) {
                mainThread.post { result.success(value) }
                client.endConnection()
            }
        }

        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                        answer(null)
                        return
                    }
                    try {
                        answer(client.installReferrer.installReferrer)
                    } catch (_: Exception) {
                        answer(null)
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    answer(null)
                }
            })
        } catch (_: Exception) {
            answer(null)
        }
    }
}
