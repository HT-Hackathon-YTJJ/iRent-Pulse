# iRent Pulse

iRent 智能車況管家 — 和泰黑客松作品。以 Flutter 復刻 iRent App 主要頁面，並在其上實作四項改善功能。

目前已完成：**主要頁面骨架** + **功能一「安心上路輔助」完整流程** + **功能四「還車拍照偵測」L0–L3 全鏈路**。

---

## 快速開始

```bash
flutter pub get
./tool/fetch_l0_model.sh   # 下載 L0 的車體偵測模型（4 MB，不進版控）
flutter run                # 接上手機 / 模擬器
```

> Android 需要 core library desugaring（`android/app/build.gradle.kts` 已開），
> `flutter_local_notifications` 用到 `java.time`，minSdk 21 的裝置沒有。

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
| --- | --- |
| 地圖首頁（同站租還／路邊租還、站點 Pin、立即預約／一鍵尋車） | `lib/screens/home_map_screen.dart` |
| 站點車輛卡片 deck（**查看更多**） | `lib/screens/pin_vehicles_sheet.dart` |
| 側邊選單（會員、錢包、優惠、回饋計畫） | `lib/screens/side_menu.dart` |
| 取車地圖 + 車輛卡片（開鎖） | `lib/screens/trip_screen.dart` |
| 信用分數與會員權益 | `lib/screens/credit_score_screen.dart` |
| 訂單明細（還車通知的落點） | `lib/screens/order_detail_screen.dart` |

### 地圖卡片的「查看更多」

收合的車輛卡片本身就是一個 sheet handle：左右滑可以換車，往上拉會長出訂車頁。
測試的人兩件都沒做——一張會動的卡片對已經知道手勢的人才是提示，而錯過它的代價
是整條訂車流程。所以手勢照留，旁邊加一顆紅色的「查看更多」，做的事跟往上拉
完全一樣，也因此在 sheet 拉開的過程中就淡出，不會變成第二顆做同一件事的按鈕。

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
| --- | --- |
| 偵測車款（掃描動畫） | `lib/screens/detecting_dialog.dart` |
| 車輛規格表 | `lib/screens/vehicle_spec_sheet.dart` |
| 如何啟動這輛車 | `lib/screens/start_vehicle_sheet.dart` |
| 是否啟用輔助 | `lib/screens/assist_prompt_dialog.dart` |
| 安心上路輔助 Bottom Sheet（五個分頁 + 互動標記） | `lib/screens/safe_drive_assist_screen.dart` |
| 車輛資訊（三種情境） | `lib/screens/vehicle_status_screen.dart` |
| 下車前確認清單 | `lib/screens/return_checklist_dialog.dart` |

**安心上路輔助的互動**：圖上的紅色編號可以點，點了會放大＋脈衝、其他標記變淡，下方清單同步捲到該項目；反過來點清單也會highlight對應標記。圖面固定在上方不會被捲走。車內總覽頁的紅色標籤可直接跳到對應分頁。

**車輛資訊的三種情境**：深色標題列右上角的膠囊（出發時／行駛中／油量不足）可切換，分別對應 85%／60%／24% 油量。24% 時會出現「無法還車」警示，還車確認清單也會變成橘色的「重新檢查」版本。這是給評審現場看不同狀態用的。

### 行駛中：Bottom Sheet，不是一頁

`vehicle_status_screen.dart` 是**疊在活地圖上的 sheet**，不是一個 route。

原本它是整頁 + 左上角返回鍵，那有兩個問題：返回鍵指向一個使用者不該回去的畫面
（車子已經解鎖在跑，「上一頁」不是一個存在的狀態），而整頁把開車的人真正需要
的東西——我在哪、最近的加油站在哪——蓋掉了。

* 三段吸附點 **45% / 74% / 96%**，整個深色標頭都是拖曳把手。
* 最低 45%：車牌、油量與「還車」在每一段都看得到，收起來是為了看地圖，不是
  為了失去控制項。
* **關不掉**。系統返回手勢會把 sheet 收到最低，不會離開畫面；離開這頁的唯一路徑
  是走完還車。
* 沒有返回鍵之後，iRent 標誌單獨靠左，兩個 badge 與情境膠囊整組靠右
  （`VehicleHeaderPanel(badgesTrailing: true)`）。

### App 被殺掉再開，租約要還在

`lib/services/trip_state.dart`。租用中是這個 App 裡唯一需要撐過 process 死亡的
狀態：車在跑、錢在算、還車被鎖在這頁後面。回到一張沒有任何租約痕跡的地圖，等於
告訴使用者「你的租約不見了」。

所以車牌、情境與 sheet 高度會寫進 `shared_preferences`，冷啟動時在 `runApp`
之前讀回來，第一幀就是行駛中——地圖首頁仍然先建立（還車完成後 pop 回去的就是
它），車輛資訊用零時長的轉場疊上去，看起來就是沒有離開過。

寫入只發生在「東西停下來」的時候：手放開 sheet、切換情境、還車完成，不是每一幀。

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
| --- | --- | --- | --- |
| **L0 拍攝防呆** | 這張照片拍好了嗎？ | 手機，每一幀 | `lib/l0/` |
| **L1 快篩** | 能判讀嗎？看得到車損嗎？車內乾淨嗎？ | 伺服器，**阻塞** | `api/app/l1.py` |
| **L2 影像確認** | 這個損傷是這趟造成的嗎？ | 伺服器，非同步 | `api/app/l2.py` |
| **L3 決策派工** | 車輛該進什麼狀態？誰要行動？ | 規則引擎，非 AI | `api/app/l3.py` |

伺服器三層的說明在 [`api/README.md`](api/README.md)。以下是端上這一層。

### L0 在手機上真的做了什麼

`ReturnCaptureScreen` 開的是真的相機，每一幀都在算：

| 檢查 | 方法 | 檔案 |
| --- | --- | --- |
| 車體存在 | COCO SSD MobileNet v1（TFLite）的 `car`／`truck`／`bus` bbox | `l0/car_detector.dart` |
| **距離**（`fill`） | bbox 與匡線的**面積開根號**比值 → 靠近一點／退後一步 | `l0/aim.dart` |
| **偏移**（`drift`） | 兩者中心距離 ÷ 匡線對角線 → 對齊輪廓線 | `l0/aim.dart` |
| 形狀 backstop | IoU，只當保險，不是判定依據 | `l0/aim.dart` |
| 完整性（四邊留白） | bbox 是否貼齊畫面邊界（**出血的匡線不套用**） | `l0/aim.dart` |
| 清晰度 | 亮度平面的 Laplacian variance | `l0/frame_analysis.dart` |
| 曝光 | 亮度直方圖的過曝／過暗像素比 | `l0/frame_analysis.dart` |
| 連續確認 | 上述全過連續 5 幀才轉綠 | `l0/aim.dart` |
| **自動閃光燈** | 同一份直方圖：連續 8 幀偏暗就自己開，亮回來 24 幀才關 | `l0/capture_session.dart` |

Android 拿到的是 YUV420、iOS 是 BGRA8888，兩邊都不解碼整張圖——
清晰度與曝光直接讀亮度平面，偵測用的 300×300 張量在取樣時順便把感光元件的
旋轉轉正，所以模型吐出來的框已經是螢幕方向的座標。

### 對齊判定為什麼重寫

第一版用**一個 IoU** 決定有沒有對準，那正是「框沒對到卻判定對到了、對到了又不顯示」
的原因。IoU 把「在哪裡」跟「多大」揉成一個數字：一台大小剛好但偏了半個車身的車，
分數等於一台正中央但太小的車，也等於一台構圖完美、只是 bbox 因為含到影子而偏高的車。
沒有任何一個門檻能讓好的過、壞的擋。

所以拆成兩個各自有物理意義的量測，而且都是**無量綱**的，在每支手機、每個角度
意思都一樣：

* `fill` = √(bbox 面積 / 匡線面積)。1.0 = 剛好填滿。這是唯一能翻譯成動作的量：
  太小就往前走，太大就往後退。
* `drift` = 兩者中心距離 ÷ 匡線對角線。這才是「對齊」。

再加三件讓讀數不再抖動的事：

* **指數平滑**：單發 SSD 就算手機放在桌上，框也會逐幀跳幾個百分點；5 Hz 下那個
  抖動剛好落在門檻兩側，把 badge 打成閃爍。
* **時效**：偵測只在真的跑推論的那幾幀送進來，超過 700ms 沒有新的框就失效。
  舊版的 `_lastCar` 永不過期，鏡頭轉開之後還在回報「已對準」。
* **遲滯**：已經鎖定的畫面用寬 18% 的門檻檢查，呼吸一下不會把快門從手上抽走。

### 相機焦段：固定在主鏡頭 1×

Android 把後鏡頭當成一顆涵蓋所有實體鏡頭的 *logical camera*，而且不保證開在 1×。
Pixel 10 Pro 上取景器大約開在 2×，使用者得往後退好幾步才能把車放進匡線——
一整個停車場的路，只為了拍一張主鏡頭原地就能拍的照片。CameraX 的 zoom ratio
是對主鏡頭定義的，所以 `setZoomLevel(1.0)` 就是「最好的後鏡頭，不裁切」，
`CaptureSession._resetZoom` 在 `initialize()` 之後明確要一次。右下角的
0.5×／1×／2× 是真的會動的，裝置做不到的檔位不會畫出來。

### 取景器畫面：整張畫，不裁切

原本預覽是 `BoxFit.cover` 鋪滿全螢幕。在 20:9 的手機上這會丟掉 4:3 串流的三分之一，
而且是**橫向**丟——這是使用者要站那麼遠的另一半原因，也是對齊讀數不可信的原因：
L0 在**影格**座標裡把車跟匡線比對，使用者在**螢幕**座標裡對齊，中間隔著一個裁切，
兩個矩形就不是同一個形狀。螢幕上看起來好好待在框裡的車，在模型看到的影格裡可能
已經貼著邊緣。

現在整張影格畫出來（上下留黑，chrome 本來就住在那裡），一個矩形、一個座標系，
使用者看到的就是感光元件看到的。

### 匡線：半透明示意圖 + 出血

* **示意圖不是外框**。純色剪影只能說「車大概放這裡」；要的是**可重複的角度**，
  而可重複意味著拿真實特徵去對畫出來的特徵——保險桿下緣、A 柱、輪拱與側裙交界。
  那些只存在於車圖裡，所以畫上去的是車圖（40% 不透明），輪廓線疊在上面帶狀態顏色。
* **灰 = 未對準・黃 = 距離不對・綠 = 已對準**，黃色的提示一定會說往哪走。
* **出血**：右前的匡線讓車尾跑出畫面**左邊**，左前相反（`CaptureSpot.guideBleed`）。
  完整放進畫面的匡線等於要求使用者拍整台車，那會把真正要記錄的那個角落——保險桿、
  頭燈、輪拱——縮成幾十個 pixel。讓遠端跑出畫面，近端才長得夠大。
  出血的那兩格不套用「車身被切到了」檢查，被切到就是照著做。
* 兩張**車尾**的匡線不出血：車尾本身就是主體，而且兩個後角都要拍到車牌。

### 匡線圖的左右曾經是反的

設計 repo 的四張車身圖是用**鏡像**命名的：`slot_paint_left_front.png` 是一台車頭
指向畫面右側的車，也就是站在**右前**角落的人看到的。直接照檔名出貨的結果是每一格
都拍到車的另一側——「右後」那格顯示的是左後視角，這就是 QA 回報的
「後面兩個車屁股拍照對調」。

對應表固定在 `tool/gen_slot_assets.py` 的 `SOURCES` 裡，不在 Dart：這樣
`CaptureSpot.art` 可以老老實實叫它顯示的角度，`test/capture_slots_test.dart`
也會在圖檔與 `guideAspect` 對不上時直接失敗。

### 匡線畫質

上游全部都是 72×72——設計 repo 是，Figma 板子裡的圖片填充也是（node 843:900
原生匯出只有 55×37）。沒有更高解析度的原圖可以拿，所以畫質是靠**怎麼放大**贏的：

* alpha 先當成平滑的場放大，再用很窄的斜坡重新切邊（SDF 字型繪製的做法），
  曲線就不會帶著 28 倍的階梯；
* 輪廓線在**輸出解析度**上才生成，是一條細而銳利的線，不是放大後的粗線；
* 彩色車圖走 Lanczos + unsharp，再以 40% 不透明度畫上去——柔和在這裡讀起來是
  「殘影」，不是「素材很爛」。

之後真的拿到清晰素材（4× 匯出或 SVG），丟一個 `slot_paint_<key>@4x.png` 到來源
資料夾旁邊，腳本會自動優先用它。

### 快門：使用者按，而且只在綠燈按

**L0 決定「可不可以按」，不決定「什麼時候按」。**
舊版一達標就自己拍，那個交易比看起來差：自動化喜歡的那一幀很少是人正要拍的那一幀，
它在人還在移動時就響了，而且拿走了流程裡唯一一個由使用者確認「這張對了」的時刻。

所以現在只有按鈕會拍，而且**只在綠燈**——黃燈或灰燈按下去會跳「判定未達標」，
那裡仍然提供「仍要送出」。快門是**被守門，不是被鎖死**：在昏暗停車場怎麼樣都轉不成
綠燈的人必須能完成還車，代價是一張普通的照片，而拒絕的代價是整趟還車。
15 秒後門檻自動放寬 20%，30 秒後直接開放。這段守則寫在 `_onShutter` 的註解裡；
如果哪天要拿掉那個逃生門，要一起改的就是那段註解。

沒跑 `tool/fetch_l0_model.sh` 也不會壞：少了車體偵測，
清晰度與曝光照常擋，只是「車體存在／畫面佔比／匡線對齊」三項會略過。
沒有相機（桌機、Web、權限被拒）則整個退回原本的腳本情境。

測試：

```bash
flutter test                                    # 端上
api/.venv/bin/python -m pytest api/tests -q     # 伺服器（不需要起 server）
```

| 檔案 | 釘住什麼 |
| --- | --- |
| `test/l0_test.dart` | 清晰度／曝光／旋轉取樣、`fill`／`drift` 各自的語意、平滑與時效、遲滯、出血格不報「被切到」、門檻放寬 |
| `test/capture_slots_test.dart` | 拍攝順序、每格的圖檔對到自己的角度、只有前兩格出血且互為鏡像、四層圖都在 bundle 裡、`guideAspect` 與圖檔相符 |
| `test/trip_state_test.dart` | 租約狀態的存／取／清除，還車後不會復活 |
| `test/return_session_test.dart` | 用假的 L1 回應把逐張回報與 issue 文案跑過一遍 |
| `test/return_capture_widget_test.dart` | 沒有相機時取景器照樣能走完 |
| `api/tests/test_board.py` | 留言板的解析，以及「留言只能往『既有』推」這條單向規則 |
| `api/tests/test_store.py` | 留言板的儲存與「只採計本趟開始前」的時間切點 |
| `api/tests/test_l3.py` | L3 規則表，以及留言如何被帶進車況履歷 |

### 權限

| 平台 | 相機 | 定位 | 說明 |
| --- | --- | --- | --- |
| Android | `AndroidManifest.xml` | 同左 | 另有 `FLASHLIGHT`；`network_security_config.xml` 只對本機開發位址開明文 HTTP |
| iOS | `NSCameraUsageDescription` | `NSLocationWhenInUseUsageDescription` | Podfile 只編 `PERMISSION_CAMERA` 與 `PERMISSION_LOCATION` 兩個處理程式 |

執行期用 `permission_handler` 一次要齊。**相機是唯一硬需求**；
定位被拒絕不擋還車，只是還車地點標不準。

### L2 的第二個證據：車輛歷程留言板

L2 只回答一件事：**是這趟造成的嗎？** 原本它只能從像素回答——同一個角度的取車照
與還車照做集合差。那是最強的證據，但它在最花錢的那個情境失效：

> 上一位使用者還車時車尾已經有一個凹洞。取車照沒拍到那個角度（或那趟根本沒拍
> 取車照）。下一位使用者拍到了洞，L2 找不到基準線只能回「無法判定」，L3 依規則 5
> 把車停用並送客服——而客服看到的是一張有洞的照片和一個沒有任何說明的訂單。

那個洞早就被記錄了。上一個人還車時把它打進了留言板。那句話就是缺的證據，而且免費。

所以留言被當成**證詞**：比照片弱，永遠不能推翻照片，但在沒有照片可比的時候可以定案。
`api/app/board.py` 的判定順序是固定的：

1. 同角度的取車照（證據）
2. **本趟開始前**寫的留言（證詞）
3. 無法判定（交給人看）

**留言只能把判定往「既有」推**——往不向這位使用者求償的方向推。它永遠不能製造一筆
「新增」，因為「有人這樣說」不是任何人該被求償的標準。取車照拍到該面板是乾淨的時候，
照片贏；只有**客服已複核**的留言能造成矛盾，而矛盾的結果是送人工，不是上帳單。

留言板是自由文字，所以 `board.parse` 把句子對回 `(部位, 類型)` 這組視覺層也在講的
詞彙——用的是封閉字彙的字面比對加一小張同義詞表。這刻意做得很笨，而且笨在安全的
方向：解析不出來的留言就跟沒寫過一樣，不會有任何誤判去扣到人。真的接上有標記 UI 的
留言板之後，`part`／`type` 會直接帶上來，這個函式只是旁邊那個自由輸入框的 fallback。

App 裡的留言板就是訂車頁的**租用履歷**（`VehicleProfile.reviews`）。真實模式開始時
`ReturnSession.publishBoard` 會把它連同各自的日期送上去，所以使用者在訂車頁讀到的
那句話，就是半小時後 L2 拿來衡量的那句話。

| 端點 | 用途 |
| --- | --- |
| `POST /v1/cars/{car_no}/notes` | 寫一則留言（`created_at` 可帶，用來回填既有的板） |
| `GET /v1/cars/{car_no}/notes?before=…` | 讀留言板；`before` 就是 L2 套用的時間切點 |

看它整條跑起來，不需要任何取車照：

```bash
api/.venv/bin/python api/scripts/demo_trip.py \
  --note "上一位使用者：後保險桿右側有一個洞，還車時已回報" \
  --return 右後=還車_右後.jpg
```

同一張照片跑兩次、一次帶 `--note` 一次不帶，同一個凹洞會從
**無法判定（車輛停用・送客服）**變成**既有（放行）**。

### 取車照片：App 端還沒接

App 現在的取車流程沒有拍照這一步。後端本身已經吃得下取車照（`stage=pickup`），
要看完整的三態判定可以用腳本灌基準線：

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

---

## 還車後的通知與訂單明細

Figma `分支A・清潔確認通知`（831:5789）把它畫在鎖定畫面上，還車一小時後：
「已確認車內整潔，您的信用分數維持不變，感謝配合✨」。那個時間點就是整個四層
設計的重點——櫃檯前不講任何車況，因為講得準的那幾層要花幾分鐘，而人要趕公車。

所以它是**真的作業系統通知**（`lib/services/notifications.dart`），不是 App 內
的 toast：通知送達時 App 通常已經在背景或已經關掉。同一則文案也會用
`ReturnNoticeBanner` 在 App 內顯示一次——投影機、靜音的模擬器、Web 版、或是
拒絕了權限的使用者，都還是看得到結果抵達。點哪一個都會開
`lib/screens/order_detail_screen.dart`（Figma 1010:6493）。

訂單明細的返回鍵直接回到**地圖首頁的起始位置**（`HomeMapScreen.resetToStart`），
不是回到上一頁：通知點進來時後面可能根本沒有任何 history，而產生這張訂單的那趟
租用已經結束了。

### 通知權限

兩個平台都要，而且安裝不會給：

| 平台 | 權限 | 在哪裡要 |
| --- | --- | --- |
| Android 13+ | `POST_NOTIFICATIONS`（`AndroidManifest.xml`） | 分析頁之後，`ReturnNotifications.requestPermission()` |
| iOS | `UNUserNotificationCenter` 授權 | 同上；另外 `AppDelegate` 要把自己設成 notification centre 的 delegate，否則 App 開著時 iOS 會直接吞掉通知 |

**都不在啟動時要。** 要的時機是還車分析結束、畫面上正寫著「結果將以通知告知，
您可立即離開」的那一刻——理由就在使用者眼前。拒絕不會擋住還車。

---

## 尚未實作

功能二「信用點數優化」、功能三「借車流程優化」。
