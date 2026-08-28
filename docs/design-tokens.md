# iRent Pulse — Design Token 規格

> **來源**：[`Tinghedy/irent-car-scan`](https://github.com/Tinghedy/irent-car-scan)（Vite + React + Tailwind 的「取還車」六頁流程原型），其 token 定義於 `src/tokens/tokens.css` 與 `tailwind.config.js`，並對映 Figma Design System（file `VA4ZaoUproMywy5bGoFC9w`）。
>
> **本文件的用途**：來源專案的 token 是以 CSS 變數 + Tailwind class 表達，綁定 Web 技術棧。本文件把同一套設計決策**抽象成與平台無關的語意規格**，供 iRent Pulse（Flutter）實作時對照，避免直接照抄 Tailwind class 名或 CSS 變數。
>
> **狀態**：規格文件，尚未有對應的 Dart 實作。附錄 D 提供落地骨架建議。

---

## 1. Token 架構

採兩層式，這是來源專案已確立的原則，本專案沿用：

```
Primitive（原始值層）          Semantic（語意層）              元件 / 畫面
─────────────────────         ──────────────────────         ─────────────
red.500  = #D91C26     ──▶    action.primary          ──▶    主按鈕底色
neutral.900 = #262626  ──▶    text.primary            ──▶    標題、卡片標題
radius.18              ──▶    radius.card             ──▶    卡片、提示膠囊
```

**規則**

1. **元件只能使用 semantic token**。Primitive 僅供 semantic 引用，不得在畫面或元件程式碼中直接使用。
2. **改主色 = 只改一處**。例如品牌紅換色，只需改 `action.primary` 指向的 primitive，所有使用處自動更新。
3. **語意名描述「用途」，不描述「外觀」**。用 `status.success` 而非 `green`；用 `action.primary` 而非 `red`。
4. 新增顏色前先問：現有 semantic token 是否已涵蓋此用途？若只是「同一用途的另一個狀態」，應加為狀態變體（見 §3.1）而非新色。

### 命名規則

本文件使用**點分層級**的平台中立命名：`類別.群組.角色[.狀態]`

| 類別 | 前綴 | 說明 |
|---|---|---|
| 色彩 | `color.*` | 對應來源 CSS 變數 `--c-*` |
| 圓角 | `radius.*` | 對應 `--r-*` |
| 字級 | `type.*` | 對應 `.t-*` utility class |
| 間距 | `space.*` | 來源未語意化，本文件補上（§4） |
| 陰影 | `elevation.*` | 來源為 inline 值，本文件抽出（§5） |
| 覆蓋層 | `overlay.*` | 來源為 inline 值，本文件抽出（§6） |

---

## 2. Primitive 層

Primitive 是不帶語意的原始值清單。**實作時建議設為私有**（Dart 的 `_` 前綴或獨立 private library），從外部無法存取，以強制執行 §1 規則 1。

### 2.1 色票

| Primitive | Hex | ARGB | 備註 |
|---|---|---|---|
| `red.500` | `#D91C26` | `0xFFD91C26` | 品牌紅 |
| `red.600` | `#B01720` | `0xFFB01720` | 品牌紅 · 按下態 |
| `red.50` | `#FBE9EA` | `0xFFFBE9EA` | 品牌紅 · 極淡底 |
| `green.500` | `#1E9E5A` | `0xFF1E9E5A` | 成功 |
| `green.300` | `#3FD37E` | `0xFF3FD37E` | 成功 · 深底版本 |
| `amber.500` | `#E8A33D` | `0xFFE8A33D` | 警示 |
| `amber.50` | `#FBF1DC` | `0xFFFBF1DC` | 警示 · 極淡底 |
| `amber.gold` | `#D4A82C` | `0xFFD4A82C` | 獎勵 / 點數 |
| `blue.400` | `#58B0D0` | `0xFF58B0D0` | 輔助強調 |
| `neutral.900` | `#262626` | `0xFF262626` | 主要文字 |
| `neutral.500` | `#808085` | `0xFF808085` | 處理中狀態 |
| `neutral.450` | `#8C8C8C` | `0xFF8C8C8C` | 次要文字 |
| `neutral.400` | `#999999` | `0xFF999999` | 深底上的次要文字 |
| `neutral.350` | `#A6A6A6` | `0xFFA6A6A6` | 提示 / placeholder |
| `neutral.300` | `#D9D9D9` | `0xFFD9D9D9` | 進度條軌道 |
| `neutral.200` | `#E6E6E6` | `0xFFE6E6E6` | 分隔線 / 卡片框 |
| `neutral.150` | `#F2F3F5` | `0xFFF2F3F5` | 次級底色 |
| `neutral.100` | `#F5F5F5` | `0xFFF5F5F5` | 頁面底色 |
| `neutral.camera` | `#4A4A4A` | `0xFF4A4A4A` | 相機頁切換鈕啟用態 |
| `neutral.ink` | `#0D0D0F` | `0xFF0D0D0F` | 相機頁全屏底 |
| `white` | `#FFFFFF` | `0xFFFFFFFF` | — |

> 中性色刻度採「數字越大越深」，與色相色票一致。`neutral.450` / `neutral.350` 是為了對齊 Figma 既有值而插入的中間階，不是刻度錯誤。

### 2.2 字體家族

| Primitive | 值 | 用途 |
|---|---|---|
| `font.sans` | Noto Sans TC | 全部中文與一般文字 |
| `font.mono` | IBM Plex Mono | 數值（如相機 zoom 倍率），需等寬對齊 |

字重使用 400 / 500 / 700 三級，不使用其他字重。

### 2.3 尺度刻度

**間距**（8-point grid，含必要的 4 / 10 例外階）

`4` · `8` · `10` · `12` · `16` · `20` · `24` · `32` · `48`

**圓角**

`4` · `8` · `10` · `18` · `full`（9999，即完全膠囊化）

---

## 3. Semantic 層

### 3.1 色彩語意

#### 動作（Action）

| Token | Primitive | 用途 |
|---|---|---|
| `color.action.primary` | `red.500` | 主要行動按鈕底色、目前步驟指示 |
| `color.action.primary.pressed` | `red.600` | 主要按鈕按下 / active 態 |
| `color.action.primary.soft` | `red.50` | 品牌色的極淡背景（提示區塊、標籤底） |

#### 文字（Text）

| Token | Primitive | 用途 |
|---|---|---|
| `color.text.primary` | `neutral.900` | 標題、卡片標題、主要內容 |
| `color.text.secondary` | `neutral.450` | 副標、說明文字、進度說明 |
| `color.text.placeholder` | `neutral.350` | 弱化附註、免責說明、輸入提示 |
| `color.text.inverse` | `white` | 深色底上的文字（相機頁、主按鈕文字） |
| `color.text.onDark.secondary` | `neutral.400` | 深色底上的次要文字 |

> `text.inverse` 與 `text.onDark.secondary` 是一組：深色底上的主／次階層，不要用 `text.secondary` 疊在深底上。

#### 表面（Surface）

| Token | Primitive | 用途 |
|---|---|---|
| `color.surface.card` | `white` | 卡片、一般頁面底、底部按鈕列 |
| `color.surface.page` | `neutral.100` | 頁面底色（與卡片區隔時使用） |
| `color.surface.subtle` | `neutral.150` | 次級區塊底 |
| `color.surface.camera` | `neutral.ink` | 相機取景全屏底 |
| `color.surface.toggleActive` | `neutral.camera` | 相機頁切換控制項的啟用態 |

#### 邊界（Border）

| Token | Primitive | 用途 |
|---|---|---|
| `color.border.divider` | `neutral.200` | 分隔線、卡片外框 |
| `color.border.track` | `neutral.300` | 進度條未填滿的軌道 |

#### 狀態（Status）

| Token | Primitive | 語意 |
|---|---|---|
| `color.status.success` | `green.500` | 完成、通過、已對準 |
| `color.status.success.onDark` | `green.300` | 同上，但用於深色底（相機頁） |
| `color.status.warning` | `amber.500` | 需注意、尚未對準 |
| `color.status.warning.soft` | `amber.50` | 警示訊息的背景底 |
| `color.status.reward` | `amber.gold` | 獎勵 / 點數 |
| `color.status.processing` | `neutral.500` | **處理中**（進行中的進度填色） |

> ⚠️ `status.processing` 在來源專案的變數註解寫作 `Neutral-Fail`，但實際語意是「處理中」而非「失敗」。本文件正名為 `processing`。**目前這套設計沒有失敗／錯誤色**——若日後需要錯誤態，須另行定義，不可挪用 `action.primary`（品牌紅）當錯誤色，兩者語意會互相污染。

#### 強調（Accent）

| Token | Primitive | 用途 |
|---|---|---|
| `color.accent.blue` | `blue.400` | 輔助強調（連結、資訊標記） |

### 3.2 圓角語意

| Token | 值 | 用途 |
|---|---|---|
| `radius.bar` | 4 | 進度條（軌道與填色兩者皆是） |
| `radius.capsule` | 8 | 狀態膠囊（「接近」「已對準」） |
| `radius.chip` | 10 | 相機頁的照片 slot 縮圖 |
| `radius.card` | 18 | 卡片、圖片容器、浮動提示膠囊 |
| `radius.button` | full | 主要按鈕（pill 形） |

> 圓角依**元件角色**命名而非依數值，因此「把卡片圓角從 18 改成 20」是改一個 token，不需要逐處尋找 `18`。

### 3.3 字級語意

字體家族除 `type.data.mono` 外一律為 `font.sans`。

| Token | 尺寸 | 字重 | 行高 | 用途 |
|---|---|---|---|---|
| `type.title.l` | 24 | 700 | 1.4 | 頁面主標題（「還車分析完成」） |
| `type.title.s` | 18 | 700 | 預設 | 卡片標題（「照片可判讀性」） |
| `type.nav.title` | 17 | 700 | 預設 | 導覽列標題 |
| `type.button.l` | 17 | 700 | 預設 | 主要按鈕文字 |
| `type.body.l` | 16 | 500 | 1.85 | 頁面副標、狀態膠囊文字、深色底提示 |
| `type.body.m` | 15 | 400 | 預設 | 一般內文 |
| `type.body.s` | 14 | 400 | 預設 | 卡片內結果文字、弱化說明 |
| `type.caption` | 12 | 500 | 預設 | 百分比數值、極小註記 |
| `type.data.mono` | 14 | 500 | 預設 | 數值顯示（等寬，`font.mono`） |

> `type.nav.title` 與 `type.button.l` 目前數值相同（17/700），但語意不同、可能各自演進，**維持為兩個 token**，不要合併。

---

## 4. 間距語意（本文件新增）

來源專案的間距散落在版面程式碼中，未語意化。整理後歸納出以下實際使用的階層，建議在本專案落地為 semantic token：

| Token | 值 | 用途 |
|---|---|---|
| `space.xs` | 4 | 標題與副標之間的緊密行距 |
| `space.sm` | 8 | 相鄰小元件（slot 縮圖之間） |
| `space.md` | 12 | 標題群組內的元素間距 |
| `space.lg` | 16 | 卡片內距、卡片之間的間距 |
| `space.xl` | 20 | 頁面主要區塊之間 |
| `space.2xl` | 24 | 底部按鈕列的上內距 |
| `space.3xl` | 32 | 卡片標題與內容的分隔 |
| `space.4xl` | 48 | 大型區塊分隔（完成頁 icon 與文案之間） |

**版面常數**（非 token，但實作時需一致）

| 項目 | 值 |
|---|---|
| 設計基準畫布 | 390 × 844（iPhone 14 邏輯像素） |
| 導覽列高度 | 56 |
| 底部按鈕列內距 | 左右 77、上 24、下 40 |
| 卡片內距 | 16；卡片高度 112 |
| 進度條高度 | 8 |
| 相機 slot 縮圖 | 56 × 56 |
| 快門按鈕 | 72 × 72 |
| 卡片外框寬度 | 1.5 |

> 左右 77 的按鈕列內距是 390 寬下的視覺結果（按鈕寬 236）。**在 Flutter 應以「按鈕最大寬度 236 置中」表達**，而非硬寫 77 的左右 padding，否則在不同螢幕寬度會失衡。

---

## 5. 陰影語意（本文件新增）

來源專案的陰影是 inline 字面值，抽出如下：

| Token | 規格 | 用途 |
|---|---|---|
| `elevation.card` | y 3、blur 6、黑 8% | 卡片 |
| `elevation.bottomBar` | y 1、blur 50、黑 15% | 底部按鈕列（大範圍柔和暈開，用於與內容分層） |

> 來源專案另有兩處陰影屬於 demo 外框（手機模擬框 `y 20 / blur 60 / 黑 20%`、步驟指示器 `y 1 / blur 3 / 黑 12%`），**不是產品 token**，不納入。

---

## 6. 覆蓋層語意（本文件新增）

相機頁的深色情境需要一組半透明疊層，來源專案以 inline 值表達，抽出如下：

| Token | 規格 | 用途 |
|---|---|---|
| `overlay.scrim.top` | 黑 60% → 透明，垂直漸層，高 160 | 取景畫面頂部，讓導覽列文字可讀 |
| `overlay.scrim.bottom` | 黑 70% → 透明，垂直漸層，高 240 | 取景畫面底部，讓快門與提示可讀 |
| `overlay.hint.background` | 黑 60% | 浮動提示膠囊（「再靠近一點」）底色 |
| `overlay.slot.fill` | 白 20% | 相機 slot 縮圖底 |
| `overlay.slot.border` | 白 35% | 相機 slot 縮圖框 |
| `overlay.slot.fillMuted` | 白 10% | 「更多」slot 的弱化底 |
| `overlay.shutter.ring` | 白 50% | 快門按鈕外環 |

> 來源專案的漸層是 progressive blur 的**簡化替代**（見附錄 C）。若本專案要 1:1 還原 Figma 的漸進模糊，這組 scrim token 的定義需一併調整。

---

## 7. 元件層規格

以下用抽象規格描述來源專案的六頁 UI，實作時對照使用（欄位皆為 semantic token）：

### 主要按鈕（Primary Button）
底色 `color.action.primary`／按下 `color.action.primary.pressed`／文字 `color.text.inverse` + `type.button.l`／圓角 `radius.button`／垂直內距 12／寬度撐滿容器（最大 236）。

### 底部按鈕列（Bottom Action Bar）
底色 `color.surface.card`／陰影 `elevation.bottomBar`／內距見 §4／固定於頁面底部，內含一顆主要按鈕。

### 導覽列（Nav Bar）
高度 56／標題置中，`type.nav.title`／返回鍵置於左側／深色頁面上文字用 `color.text.inverse`。

### 分析卡片（Analysis Card）
底 `color.surface.card`／框 1.5 `color.border.divider`／圓角 `radius.card`／陰影 `elevation.card`／內距 16／高 112。
標題 `type.title.s` + `color.text.primary`。
- **處理中態**：軌道 `color.border.track`，填色 `color.status.processing`，圓角 `radius.bar`；左下說明 `type.body.s` + `color.text.secondary`，右下百分比 `type.caption` + `color.text.primary`。
- **完成態**：整條 `color.status.success`（滿格），下方結果文字 `type.body.s` + `color.status.success`。

### 狀態膠囊（Status Pill）
圓角 `radius.capsule`／內距 左右 16、上下 4／文字 `type.body.l` + `color.text.inverse`／底色依狀態：已對準 `color.status.success`、尚未對準 `color.status.warning`。

### 相機 Slot 縮圖（Slot Chip）
56 × 56／圓角 `radius.chip`／底 `overlay.slot.fill`／框 1 `overlay.slot.border`；「更多」變體底色改用 `overlay.slot.fillMuted`。

### 快門（Shutter）
72 × 72 圓形／白色實心／外環 4 `overlay.shutter.ring`／按下縮放至 95%。

### 完成標記（Success Mark）
外圈 200 圓形，`color.status.success` 10% 透明度；內圈 120 圓形實心 `color.status.success`；勾號 `color.text.inverse`。

---

## 8. 平台對映

同一個 semantic token 在三個平台的表達方式：

| 語意 Token | 來源 CSS 變數 | 來源 Tailwind class | 本專案（Flutter）建議 |
|---|---|---|---|
| `color.action.primary` | `--c-action-primary` | `bg-action-primary` | `context.tokens.color.actionPrimary` |
| `color.text.primary` | `--c-text-primary` | `text-text-primary` | `context.tokens.color.textPrimary` |
| `color.surface.card` | `--c-surface-card` | `bg-surface-card` | `context.tokens.color.surfaceCard` |
| `radius.card` | `--r-card` | `rounded-card` | `context.tokens.radius.card` |
| `type.title.l` | `.t-title-l` | `text-title-l` | `context.tokens.type.titleL`（`TextStyle`） |

**命名轉換規則**：語意路徑 `color.action.primary.pressed` → Dart 屬性 `actionPrimaryPressed`（去掉類別前綴、其餘 camelCase）。

**Flutter 專屬注意事項**

1. **不要用 `ColorScheme.fromSeed`**。本設計系統的顏色是設計決策而非演算法產物，種子色會產生一組不受控的衍生色。應以 `ThemeExtension` 承載本文件的 token，`ColorScheme` 只填必要的框架欄位並直接指定值。
2. **字重與 Noto Sans TC**。需在 `pubspec.yaml` 註冊 400/500/700 三個字重的字檔；Flutter 不會自動合成中文字重，缺字重會 fallback 成錯誤的視覺重量。
3. **`radius.button` = full**。Flutter 用 `StadiumBorder`，不要寫 `BorderRadius.circular(9999)`。
4. **`elevation.bottomBar` 的 blur 50**。Flutter 的 `BoxShadow.blurRadius` 與 CSS blur 語意接近但不完全相同，落地後需目視校正。
5. **狀態變體用 `WidgetStateProperty`**。`action.primary` / `action.primary.pressed` 應綁在同一個按鈕樣式的不同 state，而非兩顆按鈕。

---

## 9. 維護流程

1. **設計端變更** → 更新 Figma style → 更新本文件對應表格 → 更新 Dart token 實作。
2. **新增 token 前**先確認現有語意無法涵蓋（§1 規則 4）。
3. **不得**在畫面程式碼中出現字面色碼、字級數值或圓角數值。Code review 應以此為檢查點。
4. 本文件與實作若出現落差，**以本文件為準**，並修正實作。

---

## 附錄 A — 來源專案的已知落差

抽取過程中發現的不一致，本專案實作時**不應複製**：

| 落差 | 說明 |
|---|---|
| `type.nav.title` 未接出 | `tokens.css` 定義了 `.t-nav-title`，但 `tailwind.config.js` 的 `fontSize` 沒有對應項；元件中的 `text-nav` class 因此無效，導覽列標題實際為瀏覽器預設字級。 |
| `color.text.onDark.secondary` 用錯 class | 元件寫 `text-on-dark-secondary`，但 Tailwind 產生的正確 class 是 `text-text-on-dark-secondary`，實際未生效。 |
| 四個 token 定義但未接出 | `surface.toggleActive`、`status.success.onDark`、`status.warning.soft`、`status.reward` 在 `tokens.css` 有定義，但未接進 Tailwind，畫面上無法使用。本文件保留這些語意，因為它們對應 Figma 中已存在的設計決策。 |
| `body.l` 定義重複且不一致 | `tokens.css` 的 `.t-body-l` 沒有行高，`tailwind.config.js` 的 `body-l` 有 1.85 行高。本文件以 1.85 為準。 |
| 未定義錯誤／失敗色 | 見 §3.1 的說明。 |

## 附錄 B — 完整流程（設計脈絡）

來源原型涵蓋還車流程六個畫面，token 的使用情境由此而來：

```
1 相機·接近 → 2 相機·已對準 → 3 分析中 → 4 分析完成 → 5 可安心還車 → 6 還車完成
```

畫面 1–2 為深色相機情境（`surface.camera` + `text.inverse` + overlay 系列），3–6 為淺色情境（`surface.card` + `text.primary`）。這是設計系統需要**兩套文字階層**（一般／深底）的原因。

一項貫穿的設計原則值得記下：**引導優先、資訊克制**——分析完成頁明確不顯示任何車損判定，僅告知流程進度。這影響 token 的使用方式：`status.success` 用於「流程完成」而非「車況良好」。

## 附錄 C — 來源原型的已知簡化

以下是 demo 取捨，非設計定案，本專案實作時需回頭確認 Figma 原始設計：

- 相機頁的 progressive blur 暗角以線性漸層簡化（見 §6）。
- 完成頁 icon 為綠圈勾佔位，非正式資產。
- 車輛照片為灰色佔位圖。

## 附錄 D — Flutter 落地骨架（建議）

尚未實作。建議結構：

```
lib/design_system/
├─ tokens/
│   ├─ primitives.dart      // 私有原始值，_Red500 等
│   ├─ color_tokens.dart    // ThemeExtension<AppColors>
│   ├─ type_tokens.dart     // ThemeExtension<AppTypography>
│   ├─ shape_tokens.dart    // radius / elevation / spacing
│   └─ tokens.dart          // BuildContext extension: context.tokens
└─ components/              // §7 的元件
```

`ThemeExtension` 的最小示意：

```dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.actionPrimary,
    required this.actionPrimaryPressed,
    required this.textPrimary,
    // ...
  });

  final Color actionPrimary;
  final Color actionPrimaryPressed;
  final Color textPrimary;

  static const light = AppColors(
    actionPrimary: Color(0xFFD91C26),        // ← primitive red.500
    actionPrimaryPressed: Color(0xFFB01720), // ← primitive red.600
    textPrimary: Color(0xFF262626),          // ← primitive neutral.900
  );

  @override
  AppColors copyWith({Color? actionPrimary, Color? actionPrimaryPressed, Color? textPrimary}) =>
      AppColors(
        actionPrimary: actionPrimary ?? this.actionPrimary,
        actionPrimaryPressed: actionPrimaryPressed ?? this.actionPrimaryPressed,
        textPrimary: textPrimary ?? this.textPrimary,
      );

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
          actionPrimaryPressed: Color.lerp(actionPrimaryPressed, other.actionPrimaryPressed, t)!,
          textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
        );
}
```

搭配一個 `BuildContext` extension，讓取用點維持在語意層：

```dart
extension TokenContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppTypography get type => Theme.of(this).extension<AppTypography>()!;
}
```

**深色主題**：來源設計沒有 dark mode（相機頁的深色是**情境**，不是主題）。若日後要加，`ThemeExtension` 的第二個實例即為擴充點，屆時需重新檢視每個 semantic token 在深色下的指向。
