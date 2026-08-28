# iRent Pulse

🔮 iRent 智能車況管家 — 和泰黑客松作品。以 Flutter 復刻 iRent App 主要頁面，並在其上實作四項改善功能。

目前已完成：**主要頁面骨架** + **功能一「安心上路輔助」完整流程**。

---

## 快速開始

```bash
flutter pub get
flutter run            # 接上手機 / 模擬器
```

Web 版（適合投影 Demo）：

```bash
flutter run -d chrome
```

> 地圖圖磚需要網路。Demo 前請先跑一次讓圖磚進快取。

---

## 已實作的畫面

### 主要頁面（復刻 iRent）

| 畫面 | 檔案 |
|---|---|
| 地圖首頁（同站租還／路邊租還、站點 Pin、立即預約／一鍵尋車、情報列） | `lib/screens/home_map_screen.dart` |
| 側邊選單（會員、錢包、優惠、回饋計畫） | `lib/screens/side_menu.dart` |
| 取車地圖 + 車輛卡片（開鎖） | `lib/screens/trip_screen.dart` |

### 安心上路輔助流程

```
取車地圖 ──開鎖──▶ 偵測車款 ──▶ 車輛規格 ──開始使用車輛──▶ 如何啟動這輛車
                                                              │
                                                            了解了
                                                              ▼
                                                    是否啟用安心上路輔助？
                                          ┌───────────────────┴───────────────────┐
                                       開啟                                    暫不開啟
                                          ▼                                       ▼
                                    安心上路輔助 ──關閉──────────────────────▶ 車輛資訊
                                                                                  │
                                                                                 還車
                                                                                  ▼
                                                                        下車前請再次確認
```

| 畫面 | 檔案 |
|---|---|
| 偵測車款（掃描動畫） | `lib/screens/detecting_dialog.dart` |
| 車輛規格表 | `lib/screens/vehicle_spec_sheet.dart` |
| 如何啟動這輛車 | `lib/screens/start_vehicle_sheet.dart` |
| 是否啟用輔助 | `lib/screens/assist_prompt_dialog.dart` |
| 安心上路輔助（五個分頁 + 互動標記） | `lib/screens/safe_drive_assist_screen.dart` |
| 車輛資訊（三種情境） | `lib/screens/vehicle_status_screen.dart` |
| 下車前確認清單 | `lib/screens/return_checklist_dialog.dart` |

**安心上路輔助的互動**：圖上的紅色編號可以點，點了會放大＋脈衝、其他標記變淡，下方清單同步捲到該項目；反過來點清單也會highlight對應標記。圖面固定在上方不會被捲走。車內總覽頁的紅色標籤可直接跳到對應分頁。

**車輛資訊的三種情境**：深色標題列右上角的膠囊（出發時／行駛中／油量不足）可切換，分別對應 85%／60%／24% 油量。24% 時會出現「無法還車」警示，還車確認清單也會變成橘色的「重新檢查」版本。這是給評審現場看不同狀態用的。

---

## 專案結構

```
lib/
├─ design/tokens.dart          # 色彩／圓角／陰影／字級 semantic token
├─ data/vehicle.dart           # 車款資料：規格、啟動步驟、五個分區的圖說內容與標記座標
├─ widgets/                    # PillButton、深色 Sheet、車輛標頭、地圖底圖與 Pin
└─ screens/                    # 上表所有畫面
```

設計 token 對應 `docs/design-tokens.md` 與 Figma
（file `VA4ZaoUproMywy5bGoFC9w`，node `946-660`）。

### 換一台車要改什麼

只要在 `lib/data/vehicle.dart` 新增一個 `VehicleProfile`（規格、啟動步驟、五個 `AssistSection`），並把圖檔放進 `assets/images/`。標記座標 `marks` 是相對於 Figma 372×243 卡片的比例值，畫面會自動換算到實際尺寸，所以直接照 Figma 量就好。

---

## 地圖

目前用 `flutter_map` + OpenStreetMap 圖磚，套一層色彩矩陣把它調成接近 Google Maps 的淺灰底。**不需要 API key**，適合現在這個階段。

要換成真正的 Google Maps：加入 `google_maps_flutter`、把 `lib/widgets/map_backdrop.dart` 裡的 `FlutterMap` 換成 `GoogleMap`，中心點與 zoom 參數不用動。要換成其他有樣式的圖磚（Stadia Alidade Smooth、CARTO Positron）則只需要改 `MapBackdrop.tileUrl`，但兩者都需要金鑰。

---

## 尚未實作

功能二「信用點數優化」、功能三「借車流程優化」、功能四「拍照偵測」。
