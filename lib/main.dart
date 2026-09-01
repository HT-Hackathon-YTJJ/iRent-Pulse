import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/map_config.dart';
import 'design/tokens.dart';
import 'screens/home_map_screen.dart';
import 'screens/order_detail_screen.dart';
import 'services/notifications.dart';
import 'services/trip_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 地圖要在第一張地圖建立前初始化：Web 載 JS SDK、iOS 把金鑰交給 GMSServices。
  // 沒有金鑰（或初始化失敗）時會自動退回 OpenStreetMap 底圖。
  await initGoogleMaps();
  // 通知通道要在任何人排程通知之前備好；權限留到真的要發時才要。
  await ReturnNotifications.instance.init();
  // 讀在 runApp 之前：租用中的話第一幀就要是「行駛中」，不能先閃一下地圖首頁
  // 再把 Sheet 疊上去。
  final resumed = await TripStore.load();
  runApp(IRentPulseApp(resumedTrip: resumed));
}

class IRentPulseApp extends StatelessWidget {
  const IRentPulseApp({super.key, this.resumedTrip});

  /// A rental that was still running when the app was last killed.
  final ActiveTrip? resumedTrip;

  @override
  Widget build(BuildContext context) {
    // 'Noto Sans TC' resolves from the webfont on web and from the bundled CJK
    // face on iOS/Android; the fallback list keeps weights correct everywhere.
    const family = 'Noto Sans TC';
    const fallback = <String>[
      'PingFang TC',
      'Noto Sans CJK TC',
      'Microsoft JhengHei',
    ];

    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColor.page,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: AppColor.brand,
        onPrimary: AppColor.textInverse,
        secondary: AppColor.accentBlue,
        surface: AppColor.card,
        onSurface: AppColor.textPrimary,
        error: AppColor.brand,
      ),
    );

    // Tapping the 分支A 通知 opens 訂單明細, from anywhere — including a cold
    // start, where there is no widget tree yet to route from.
    ReturnNotifications.instance.onOpenOrder = (_) {
      final navigator = ReturnNotifications.navigatorKey.currentState;
      navigator?.push(OrderDetailScreen.route());
    };

    return MaterialApp(
      title: 'iRent Pulse',
      navigatorKey: ReturnNotifications.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamily: family,
          fontFamilyFallback: fallback,
          bodyColor: AppColor.textPrimary,
          displayColor: AppColor.textPrimary,
        ),
        primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: family,
          fontFamilyFallback: fallback,
        ),
      ),
      // The reference screenshots came from a phone with an enlarged system
      // font, which is what made the first replica read oversized. Pinning the
      // scale keeps every control at its designed size on any device.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.0,
        child: child!,
      ),
      home: HomeMapScreen(resumedTrip: resumedTrip),
    );
  }
}
