import 'package:flutter/material.dart';

/// Semantic design tokens for the iRent Pulse demo.
///
/// Values trace back to the Figma design system
/// (file VA4ZaoUproMywy5bGoFC9w) and to docs/design-tokens.md.
class AppColor {
  AppColor._();

  // Brand
  static const brand = Color(0xFFD91C26);
  static const brandPressed = Color(0xFFB01720);
  static const brandSoft = Color(0xFFFBE9EA);
  static const brandBright = Color(0xFFEB000A);

  // Surface
  static const card = Color(0xFFFFFFFF);
  static const page = Color(0xFFF5F5F5);
  static const subtle = Color(0xFFF5F5F7);
  static const sheetDark = Color(0xFF4A4A4A);
  static const sheetDarkDeep = Color(0xFF3C3C3C);

  // Text
  static const textPrimary = Color(0xFF262626);
  static const textInk = Color(0xFF1F1F24);
  static const textSecondary = Color(0xFF8C8C8C);
  static const textMuted = Color(0xFF73737A);
  static const textOnDark = Color(0xFFB3B3B3);
  static const textInverse = Color(0xFFFFFFFF);

  // Status
  static const success = Color(0xFF1E9E5A);
  static const successBright = Color(0xFF1FAD63);
  static const successText = Color(0xFF149E52);
  static const successSoft = Color(0xFFF0FAF5);
  static const successMint = Color(0xFFCDFFC0);

  static const warning = Color(0xFFE8A33D);
  static const warningSoft = Color(0xFFFFF5E5);
  static const warningSoftAlt = Color(0xFFFBF1DC);
  static const warningText = Color(0xFFB86B0D);

  // Accent
  static const accentBlue = Color(0xFF58B0D0);
  static const accentBlueSoft = Color(0xFFE8F6FA);
  static const mint = Color(0xFF00C8B3);

  // Line
  static const divider = Color(0xFFE6E6E6);
  static const track = Color(0xFFD9D9DB);
}

class AppRadius {
  AppRadius._();
  static const bar = 4.0;
  static const chip = 10.0;
  static const checklist = 14.0;
  static const card = 15.0;
  static const sheet = 20.0;
  static const dialog = 28.0;
  static const pill = 999.0;
}

class AppShadow {
  AppShadow._();

  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

  static const cardStrong = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4)),
  ];

  static const dialog = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 32, offset: Offset(0, 10)),
  ];

  static const bottomBar = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -2)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

/// Type ramp. Family resolution is left to the theme so that the web build can
/// use the Noto Sans TC webfont while mobile falls back to the system CJK face.
class AppText {
  AppText._();

  static const displayFuel = TextStyle(
    fontSize: 50,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );
  static const displayAmount = TextStyle(
    fontSize: 32,
    height: 1.0,
    fontWeight: FontWeight.w700,
  );
  static const titleXl = TextStyle(
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
  static const titleL = TextStyle(
    fontSize: 23,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );
  static const titleM = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );
  static const titleS = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );
  static const bodyL = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
  static const bodyM = TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const bodyS = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.6,
  );
  static const bodySMedium = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
  static const captionS = TextStyle(
    fontSize: 11,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const micro = TextStyle(
    fontSize: 10,
    height: 1.4,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
  static const button = TextStyle(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );
}
