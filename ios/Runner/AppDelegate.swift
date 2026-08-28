import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Dart 端在 runApp() 之前會用這條 channel 把 .env 的金鑰送過來，
  /// 所以 iOS 不需要把金鑰寫死在原生程式碼裡，clone 下來就能直接跑。
  private static let mapsChannel = "irent_pulse/maps"

  /// GMSServices 只吃第一次的金鑰；hot restart 會重跑 main()，所以要記住。
  private var mapsKeyProvided = false

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.mapsChannel,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "provideApiKey" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let key = call.arguments as? String, !key.isEmpty else {
        // 沒金鑰不是錯誤，Dart 端會自己退回 OpenStreetMap 底圖。
        result(false)
        return
      }
      if self?.mapsKeyProvided == true {
        result(true)
        return
      }
      let ok = GMSServices.provideAPIKey(key)
      self?.mapsKeyProvided = ok
      result(ok)
    }
  }
}
