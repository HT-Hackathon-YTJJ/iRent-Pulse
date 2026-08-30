# iRent Pulse

🔮 iRent 智能車況管家 — 和泰黑客松作品。以 Flutter 復刻 iRent App 主要頁面，並在其上實作四項改善功能。

目前已完成：**主要頁面骨架** + **功能一「安心上路輔助」完整流程** + **功能四「還車拍照偵測」L0–L3 全鏈路**。

---

## 快速開始

```bash
flutter pub get
./tool/fetch_l0_model.sh   # 下載 L0 的車體偵測模型（4 MB，不進版控）
flutter run                # 接上手機 / 模擬器
```

還車拍照要跑真的 AI 檢測時，另開一個終端機起後端：

```bash
api/run.sh
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
| 地圖首頁（同站租還／路邊租還、站點 Pin、立即預約／一鍵尋車） | `lib/screens/home_map_screen.dart` |
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
| 安心上路輔助 Bottom Sheet（五個分頁 + 互動標記） | `lib/screens/safe_drive_assist_screen.dart` |
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
├─ config/                     # 地圖金鑰開關與 Web 版 Maps JS 動態載入
├─ l0/                         # 還車拍照的端上檢查：相機、車體偵測、清晰度／曝光、閃光燈
├─ services/                   # 呼叫 api/ 的 L1／L2／L3，以及一次還車的逐張狀態
├─ widgets/                    # PillButton、深色 Sheet、車輛標頭、地圖底圖與 Pin
└─ screens/                    # 上表所有畫面

api/                           # L1／L2／L3 的 Python 後端，見 api/README.md
```

設計 token 對應 `docs/design-tokens.md` 與 Figma
（file `VA4ZaoUproMywy5bGoFC9w`，node `946-660`）。

### 換一台車要改什麼

只要在 `lib/data/vehicle.dart` 新增一個 `VehicleProfile`（規格、啟動步驟、五個 `AssistSection`），並把圖檔放進 `assets/images/`。標記座標 `marks` 是相對於 Figma 372×243 卡片的比例值，畫面會自動換算到實際尺寸，所以直接照 Figma 量就好。

---

## 安心上路輔助的 Bottom Sheet

用 `DraggableScrollableSheet`（Flutter 內建，不需要額外套件）疊在地圖上：

* 三段吸附點：**40% / 72% / 94%**，放手會自動吸到最近的一段。
* 最低只能拉到 40%，**拖不下去也關不掉**——避免行駛中誤觸關閉。關閉一律走右上角的 ✕。
* 拉到 40% 時圖說收起來，只留標題、分頁與說明列表；拉開後圖說自動回來並吃掉多出來的高度。
* 整個標題區都是拖曳把手（`_dragSheet` / `_settleSheet` 直接驅動 `DraggableScrollableController`），不是只有中間那條灰線；列表捲到頂端再往下拉也會收合 Sheet，符合 Material 的操作邏輯。
* 點圖上的紅色編號或下方清單時，Sheet 會自動至少展開到 72%，再把該項捲到視野內。

---

## 地圖

`lib/widgets/map_backdrop.dart` 內建兩套底圖，看 `.env` 裡有沒有金鑰自動切換。站點 Pin、使用者藍點、中心點與 zoom 兩邊共用，換底圖不會動到任何畫面。

| | 需要金鑰 | 說明 |
| --- | --- | --- |
| Google Maps | 是 | 真正的 Google 底圖，另外關掉 POI／大眾運輸標籤讓 Pin 更明顯 |
| OpenStreetMap | 否 | 圖磚套一層色彩矩陣調成接近 Google 的淺灰底，沒金鑰時的 fallback |

Pin 是用 Web Mercator 投影自己算螢幕座標畫上去的 Flutter widget（不是 `BitmapDescriptor`），兩套底圖長得一模一樣，PRO 標籤與點擊區都保留。

### 金鑰放哪

金鑰只存在專案根目錄的 `.env`，**已被 .gitignore 排除，不會進版控**。照 `.env.example` 複製一份填上即可：

```
GOOGLE_MAPS_API_KEY=AIza...
```

第一次 clone 下來（或換了金鑰）跑一次產生器，把 `.env` 的金鑰寫進 `lib/config/map_key.dart`：

```bash
./tool/gen_map_key.sh
```

之後直接跑就是 Google Maps，不需要任何額外參數：

```bash
flutter run -d chrome
```

`lib/config/map_key.dart` 同樣被 .gitignore 排除；版控裡只有 `map_key.example.dart` 範本。
沒跑產生器、或 `.env` 沒有金鑰時，`useGoogleMaps` 會是 false，自動退回 OpenStreetMap，不會壞掉。
CI 之類不方便放檔案的環境，仍可用 `--dart-define-from-file=.env` 覆蓋。

各平台怎麼拿到金鑰：

| 平台 | 來源 | 要不要手動貼 |
| --- | --- | --- |
| Web | `lib/config/maps_loader_web.dart` 啟動時動態插入 Maps JS `<script>` | 不用 |
| 全平台（Dart 端） | `tool/gen_map_key.sh` 從 `.env` 產生 `lib/config/map_key.dart` | 不用 |
| Android | `app/build.gradle.kts` 讀 `.env` → `manifestPlaceholders` → AndroidManifest | 不用 |
| iOS | `main()` 透過 `irent_pulse/maps` channel 把金鑰交給 `AppDelegate` 的 `GMSServices.provideAPIKey` | 不用 |

### 已知限制

`google_maps_flutter_web` 不吃 `GoogleMap.padding`，所以 Web 版沒辦法把 Google 標誌／版權列推到自訂 UI 上方，只能從我們這邊留白（首頁底部列因此多留了 14px）。Android／iOS 會正常吃 `padding`。

---

## 還車拍照偵測（功能四）

`docs/return-car-docs/分層規格書_v1.md` 的四層，端上一層、伺服器三層：

| 層 | 問題 | 位置 | 檔案 |
|---|---|---|---|
| **L0 拍攝防呆** | 這張照片拍好了嗎？ | 手機，每一幀 | `lib/l0/` |
| **L1 快篩** | 能判讀嗎？看得到車損嗎？車內乾淨嗎？ | 伺服器，**阻塞** | `api/app/l1.py` |
| **L2 影像確認** | 這個損傷是這趟造成的嗎？ | 伺服器，非同步 | `api/app/l2.py` |
| **L3 決策派工** | 車輛該進什麼狀態？誰要行動？ | 規則引擎，非 AI | `api/app/l3.py` |

伺服器三層的說明在 [`api/README.md`](api/README.md)。以下是端上這一層。

### L0 在手機上真的做了什麼

`ReturnCaptureScreen` 開的是真的相機，每一幀都在算：

| 檢查 | 方法 | 檔案 |
|---|---|---|
| 車體存在 + 畫面佔比 | COCO SSD MobileNet v1（TFLite）的 `car`／`truck`／`bus` bbox | `l0/car_detector.dart` |
| 完整性（四邊留白） | 同一個 bbox 是否貼齊畫面邊界 | `l0/aim.dart` |
| 清晰度 | 亮度平面的 Laplacian variance | `l0/frame_analysis.dart` |
| 曝光 | 亮度直方圖的過曝／過暗像素比 | `l0/frame_analysis.dart` |
| 匡線對齊 | bbox 與畫面上灰色輪廓線的 IoU（純幾何，不是模型） | `l0/aim.dart` |
| 連續確認 | 上述全過連續 5 幀才觸發快門 | `l0/aim.dart` |
| **自動閃光燈** | 同一份直方圖：連續 8 幀偏暗就自己開，亮回來 24 幀才關 | `l0/capture_session.dart` |

Android 拿到的是 YUV420、iOS 是 BGRA8888，兩邊都不解碼整張圖——
清晰度與曝光直接讀亮度平面，偵測用的 300×300 張量在取樣時順便把感光元件的
旋轉轉正，所以模型吐出來的框已經是螢幕方向的座標。

**快門永遠不會被鎖住。** 不合格只會跳「判定未達標」，仍然可以「仍要送出」，
那張照片會帶 `capture_mode: manual`／`bypassed` 上去讓 L1 加強檢查。
15 秒後門檻自動放寬 20%，30 秒後直接開放手動快門——
使用者站在停車場快門就是不觸發而放棄還車，代價遠大於一張品質普通的照片。

沒跑 `tool/fetch_l0_model.sh` 也不會壞：少了車體偵測，
清晰度與曝光照常擋，只是「車體存在／畫面佔比／匡線對齊」三項會略過。
沒有相機（桌機、Web、權限被拒）則整個退回原本的腳本情境。

測試：

```bash
flutter test          # L0 的純運算、逐張回報狀態機、無相機時的取景器
api/run.sh & api/.venv/bin/python -m pytest api/tests -q   # L3 規則表
```

`test/l0_test.dart` 釘住清晰度／曝光／旋轉取樣與門檻放寬，
`test/return_session_test.dart` 用假的 L1 回應把逐張回報與 issue 文案跑過一遍，
`test/return_capture_widget_test.dart` 確認沒有相機時取景器照樣能走完。

### 權限

| 平台 | 相機 | 定位 | 說明 |
|---|---|---|---|
| Android | `AndroidManifest.xml` | 同左 | 另有 `FLASHLIGHT`；`network_security_config.xml` 只對本機開發位址開明文 HTTP |
| iOS | `NSCameraUsageDescription` | `NSLocationWhenInUseUsageDescription` | Podfile 只編 `PERMISSION_CAMERA` 與 `PERMISSION_LOCATION` 兩個處理程式 |

執行期用 `permission_handler` 一次要齊。**相機是唯一硬需求**；
定位被拒絕不擋還車，只是還車地點標不準。

### 取車照片：目前還沒接

L2 要回答「這個損傷是這趟造成的嗎」，靠的是同一台車、同一個角度的**取車照**做集合差。
App 現在的取車流程沒有拍照這一步，所以真實模式下 L2 一律只能回「無法判定」，
由 L3 轉「停用（`undetermined`）」——這是規格書要的保守行為，不是壞掉。

後端本身已經吃得下取車照（`stage=pickup`），要看完整的三態判定可以先用腳本灌基準線：

```bash
api/.venv/bin/python api/scripts/demo_trip.py \
  --pickup 左前=取車_左前.jpg --return 左前=還車_左前.jpg
```

### 真實模式 vs 腳本情境

進還車流程時會先探測 `api/` 是否活著（`/healthz`，3 秒逾時）：

* **探得到** → 情境 ⓪「真實 AI 檢測」：相機跑 L0，每拍完一張立刻送 L1，
  分析頁逐張回報（`左前 ✓ 右前 ✓ 左後 ⏳`），離開頁面時才跑 L2／L3。
* **探不到** → 原本 Figma 板上的六個腳本情境照跑，一行程式都不會動到。

長按取景器標題可以隨時切換，Demo 現場網路掛掉也不會開天窗。

---

## 尚未實作

功能二「信用點數優化」、功能三「借車流程優化」。
