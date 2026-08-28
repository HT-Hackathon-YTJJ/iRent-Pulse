import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/map_config.dart';
import 'design/tokens.dart';
import 'screens/home_map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 地圖要在第一張地圖建立前初始化：Web 載 JS SDK、iOS 把金鑰交給 GMSServices。
  // 沒有金鑰（或初始化失敗）時會自動退回 OpenStreetMap 底圖。
  await initGoogleMaps();
  runApp(const IRentPulseApp());
}

class IRentPulseApp extends StatelessWidget {
  const IRentPulseApp({super.key});

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

    return MaterialApp(
      title: 'iRent Pulse',
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
      home: const HomeMapScreen(),
    );
  }
}
