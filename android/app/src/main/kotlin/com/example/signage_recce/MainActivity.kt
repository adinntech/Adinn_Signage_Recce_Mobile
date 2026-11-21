package com.example.signage_recce

import com.example.signage_recce.ar.ArBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Camera AR (ARCore) bridge + native view. Isolated: devices without
        // ARCore never create a session and the rest of the app is unaffected.
        val ar = ArBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("adinn/ar_view", ar.viewFactory)
    }
}
