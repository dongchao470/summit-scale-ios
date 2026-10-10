# 山与秤 / Summit & Scale

体重、饮食与运动的私人记录 App。三 Tab：**今日 / 记录 / 回顾**。

- 设备目标：iOS 16.0+（当前测试机 iOS 16.4.1，roothide + TrollStore）
- 数据层：Core Data（`NSManagedObjectModel` 程序化构建，无 `.xcdatamodeld`）
- 图表：Swift Charts
- 工程生成：XcodeGen（`project.yml`）
- 构建：GitHub Actions `macos-15`，无签名产出 IPA，由用户在设备侧用 TrollStore 签名安装

## v0.2 功能

- **首次启动引导**：问名字、性别、出生年份、身高、当前体重、目标体重、日常活动量、目标方向；用 Mifflin-St Jeor 公式算基础代谢（BMR），乘活动系数得每日总消耗（TDEE）。
- **卡路里账本**：今日页顶部圆环把「已摄入 − 运动消耗」与当日预算对比，配热量缺口、基础代谢、总消耗三块指标卡；超出预算时圆环转橙。
- **吃喝记录**：内置按类别分组的中式食物库（每 100 g / 每份的热量与三大营养素），支持按克数或份数换算，也能手填热量。
- **运动记录**：爬山、快走、跑步、骑行等按 MET 公式估算消耗，可手动覆盖；v0.1 的爬山记录在启动时自动迁移为运动记录。
- **健康导入**：读取「健康」App 的体重记录（最近 90 天），按 `externalID` 去重后写入。未授权或系统不可用时给出明确提示，不阻塞手动记录。
- **回顾页**：体重曲线、每日摄入柱状图、区间汇总（体重变化 / 平均摄入 / 运动消耗合计）。

## 目录

```
project.yml                       XcodeGen 工程描述（唯一工程真源）
SummitScale/
  Sources/
    App/                          App 入口、首启分流与 Tab 骨架
    Data/                         Core Data 栈、实体、写入出口
    Domain/                       热量公式、食物库、账本模型
    Features/Activity/            记运动
    Features/Food/                记吃喝
    Features/Log/                 记录页 + 记体重
    Features/Onboarding/          首启档案引导
    Features/Profile/             档案编辑
    Features/Review/              回顾页（曲线 / 柱状 / 汇总）
    Features/Today/               今日页 + 热量圆环
    Health/                       HealthKit 读取与导入
    Support/                      格式化与卡片组件
  Resources/                      Info.plist、Assets.xcassets
  SummitScale.entitlements        HealthKit 权限声明
scripts/make_icon.py              图标生成（纯标准库）
.github/workflows/build-ipa.yml   云编译流水线
```

## 本地/云端构建

```bash
xcodegen generate --spec project.yml
xcodebuild -project SummitScale.xcodeproj -scheme SummitScale \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" clean build
```

推送到 `main` 触发 Actions，产物为 `SummitScale-ipa` artifact（内含未签名 IPA 与 sha256）。
流水线在打包前用 `ldid -S<entitlements>` 与 `codesign --force --sign - --entitlements` 给可执行文件注入 HealthKit 权限（`continue-on-error`，两条路径都写日志）。

## 数据模型

| 实体 | 关键字段 |
|---|---|
| `WeightEntry` | `id` `date`(索引) `kilograms` `note` `createdAt` `source` `externalID` |
| `FoodEntry` | `id` `date`(索引) `foodID` `name` `grams` `mealValue` `kcal` `proteinGrams` `fatGrams` `carbGrams` `note` `createdAt` `source` `externalID` |
| `ActivityEntry` | `id` `date`(索引) `kindValue` `title` `durationMinutes` `distanceKilometers` `elevationGainMeters` `kcal` `note` `createdAt` `source` `externalID` |
| `UserProfile` | `name` `sexValue` `birthDate` `heightCentimeters` `startWeightKilograms` `targetWeightKilograms` `activityValue` `goalValue` `dailyCalorieOverride` `createdAt` `updatedAt` |
| `Hike` | v0.1 遗留，启动时迁移进 `ActivityEntry` |
| `Measurement` / `Photo` / `Goal` / `Milestone` | 占位，后续迭代使用 |

`source` / `externalID` 用于区分手动记录与外部导入（如 HealthKit），并做去重。

## 计算口径

- BMR：Mifflin-St Jeor（男 `10W + 6.25H − 5A + 5`，女 `10W + 6.25H − 5A − 161`）。
- TDEE = BMR × 活动系数（1.2 / 1.375 / 1.55 / 1.725 / 1.9）。
- 每日预算由目标方向调整（减脂 −20%、增重 +15%、维持不变），可在档案里手动覆盖。
- 运动消耗 = MET × 3.5 × 体重(kg) ÷ 200 × 分钟数。
- 所有热量都是估算值，界面里标注了这一点，不构成医疗建议。

## 迭代计划

1. 第 1 迭代：记体重 + 记爬山 + 趋势图，三 Tab 骨架。
2. **第 2 迭代（当前）**：首启档案引导、卡路里账本、吃喝与运动记录、健康体重导入。
3. 第 3 迭代：照片叠加对比、目标与里程碑、小组件、导出与备份。

## 构建踩坑

- `Section("标题") { ... }` 里若含多个 `if` 分支，类型推断会退化到 Table 的 `Section` 重载，报 `generic parameter 'V' could not be inferred`；改写成 `Section(header: Text("标题")) { ... }`，并把条件行抽成独立的 `@ViewBuilder` 属性即可。需要 footer 时必须用 `Section { } header: { } footer: { }`。
- Core Data 的 `NSManagedObject` 子类不自动符合 `Identifiable`，`ForEach(fetchedResults)` 会编译失败；在实体文件里补 `extension X: Identifiable {}`（`id` 已存在）最省事。
- macOS runner 上用 `ldid` 注入 entitlements 必须写成 `ldid -S<文件>`（`-S` 与文件名之间不能有空格），带空格会以 `ldid.cpp(852): _assert(): false` 失败；`codesign --force --sign - --entitlements <plist> <二进制>` 是可靠备选。
- 验证未安装到设备的 IPA：解包 `Payload/*.app`，用 `python3 plistlib` 核对 `Info.plist`，并比对本地 `sha256sum` 与流水线产出的 `.sha256`。
- HealthKit 权限在 TrollStore 侧可能被拒（`healthd` 会校验客户端签名方）；App 已实现未授权时给出提示并降级到手动记录，不会崩溃。
