package com.uplayer.u_player

import android.content.Context
import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GoBackendBridge.register(flutterEngine, applicationContext)
        GoBackendBridge.handleSessionGrantUri(intent?.dataString)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        GoBackendBridge.handleSessionGrantUri(intent.dataString)
    }
}