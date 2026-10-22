package com.aitone.studio
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
class MainActivity : FlutterActivity() {
    private var bridge: PedalDeviceBridge? = null
    private var recording: ToneRecordingBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = PedalDeviceBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        recording = ToneRecordingBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onDestroy() { recording?.dispose();recording=null; bridge?.dispose(); bridge = null; super.onDestroy() }
}
