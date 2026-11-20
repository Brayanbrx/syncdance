package ai.syncdance.syncdance_mobile

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Singing: the guide may only play while the student sings when it
        // goes to headphones; through the speaker the microphone hears it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai.syncdance/audio_route")
            .setMethodCallHandler { call, result ->
                if (call.method == "output") {
                    result.success(guideOutput())
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Where media sound goes: Android sends it to headphones when any are connected. */
    private fun guideOutput(): String {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val types = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.type }
        return when {
            types.any { it in WIRED } -> "wired"
            types.any { it in BLUETOOTH } -> "bluetooth"
            else -> "speaker"
        }
    }

    private companion object {
        // Constants from newer Android versions are plain numbers: on an older
        // phone they simply never match.
        val WIRED = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
        )
        val BLUETOOTH = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_HEARING_AID,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
        )
    }
}
