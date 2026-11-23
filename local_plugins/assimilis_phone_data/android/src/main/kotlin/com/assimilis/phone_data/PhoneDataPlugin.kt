package com.assimilis.phone_data

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers the phone-data channel in every Flutter engine, including WorkManager's background one. */
class PhoneDataPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PhoneDataChannel.register(binding.binaryMessenger, binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
