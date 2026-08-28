import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/tokens.dart';
import 'screens/home_map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      home: const HomeMapScreen(),
    );
  }
}
