import 'package:flutter/material.dart';

/// One numbered callout on a diagram. [marks] are fractional positions
/// (0..1 of the diagram card) — a single item can have several markers when the
/// control appears more than once (e.g. audio keys on both steering spokes).
class AssistItem {
  const AssistItem({
    required this.number,
    required this.title,
    required this.description,
    required this.marks,
  });

  final int number;
  final String title;
  final String description;
  final List<Offset> marks;
}

/// A hotspot on the interior overview that jumps to another section.
class OverviewHotspot {
  const OverviewHotspot({
    required this.label,
    required this.sectionId,
    required this.position,
  });

  final String label;
  final String sectionId;
  final Offset position;
}

/// How the diagram bitmap is placed inside the diagram card.
///
/// [boxWidthFactor] is the fraction of the card width the diagram box occupies
/// (centred). [imageRect] reproduces a crop authored in Figma as fractional
/// left/top/width/height of that box; when null the bitmap is simply contained.
class DiagramLayout {
  const DiagramLayout({this.boxWidthFactor = 1.0, this.imageRect});

  final double boxWidthFactor;
  final Rect? imageRect;

  static const fill = DiagramLayout();
}

class AssistSection {
  const AssistSection({
    required this.id,
    required this.label,
    required this.image,
    required this.items,
    this.contentAspect,
    this.layout = DiagramLayout.fill,
    this.hotspots = const [],
  });

  final String id;
  final String label;
  final String image;
  final List<AssistItem> items;

  /// Intrinsic aspect ratio of [image]. When set, the diagram card adopts it so
  /// the drawing fills the card instead of sitting in a letterbox, and marker
  /// positions (authored against Figma's 372x243 card) are remapped to match.
  final double? contentAspect;
  final DiagramLayout layout;

  /// Only the overview section carries hotspots.
  final List<OverviewHotspot> hotspots;

  bool get isOverview => hotspots.isNotEmpty;
}

class SpecRow {
  const SpecRow(this.label, this.value);
  final String label;
  final String value;
}

class StartupStep {
  const StartupStep(this.text);
  final String text;
}

class VehicleProfile {
  const VehicleProfile({
    required this.plate,
    required this.brand,
    required this.model,
    required this.heroImage,
    required this.sideImage,
    required this.interiorImage,
    required this.specs,
    required this.startupSteps,
    required this.startupNote,
    required this.assistSections,
  });

  final String plate;
  final String brand;
  final String model;
  final String heroImage;
  final String sideImage;
  final String interiorImage;
  final List<SpecRow> specs;
  final List<StartupStep> startupSteps;
  final String startupNote;
  final List<AssistSection> assistSections;

  String get fullName => '$brand $model';

  AssistSection sectionById(String id) => assistSections.firstWhere(
    (s) => s.id == id,
    orElse: () => assistSections.first,
  );
}

// ---------------------------------------------------------------------------
// Toyota Corolla Cross — content transcribed from the Figma flow.
// ---------------------------------------------------------------------------

const _overview = AssistSection(
  id: 'overview',
  label: '車內總覽',
  image: 'assets/images/assist_overview.png',
  items: [],
  hotspots: [
    OverviewHotspot(
      label: '儀表板',
      sectionId: 'dashboard',
      position: Offset(0.324, 0.263),
    ),
    OverviewHotspot(
      label: '方向盤按鍵',
      sectionId: 'steering',
      position: Offset(0.359, 0.494),
    ),
    OverviewHotspot(
      label: '排檔桿',
      sectionId: 'shifter',
      position: Offset(0.617, 0.560),
    ),
    OverviewHotspot(
      label: '開關',
      sectionId: 'switches',
      position: Offset(0.082, 0.638),
    ),
  ],
);

const _dashboard = AssistSection(
  id: 'dashboard',
  contentAspect: 1739 / 904,
  label: '儀表板',
  image: 'assets/images/assist_dashboard.png',
  items: [
    AssistItem(
      number: 1,
      title: '轉速表',
      description: '顯示引擎每分鐘的轉速，單位通常為「×1000 r/min」',
      marks: [Offset(0.220, 0.276)],
    ),
    AssistItem(
      number: 2,
      title: '速率表',
      description: '顯示車輛目前的行駛速度，單位為「km/h」',
      marks: [Offset(0.492, 0.181)],
    ),
    AssistItem(
      number: 3,
      title: '車外溫度',
      description: '顯示目前的車外環境溫度，顯示範圍約為「−40°C～50°C」',
      marks: [Offset(0.694, 0.412)],
    ),
    AssistItem(
      number: 4,
      title: '時鐘',
      description: '顯示目前的時間，方便駕駛掌握行程時間',
      marks: [Offset(0.887, 0.379)],
    ),
    AssistItem(
      number: 5,
      title: '多功能資訊顯示幕',
      description: '顯示油耗、續航里程、行車狀態及車輛警示訊息',
      marks: [Offset(0.796, 0.535)],
    ),
    AssistItem(
      number: 6,
      title: '里程表與計程表',
      description: '顯示車輛累積總里程，以及可歸零的單次行程里程',
      marks: [Offset(0.844, 0.737)],
    ),
    AssistItem(
      number: 7,
      title: '排檔位置及檔位指示燈',
      description: '顯示車輛目前使用的排檔位置及檔位狀態',
      marks: [Offset(0.734, 0.737)],
    ),
    AssistItem(
      number: 8,
      title: '顯示變更按鈕',
      description: '用來切換里程、計程及其他儀表資訊的顯示內容',
      marks: [Offset(0.651, 0.671)],
    ),
    AssistItem(
      number: 9,
      title: '燃油表',
      description: '顯示油箱內剩餘的燃油量，接近「E」時應注意補充燃油',
      marks: [Offset(0.489, 0.704)],
    ),
    AssistItem(
      number: 10,
      title: '引擎冷卻液溫度表',
      description: '顯示引擎冷卻液溫度，接近「H」時可能表示引擎過熱',
      marks: [Offset(0.220, 0.724)],
    ),
  ],
);

const _switches = AssistSection(
  id: 'switches',
  contentAspect: 1501 / 1048,
  label: '開關',
  image: 'assets/images/assist_switches.png',
  items: [
    AssistItem(
      number: 1,
      title: '頭燈照射角度水平調整旋鈕',
      description: '依照乘客及行李載重情況，調整頭燈光束的照射高度，避免影響對向駕駛',
      marks: [Offset(0.121, 0.214)],
    ),
    AssistItem(
      number: 2,
      title: 'AHB 智慧型遠光燈自動切換系統開關',
      description: '開啟後可依前方車輛及道路照明情況，自動切換遠光燈與近光燈',
      marks: [Offset(0.188, 0.214)],
    ),
    AssistItem(
      number: 3,
      title: 'ODO／TRIP 開關',
      description: '用來切換總里程與單次行程里程，長按時可將單次行程里程歸零',
      marks: [Offset(0.309, 0.214)],
    ),
    AssistItem(
      number: 4,
      title: '車外後視鏡開關',
      description: '用來選擇左側或右側後視鏡，並調整鏡面的上下左右角度',
      marks: [Offset(0.812, 0.498)],
    ),
    AssistItem(
      number: 5,
      title: '車門鎖開關',
      description: '用來由車內同時上鎖或解鎖所有車門',
      marks: [Offset(0.745, 0.551)],
    ),
    AssistItem(
      number: 6,
      title: '電動窗開關',
      description: '用來升起或降下各車門的車窗，駕駛座可控制所有車窗',
      marks: [Offset(0.812, 0.597)],
    ),
    AssistItem(
      number: 7,
      title: '電動窗鎖定開關',
      description: '開啟後可停用其他座位的電動窗開關，避免乘客誤操作',
      marks: [Offset(0.737, 0.724)],
    ),
  ],
);

const _shifter = AssistSection(
  id: 'shifter',
  contentAspect: 283 / 243,
  label: '排檔桿',
  image: 'assets/images/assist_shifter.png',
  layout: DiagramLayout(
    boxWidthFactor: 283 / 372,
    imageRect: Rect.fromLTWH(-0.2191, 0.033, 1.311, 0.934),
  ),
  items: [
    AssistItem(
      number: 1,
      title: 'VSC OFF 開關',
      description: '用來關閉車身穩定控制系統；一般行駛時建議保持開啟，以協助降低車輛打滑或失控的風險',
      marks: [Offset(0.341, 0.321)],
    ),
    AssistItem(
      number: 2,
      title: 'USB 插槽',
      description: '用來連接 USB 裝置，可為手機充電，部分插槽也支援音樂播放或手機連線功能',
      marks: [Offset(0.336, 0.465)],
    ),
    AssistItem(
      number: 3,
      title: 'Auto Hold 自動定車煞車系統開關',
      description: '開啟後，車輛停止時可自動維持煞車，暫時不需持續踩住煞車踏板',
      marks: [Offset(0.401, 0.535)],
    ),
    AssistItem(
      number: 4,
      title: '駐車煞車開關',
      description: '用來啟用或解除電子駐車煞車；停車後應確認駐車煞車已啟用',
      marks: [Offset(0.481, 0.617)],
    ),
  ],
);

const _steering = AssistSection(
  id: 'steering',
  contentAspect: 1692 / 930,
  label: '方向盤按鍵',
  image: 'assets/images/assist_steering.png',
  items: [
    AssistItem(
      number: 1,
      title: '儀表控制開關',
      description: '用來切換儀表板顯示內容，以及選擇或調整各項車輛設定',
      marks: [Offset(0.204, 0.440)],
    ),
    AssistItem(
      number: 2,
      title: '方向燈控制桿',
      description: '用來啟動左右方向燈，並控制頭燈、位置燈、尾燈、牌照燈、日間行車燈及前後霧燈',
      marks: [Offset(0.207, 0.288)],
    ),
    AssistItem(
      number: 3,
      title: '兩車間距設定開關',
      description: '在 ACC 啟用時，用來調整與前方車輛之間的跟車距離',
      marks: [Offset(0.737, 0.383)],
    ),
    AssistItem(
      number: 4,
      title: '定速系統開關',
      description: '用來啟用及設定 ACC 全速域主動式車距維持定速系統，可自動調整車速並與前車保持適當距離',
      marks: [Offset(0.836, 0.403)],
    ),
    AssistItem(
      number: 5,
      title: '音響控制鍵',
      description: '用來調整音量、切換音源或選擇上一首與下一首曲目',
      marks: [Offset(0.188, 0.584), Offset(0.852, 0.564)],
    ),
    AssistItem(
      number: 6,
      title: 'LTA 車道循跡輔助開關',
      description: '用來啟用車道循跡輔助系統，協助車輛維持在車道中央行駛',
      marks: [Offset(0.734, 0.486)],
    ),
    AssistItem(
      number: 7,
      title: '電話控制鍵',
      description: '用來接聽或結束藍牙連線手機的通話',
      marks: [Offset(0.285, 0.473)],
    ),
    AssistItem(
      number: 8,
      title: '語音控制鍵',
      description: '用來啟動車載語音控制功能，以語音操作電話、音響或其他支援功能',
      marks: [Offset(0.282, 0.605)],
    ),
    AssistItem(
      number: 9,
      title: '擋風玻璃雨刷及噴水器開關',
      description: '用來啟動雨刷、調整刷動速度，以及噴灑清洗液清潔擋風玻璃',
      marks: [Offset(0.831, 0.276)],
    ),
    AssistItem(
      number: 10,
      title: '喇叭',
      description: '按下方向盤中央位置時，可發出警示聲響，提醒其他車輛或行人注意',
      marks: [Offset(0.516, 0.440)],
    ),
  ],
);

const corollaCross = VehicleProfile(
  plate: 'REN-0000',
  brand: 'Toyota',
  model: 'COROLLA CROSS',
  heroImage: 'assets/images/car_corolla_cross.png',
  sideImage: 'assets/images/car_corolla_cross_hero.png',
  interiorImage: 'assets/images/interior_start.jpg',
  specs: [
    SpecRow('啟動方式', '按鍵啟動'),
    SpecRow('駐車方式', '電子手煞車'),
    SpecRow('AUTO HOLD', '有'),
    SpecRow('倒車顯影', '有'),
    SpecRow('排檔方式', '中央鞍座傳統排檔桿'),
    SpecRow('油箱蓋位置', '車身左後方'),
  ],
  startupSteps: [
    StartupStep('踩住煞車踏板'),
    StartupStep('確認排檔桿位於 P 檔'),
    StartupStep('按下方向盤右側的 START 按鍵'),
  ],
  startupNote: '引擎啟動後，儀表板會亮起並顯示 READY',
  assistSections: [_overview, _dashboard, _switches, _shifter, _steering],
);
