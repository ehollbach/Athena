package dev.ehollbach.athena_native

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** What Athena asks the phone: its memory and name, where to keep models, the free space there.
 *  The decision engine itself is libathena_engine.so, called from Dart over FFI. */
class AthenaNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "athena_native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceFacts" -> {
                val memory = ActivityManager.MemoryInfo()
                (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                result.success(
                    mapOf(
                        "platform" to "android",
                        "machine" to Build.MODEL,
                        "name" to deviceName(),
                        "ramBytes" to memory.totalMem,
                        "osVersion" to Build.VERSION.RELEASE,
                    )
                )
            }
            // not in Android's cloud backup, and not cleared as a cache when storage runs low
            "modelsDir" -> result.success(File(context.noBackupFilesDir, "models").apply { mkdirs() }.absolutePath)
            "freeBytes" -> result.success(StatFs(call.argument<String>("path")).availableBytes)
            "launchArguments" -> result.success(emptyList<String>())
            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on") == true
                activity?.runOnUiThread {
                    val window = activity?.window ?: return@runOnUiThread
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** "Google Pixel 8a", not "Google Google Pixel 8a" */
    private fun deviceName(): String {
        val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (Build.MODEL.startsWith(maker, ignoreCase = true)) Build.MODEL else "$maker ${Build.MODEL}"
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
}
