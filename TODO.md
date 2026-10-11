# 待办 / 待澄清

> 记录用户提到、但尚未决定开发的事项。**记录不等于已开发**——等用户确认后再动手。

## 当前状态

- 2026-10-10：用户报了一组问题（见第 1 节），**代码一律未动**，等确认范围后统一开工。
- 已交付：v0.1.0 / v0.2.0 / v0.3.0 build 3 / v0.3.1 build 4 / v0.3.2 build 5。
- 上面所有版本的**功能均未在真机上被确认过**（记录里没有一条）。

---

## 1. 用户新报的五个问题（v0.3.3 候选，已全部定位到行）

### 1.1 点通知后直接入账，必须让用户确认 ⚠️ 严重

**现状（已核实）**：全仓**没有** `UNUserNotificationCenterDelegate` / `didReceive` / `willPresent` /
`onOpenURL` / `UIApplicationDelegate`——**点通知根本没有回调**，只是把 App 拉到前台。
真正写库的是 `App/RootTabView.swift:113` 的 `.task { runAutoFill() }` 和 `114-117` 的
`.onChange(of: scenePhase)`（回到 `.active` 就再跑一次）。`178-182` 调
`Persistence.shared.runAutoFill()`，写完才在 `102-112` 弹一句「套餐已自动记入」。
**先静默写库、后弹提示，用户无法拒绝、无法撤销。**

**对照**：手动一键加是有确认的——`Features/Today/TodayView.swift:123-139` 的 `confirmationDialog`。

**改法方向**：`runAutoFill` 拆成「算出待写条目 → 弹确认（列出套餐名、条目、合计热量）→ 用户点了才写」。
顺带给 `Reminders.swift` 的 `content` 加 `userInfo`（带上模板 id），点通知能定位到具体套餐。

### 1.2 套餐入账后应显示成套餐，而不是一条条平铺

**现状（已核实）**：两条路径都走 `Data/Store+Template.swift:85-117` 的 `writeItems`，把模板拆成多条
`FoodEntry` 写库。字段差异：

- `runAutoFill`（`167-193`）写 `externalID = "template:<模板UUID>:yyyyMMdd"`
- `applyTemplate`（`63-82`）写 `externalID: nil` ❌ **完全缺失分组键**
- 两条路径都写 `source = "template"`（`111`）、`note = "来自套餐「模板名」"`（`109`）、
  `foodID = item.foodID`（食物 ID，不是套餐 ID）
- 展示侧 `Features/Today/TodayView.swift:296-354` 只按 meal 过滤，`349-351` 逐条 `foodRow`

**结论**：**现在无法把套餐识别成套餐**。只剩 `source="template"` 和 note 里的套餐名（改名或同名就失真），
只有自动补录那条路径能靠 externalID 前缀反推。

**改法方向**：① `applyTemplate` 也写稳定的套餐标识（复用补录键格式，或新增字段）；
② 今日清单按该键折叠成一行「套餐：标准晚餐 · 3 件 · 520 千卡」，可展开。

⚠️ **迁移红线**：`Data/Persistence.swift` 的容错逻辑是「store 加载失败就**删掉重建**」。
真要在 `FoodEntry` 上加字段，**必须同时开启轻量迁移**（`shouldMigrateStoreAutomatically` /
`shouldInferMappingModelAutomatically`），否则用户全部记录会被一键清空。

### 1.3 顺带查出的连带 bug：套餐会同日重复写一份

`applyTemplate` **不查** `hasAutoFilled`。所以「先自动补录、再手动一键加」会在同一天各写一份。
修 1.1 时一并处理。

### 1.4 联网商品热量「基本都是 0」

**根因（已核实，不是解析错）**：

- 主源**下厨房**：`Data/FoodSearchService.swift:168-176` 把 `kcalPer100: 0, proteinPer100: 0,
  carbsPer100: 0, fatPer100: 0` **硬编码写死**；`172` 的注释自己写着「下厨房不提供营养表，留空让上层兜底」
- 备源 **Open Food Facts**：字段映射是对的（`energy-kcal_100g` → `kcalPer100` 等，`266-269`），
  但该站**实测常整站 503**（`58` 注释）
- 更要命的是两源按 `name.lowercased()` 去重合并（`~92-108`），**下厨房结果排在前**，
  OFF 的同名条目录入时被那个「空热量」条目挤掉
- 兜底 `PickedFood.init(remote:)` 调 `FoodLibrary.bestMatch`，匹配不到就保持 0

**改法方向**：① 换或补一个真给营养数据的源；② 结果行明确标「无营养数据」，并允许用户自己填；
③ 用本地库 `bestMatch` 做热量估算兜底。

### 1.5 联网商品不能编辑

**根因（已核实）**：`Features/Food/FoodPickerSheet.swift` 的 `remoteSection`（`240-292`）
结果行就是个 `Button`（`272-284`），点击 `273-275` 直接 `onPick(...)` + `dismiss()`——
**选择器里没有任何编辑 UI**。接收方 `AddFoodSheet`（`100-104`）只接 `picked` 和 `grams`，
用户能改的只有份量 TextField 与「半份/一份/两份」按钮（`~145-165`，只驱动克数）。
`PickedFood` 的 `kcalPer100` 等（`init(remote:)`，`~35-48`）**没有绑定任何输入控件**，
`AddFoodSheet` 只做只读折算（`~45-48`）。所以一旦兜底估热为 0，用户只能改克数或改手填。

### 1.6 本地库东西太少，炒米粉都搜不到

**现状（已核实）**：本地库共 **454 条**——`FoodLibrary.swift` 107 + `FoodExtraDaily.swift` 149 +
`FoodExtraDaily2.swift` 150 + `FoodExtraHotpot.swift` 30 + `FoodExtraCafe.swift` 18。
分类分布：家常菜 69、主食 59、快餐 49、零食 36、肉蛋 35、蔬菜 33、火锅 33、水果 28、
咖啡奶茶 24、汤粥 20、饮品 17、蛋奶 16、调味 15、豆类 10、坚果 10。

- **「炒米粉」0 命中**（有炒河粉、干炒牛河、桂林米粉、米线，就是没炒米粉）
- 另有 **10 组同名不同 id 的重复**：千张、午餐肉、娃娃菜、拿铁、沙拉酱、紫菜蛋花汤、
  肥牛卷、金针菇、韭菜、黄焖鸡米饭
- 131 个常见菜名关键词里，只有「炒米粉」是完全缺失

**改法方向**：① 补齐缺的常见家常菜/主食；② 清理重复条目；③ 一并提升搜索匹配（模糊匹配）能力。

### 1.7 联网条目的来源标记缺失

`Data/Store.swift:141-170` 的 `addFood` 固定写 `source = "manual"`、`externalID = nil`（`168-169`），
**联网条目和本地条目在 source 上完全不可区分**，只能靠 `foodID`（`xcf-<菜谱ID>` / OFF 条码）
和 `note = "联网条目"` 认。要做「按来源筛选/统计」得先补这个。

---

## 2. 食品库不显示图片（已定位到一行）

**用户 2026-10-10 确认：「视频库」就是食品库**，指本地食物库列表没有配图。

**根因**：`Domain/FoodLibrary.swift:19` 已经算好了 `var imageURL: String? { FoodImages.url(for: id) }`，
`PickedFood.init(item:)` 也已经写了 `imageURL = item.imageURL`；唯独
`Features/Food/FoodPickerSheet.swift:200` 本地库那一行写死了 `imageURL: nil`，把图地址丢了。

**改法**：`imageURL: nil` → `imageURL: item.imageURL`（一行）。

**更正**：早前我说「今日清单一张图都没有」是**错的**——`TodayView.swift:357` 的 `foodRow` 里有
`FoodThumb`，今日清单是有缩略图的；没图的只有本地库列表那一处。

---

## 3. 通知：不开 App 能做到哪一步

**现状**：`Support/Reminders.swift` 用 `UNCalendarNotificationTrigger(repeats: true)`（`35-38`），
系统级调度，**App 没开、被杀掉都照弹**。通知 identifier = `mealtemplate-<模板UUID>`（`61-63`），
正文「该记<餐次>了 / 「模板名」可以直接入账，约 X 千卡」（`28-33`）——但**没有 `content.userInfo`**，
加上没有代理，这个 identifier 谁也没消费。

**边界要说清楚**：

- 通知**弹出**：能，不依赖 App 运行 ✅
- 到点**自动写入记录**：做不到保证 ❌ iOS 不允许 App 未运行时随意跑代码
- 通知负责到点叫你，入账负责你打开时补上——两件事

**要补的洞**：① 点通知落「今日」页并弹确认（见 1.1）；② `Reminders.sync` 只在保存模板时调用，
用户拒过权限后再去系统设置里打开，不会重排提醒 → 冷启动补一次 re-sync；
③ 可选 `BGAppRefreshTask` 兜底（不保证准时）。

---

## 4. 迭代进度盘点（2026-10-10 只读核对）

| 期次 | 内容 | 状态 |
|---|---|---|
| 第 1 迭代 | 记体重 + 记爬山 + 趋势图、三 Tab 骨架 | 已交付 v0.1.0 |
| 第 2 迭代 | 首启档案引导、卡路里账本、吃喝与运动、健康体重导入 | 已交付 v0.2.0 |
| 第 3 迭代（当前） | 三 Tab 重构、首页统计做细、食物库 454 条、联网搜食物、套餐一键加与到点自动填 | 代码已全部写完（v0.3.0～0.3.2），尾巴见第 1、2、3 节 |
| 第 4 迭代 | 照片叠加对比、目标与里程碑、小组件、导出与备份 | **一寸没动** |

**第 4 迭代未开工的证据**：

- `Photo` / `Goal` / `Milestone` 在 `SummitScale/Sources/Data/` 里 grep 零命中；
  README 数据模型表仍标「占位，后续迭代使用」
- `project.yml` 里没有 widget / extension target
- 源码里搜 `Export` / `导出` / `备份` 零命中

---

## 5. 「加功能」清单（等用户继续给）

- 候选池（来自第 4 迭代原计划）：照片叠加对比、目标与里程碑、小组件、导出与备份。

---

## 6. v0.3.3（2026-10-11）五条问题的修复记录

用户原话：通知点进来直接入账得给个确认；套餐进来的条目该按套餐显示；
联网查的热量基本是 0 还不能编辑；本地库太少（搜「炒米粉」都没有）；接口全是 0 也不行。
按「优先找更好的接口」的要求先做了数据源调研，再逐条改。

| # | 问题 | 改法 | 落地位置 |
|---|---|---|---|
| 1 | 通知/自动补录不问自记 | 拆成「只算不写」+「写」两步，中间弹 `confirmationDialog`（记进今天 / 今天不用）；「今天不用」也落标记，避免同一天反复弹；通知带 `userInfo`，冷启动补 `resyncAll` | `Store+Template.swift`、`RootTabView.swift`、`Reminders.swift` |
| 2 | 套餐条目一条条平铺 | 自动补录与手动一键加统一写 `externalID = autoFillKey(...)`，今日页按这个键分桶折叠成一行、可展开 | `Store+Template.swift`、`TodayView.swift` |
| 3 | 联网条目热量恒为 0 | 下厨房没有营养表，改成用本地库同名条目补值并显示「按本地「X」估」；补到营养的排前面；Open Food Facts 中国站长期 503，改成先试中国站再落世界站 | `FoodSearchService.swift` |
| 4 | 联网条目不可编辑 | 记一笔页新增「每 100 g 营养」四个输入框，改完连带份量折算；取不到值时留空让用户填 | `AddFoodSheet.swift` |
| 5 | 本地库太少 | 454 → 2009 条：新增中式成菜表（炒米粉、螺蛳粉、肠粉、烧鹅等）+《中国食物成分表》数据集 1503 条；顺手清掉 10 组同名重复、修掉本地列表写死的 `imageURL: nil` | `FoodExtraCooked.swift`、`FoodExtraCFCT.swift`、`FoodLibrary.swift`、`FoodPickerSheet.swift` |

**顺带修的**：`Store.addFood` 原来一律写 `source = "manual"`，联网/套餐来源全丢 —— 新增
`Domain/FoodSource.swift`，入账时记真实来源。

**数据来源与口径**：成分表数据集取自 GitHub `Sanotsu/china-food-composition-data`，
只保留热量/蛋白/碳水/脂肪四项齐全的 1503 条，非数字值（`—` `Tr` `…`）整条丢弃不补 0。
转换统计见 `/workspace/tmp/cfct_report.md`。该数据集只有食材没有成菜，「炒米粉」这类靠手写表补。

**验证**：`tools/verify_food.py`、`tools/verify_autofill.py`、`tools/verify_food2.py` 本地退出码 0；
GitHub Actions `6d5c7dd3` 编译通过，产出 `SummitScale-0.3.3-build6-unsigned.ipa`。
**未做真机验证** —— 需用户安装后确认通知确认框、套餐折叠、联网补值、营养编辑四处。

**待观察**：`FoodExtraCFCT.swift` 里 8 条记录的热量与 4/4/9 公式对不上（膳食纤维计入热量但
不计入碳水），已有注释说明并从 CI 门槛里豁免，只在脚本输出里提示。
