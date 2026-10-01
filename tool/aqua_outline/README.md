# AQUA 輪廓模型

還車拍照四角的「跟著你轉的 3D 輪廓」（`lib/guide/`）畫的是這台車。這個資料夾
產生 App 載入的 `assets/models/aqua_outline.json`，也留著驗證它比例正確的工具。

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python export.py           # → assets/models/aqua_outline.json
.venv/bin/python views.py views.png  # 正側、正前、正後、俯視 + 四個角
```

## 為什麼自己建，而不是用現成模型

試過的 3D 生成服務外框都不準。輪廓引導唯一要對的就是外框，所以模型是用
**官方尺寸 + 照片校正出來的側面輪廓**參數化做出來的，細節（燈、格柵、門縫）
只畫成線，不建成幾何。

| 規格 | 數值 | 來源 |
|---|---|---|
| 全長 × 全寬 × 全高 | 4,050 × 1,695 × 1,455 mm | toyota.jp 主要諸元 2019-03（NHP10 小改款） |
| 軸距 | 2,550 mm | 同上 |
| 輪距 前 / 後 | 1,470 / 1,460 mm | 同上 |
| 最低地上高 | 140 mm | 同上 |
| 前懸 / 後懸 | 850 / 650 mm | Prius c 2015 是 810 / 635（全長 3,995）；小改款保桿加長 55 mm，這裡分成前 40、後 15 |
| 輪胎 | 185/60R15（外徑 603 mm） | vehiclesizes.com |

**全高 1,455 是量到車頂鯊魚鰭天線的頂端。** 兩張照片疊圖都顯示車頂本身低
3–5 cm，所以車頂降下來、天線另外建。

## 車身怎麼建（`aqua.py`）

沿車長每幾公分切一個橫截面，再把截面串起來（loft）。每個截面：

- 上下緣來自側面輪廓（`UPPER`、`lower_z`，輪拱是 `lower_z` 裡的圓弧）
- 寬度來自俯視收窄（`plan`：車頭圓、車尾上半部收得比保桿多）
- 腰線以上內傾（`z_belt`、`w_belt`、`top_edge`）：引擎蓋、擋風玻璃、車頂、
  尾門各有自己的「冠」深度

另外建：輪胎（圓角鼓）、後照鏡、輪拱內襯（把輪拱挖穿的通道封起來）、
車頂天線、尾翼（它是懸在後擋上方的一片翼，不是車頂的延伸）。

## 細節線（`features.py`）

窗框、B 柱、門縫、車頭燈、引擎蓋接縫、格柵、霧燈進氣口、尾燈、後擋、車牌。
每條線存成「錨點 + 投射方向」，建模時才投到車身上，所以車身再改，線也會貼著。

錨點的來源有兩種：

- 從照片描下來、再透過解出來的相機反投影到車身上（`features_src.json`，
  `features.py` 的 `trace()` 產生）
- 直接由車身參數算出來（窗框、擋風玻璃上下緣）

側面照和前 3/4 照對車門位置的判斷差了約 12 cm（長焦的深度模糊），B 柱和
門縫取兩者中間。

## 怎麼驗證外框比例

用兩張 Commons 上的 AQUA 小改款照片（`./fetch_refs.sh` 下載，都是 TTTNIS
拍攝、CC0）：

1. `fit.py`：只用模型**確定知道**的東西 — 輪轂中心、輪圈橢圓的上下左右極值、
   輪胎接地點 — 反解每張照片的相機（位置、朝向、焦距）。殘差 3.6 px 與 2.8 px。
2. `overlay.py`：用解出來的相機把模型輪廓畫在照片上，看車頂、車尾、車頭、
   輪拱、後照鏡哪裡對不上，回頭改參數。

```bash
./fetch_refs.sh
.venv/bin/python fit.py                                    # 重解兩台相機
.venv/bin/python overlay.py refs/2017-2021_Toyota_Aqua_rear.jpg side_cam.json side.jpg
.venv/bin/python overlay.py refs/2017-2021_Toyota_Aqua.jpg front_cam.json front.jpg
```

`docs/orbit-guide/overlay_check.jpg` 是目前這版的疊圖。

`detect_pose.py` 則是反過來驗 App 的方位判斷，用 App 同一個 COCO SSD 模型。
兩件事是用它量出來的：

- **偵測器的框比模型扁 4.4%**。對兩張參考照片，拿偵測器的框跟「用解出來的
  相機投影模型」的框比，長寬比 1.048 與 1.040。App 的 `detectorAspectBias`
  就是這個數字。
- **只看框的形狀，距離會把角度帶偏**：同一個 40° 在 4.7 m 是 1.86、11 m 是 2.17。
  所以 App 用的是方位 × 距離的表，先用框寬推距離。

`demo/return_photos/` 的照片不適合拿來驗角度：那幾張是近拍，車的一端跑出照片外，
框被切短，讀出來會偏正面。

`export.py` 另外輸出 `hull`：模型凸包上的頂點（不含車頂天線）。框只會碰到凸包，
App 預測偵測器的框時只投影這幾百個點。
它需要 `ai-edge-litert`，Python 3.9 的 wheel 在 macOS 上缺 dylib，用 3.12：
`uv venv --python 3.12 .venv312 && uv pip install --python .venv312/bin/python ai-edge-litert numpy pillow`。

## 渲染（`render.py`）

App 的 `lib/guide/outline_renderer.dart` 的 Python 版，演算法一模一樣，
驗證和出圖用：投影 → 分正反面 → 低解析度反深度緩衝 → 取輪廓邊（正反面交界）、
摺邊（>32°）和細節線 → 逐點取樣，和 3×3 鄰域最遠深度比較決定可見。
