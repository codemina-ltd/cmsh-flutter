package io.cmsh.cmsh_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.Mockito

internal class CmshFlutterPluginTest {
    @Test
    fun onMethodCall_rejectsUnknownMethods() {
        val plugin = CmshFlutterPlugin()
        val result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("unknown", null), result)

        Mockito.verify(result).notImplemented()
    }
}
