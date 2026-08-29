import 'dart:math' as math;

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

/// The two ways a car can be picked up on the map. Both share one booking
/// sheet — only the wording and the pick-up point differ.
enum RentMode { station, roadside }

extension RentModeLabel on RentMode {
  String get label => this == RentMode.station ? '同站租還' : '路邊租還';

  /// Copy for the primary CTA at the bottom of the booking sheet.
  String get bookLabel => '預約$label';

  /// Heading above the pick-up address inside the dark card.
  String get pickupLabel => this == RentMode.station ? '取還車站點' : '停車位置';
}

/// One tile of the photo strip. The demo has no real inspection photos, so the
/// renders are reframed instead of cropped into new assets.
class VehiclePhoto {
  const VehiclePhoto({
    required this.asset,
    required this.caption,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String asset;
  final String caption;
  final BoxFit fit;
  final Alignment alignment;
}

/// An entry of the 租用履歷 tab. [reply] is iRent's answer to a complaint.
class RentalReview {
  const RentalReview({
    required this.date,
    required this.text,
    this.reply,
    this.negative = false,
  });

  final String date;
  final String text;
  final String? reply;
  final bool negative;
}

/// An entry of the 保養紀錄 tab.
class MaintenanceRecord {
  const MaintenanceRecord({
    required this.date,
    required this.title,
    required this.detail,
  });

  final String date;
  final String title;
  final String detail;
}

/// A single car offered on the map: a [VehicleProfile] plus everything that is
/// specific to *this* car sitting at *this* spot (plate, address, price…).
class VehicleListing {
  const VehicleListing({
    required this.vehicle,
    required this.mode,
    required this.region,
    required this.address,
    required this.hourlyRate,
    required this.lastUsedOn,
    this.assuranceRate = 70,
    this.mileageRate = 1.5,
    this.holdMinutes = 30,
  });

  final VehicleProfile vehicle;
  final RentMode mode;

  /// 營運區域，例如「北區」。
  final String region;

  /// 站點名稱（同站租還）或路邊停車位置（路邊租還）。
  final String address;

  /// 平日每小時租金。
  final int hourlyRate;

  /// 安心服務每趟加購金額。
  final int assuranceRate;

  /// 里程費（元 / 公里）。
  final double mileageRate;

  /// 取車保留倒數（分鐘）。
  final int holdMinutes;

  final String lastUsedOn;

  String get plate => vehicle.plate;

  int estimate({required int hours, required bool assurance}) =>
      hourlyRate * hours + (assurance ? assuranceRate : 0);
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
    this.photos = const [],
    this.equipment = const [],
    this.reviews = const [],
    this.maintenance = const [],
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

  /// Photo strip shown above the tabs of the booking sheet.
  final List<VehiclePhoto> photos;

  /// 規格配備 tab.
  final List<SpecRow> equipment;

  /// 租用履歷 tab.
  final List<RentalReview> reviews;

  /// 保養紀錄 tab.
  final List<MaintenanceRecord> maintenance;

  String get fullName => '$brand $model';

  AssistSection sectionById(String id) => assistSections.firstWhere(
    (s) => s.id == id,
    orElse: () => assistSections.first,
  );

  /// Every car on the map is the same model with its own plate.
  VehicleProfile withPlate(String plate) => VehicleProfile(
    plate: plate,
    brand: brand,
    model: model,
    heroImage: heroImage,
    sideImage: sideImage,
    interiorImage: interiorImage,
    specs: specs,
    startupSteps: startupSteps,
    startupNote: startupNote,
    assistSections: assistSections,
    photos: photos,
    equipment: equipment,
    reviews: reviews,
    maintenance: maintenance,
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

const _corollaPhotos = <VehiclePhoto>[
  VehiclePhoto(
    asset: 'assets/images/car_corolla_cross_hero.png',
    caption: '車輛外觀',
    fit: BoxFit.contain,
  ),
  VehiclePhoto(asset: 'assets/images/interior_start.jpg', caption: '車內座艙'),
  VehiclePhoto(
    asset: 'assets/images/car_corolla_cross.png',
    caption: '車頭近拍',
    alignment: Alignment.centerLeft,
  ),
];

const _corollaEquipment = <SpecRow>[
  SpecRow('車型級距', '跨界休旅車（CUV）'),
  SpecRow('乘坐人數', '5 人座'),
  SpecRow('排氣量', '1,798 c.c.'),
  SpecRow('引擎型式', '直列四缸 Dual VVT-i（油電版搭配電動馬達）'),
  SpecRow('動力輸出', '油電版・綜效最大馬力 122 ps'),
  SpecRow('變速系統', 'E-CVT 電子控制無段變速系統（油電）'),
  SpecRow('驅動方式', '前輪驅動（FF）'),
  SpecRow('車身尺碼', '長 4,460 mm × 寬 1,825 mm × 高 1,620 mm'),
];

const _corollaReviews = <RentalReview>[
  RentalReview(date: '2026/07/31', text: '空間真的很大，搬家超方便，下次還會再租'),
  RentalReview(
    date: '2026/07/28',
    text: '一上車就有濃濃的煙味，座椅上感覺還有煙灰',
    reply: '已派員清潔！感謝您的回報',
    negative: true,
  ),
  RentalReview(date: '2026/07/21', text: '車內很乾淨也沒有異味，還車拍照還會送點數，太好了'),
  RentalReview(date: '2026/07/14', text: '油電很省油，開一整天只加了半桶'),
];

const _corollaMaintenance = <MaintenanceRecord>[
  MaintenanceRecord(
    date: '2026/07/26',
    title: '定期保養',
    detail: '更換機油、機油芯，四輪定位檢查',
  ),
  MaintenanceRecord(
    date: '2026/06/30',
    title: '輪胎更換',
    detail: '更換前輪胎組（原廠規格 225/50 R18）',
  ),
  MaintenanceRecord(date: '2026/05/18', title: '車內清潔', detail: '座椅深層清潔、冷氣濾網更換'),
  MaintenanceRecord(
    date: '2026/04/02',
    title: '電池檢測',
    detail: '油電系統與 12V 電瓶健康度檢測，狀態正常',
  ),
];

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
  photos: _corollaPhotos,
  equipment: _corollaEquipment,
  reviews: _corollaReviews,
  maintenance: _corollaMaintenance,
);

// ---------------------------------------------------------------------------
// The cars sitting on the map. Same model throughout the demo — what changes
// per pin is the plate, the pick-up point and the price.
// ---------------------------------------------------------------------------

/// (車牌, 取車點, 平日時租)
const _stationSpots = <(String, String, int)>[
  ('REN-0000', 'iRent 成大自強站', 160),
  ('RCF-6603', 'iRent 台中寶善寺站（建議倒車入庫）', 160),
  ('RDT-1128', 'iRent 台中太原路站', 150),
  ('RBX-7420', 'iRent 中友百貨站 B2', 180),
  ('RAK-3391', 'iRent 一中商圈站', 170),
  ('RCM-5507', 'iRent 台中車站前站', 160),
  ('RDS-6182', 'iRent 忠明南路站', 150),
  ('RFN-9043', 'iRent 水源地公園站', 160),
];

const _roadsideSpots = <(String, String, int)>[
  ('RCF-6605', '新北市新店區北新路 200 號', 165),
  ('RGH-2274', '台中市北區太原路二段 88 號', 165),
  ('RJP-8810', '台中市北區梅亭街 12 號旁', 155),
  ('RKL-4406', '台中市中區綠川西街 33 號', 175),
  ('RNQ-1937', '台中市北區漢口路三段 51 號', 160),
  ('RPT-5528', '台中市西區美村路一段 9 號', 170),
  ('RSV-7761', '台中市北區崇德路一段 120 號', 155),
  ('RWZ-3094', '台中市中區民權路 76 號', 165),
];

List<VehicleListing> _listingsFor(RentMode mode) => [
  for (final (plate, address, rate)
      in mode == RentMode.station ? _stationSpots : _roadsideSpots)
    VehicleListing(
      vehicle: corollaCross.withPlate(plate),
      mode: mode,
      region: mode == RentMode.station ? '中區' : '北區',
      address: address,
      hourlyRate: rate,
      lastUsedOn: '115/7/31',
    ),
];

final stationListings = _listingsFor(RentMode.station);
final roadsideListings = _listingsFor(RentMode.roadside);

List<VehicleListing> listingsFor(RentMode mode) =>
    mode == RentMode.station ? stationListings : roadsideListings;

/// Taiwanese plates skip I and O so they cannot be read as 1 and 0.
const _plateLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

String _plate(math.Random rng) {
  final letters = [
    for (var i = 0; i < 3; i++)
      _plateLetters[rng.nextInt(_plateLetters.length)],
  ].join();
  return '$letters-${1000 + rng.nextInt(9000)}';
}

/// The cars behind one map pin.
///
/// 同站租還 → the whole fleet parked at that station: 3–4 cars sharing the
/// spot, the demo model throughout, with plates drawn from a generator seeded
/// on the station name so a card keeps its plate across rebuilds.
///
/// 路邊租還 → one pin is one car on the street, so that is the whole list; the
/// neighbouring cars are the neighbouring pins' cards in [deckFor].
List<VehicleListing> listingsAtPin(VehicleListing tapped) {
  if (tapped.mode == RentMode.roadside) return [tapped];

  final rng = math.Random(tapped.address.hashCode);
  final count = 3 + rng.nextInt(2);
  return [
    tapped,
    for (var i = 1; i < count; i++)
      VehicleListing(
        vehicle: corollaCross.withPlate(_plate(rng)),
        mode: tapped.mode,
        region: tapped.region,
        address: tapped.address,
        hourlyRate: tapped.hourlyRate,
        lastUsedOn: tapped.lastUsedOn,
      ),
  ];
}

/// Every card behind a mode's map pins, flattened in pin order.
///
/// One continuous deck rather than a fresh list per pin: tapping a pin then
/// *slides* the deck to that pin's card instead of swapping the text out from
/// under the card, and swiping the deck walks the map from pin to pin — the
/// way Google Maps keeps its marker and its card carousel on the same item.
class PinDeck {
  const PinDeck._(this.cards, this._pinOfCard, this._firstCardOfPin);

  final List<VehicleListing> cards;
  final List<int> _pinOfCard;
  final List<int> _firstCardOfPin;

  /// Which pin the card at [card] belongs to.
  int pinAt(int card) => _pinOfCard[card.clamp(0, _pinOfCard.length - 1)];

  /// The card a tap on [pin] should land on — the first of that pin's group.
  int cardAt(int pin) => _firstCardOfPin[pin % _firstCardOfPin.length];
}

PinDeck _buildDeck(RentMode mode) {
  final cards = <VehicleListing>[];
  final pinOfCard = <int>[];
  final firstCardOfPin = <int>[];

  final pins = listingsFor(mode);
  for (var pin = 0; pin < pins.length; pin++) {
    firstCardOfPin.add(cards.length);
    for (final listing in listingsAtPin(pins[pin])) {
      cards.add(listing);
      pinOfCard.add(pin);
    }
  }
  return PinDeck._(cards, pinOfCard, firstCardOfPin);
}

final _decks = <RentMode, PinDeck>{};

/// Built once per mode: the station fleets are randomly sized, so rebuilding
/// the deck would shuffle the card the user is looking at.
PinDeck deckFor(RentMode mode) =>
    _decks.putIfAbsent(mode, () => _buildDeck(mode));
