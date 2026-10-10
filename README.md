# 山与秤 / Summit & Scale

体重与爬山的私人记录 App。三 Tab：**今日 / 记录 / 回顾**。

- 设备目标：iOS 16.0+（当前测试机 iOS 16.4.1，roothide + TrollStore）
- 数据层：Core Data（`NSManagedObjectModel` 程序化构建，无 `.xcdatamodeld`）
- 图表：Swift Charts
- 工程生成：XcodeGen（`project.yml`）
- 构建：GitHub Actions `macos-15`，无签名产出 IPA，由用户在设备侧用 TrollStore 签名安装

## 目录

```
project.yml                       XcodeGen 工程描述（唯一工程真源）
SummitScale/
  Sources/
    App/                          App 入口与 Tab 骨架
    Data/                         Core Data 栈、实体、写入出口
    Features/Today/               今日页 + 记体重
    Features/Log/                 记录页 + 记爬山
    Features/Review/              回顾页（曲线 / 周柱状 / 统计）
    Support/                      格式化与卡片组件
  Resources/                      Info.plist（生成）、Assets.xcassets
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

## 数据模型（第 1 迭代）

| 实体 | 关键字段 |
|---|---|
| `WeightEntry` | `id` `date`(索引) `kilograms` `note` `createdAt` `source` `externalID` |
| `Hike` | `id` `date`(索引) `title` `distanceKilometers` `elevationGainMeters` `durationMinutes` `note` `createdAt` `source` `externalID` |

`source` / `externalID` 先留着占位，第 2 迭代接 HealthKit 与导入时不用改模型。

## 迭代计划

1. **第 1 迭代（当前）**：记体重 + 记爬山 + 趋势图，三 Tab 骨架。
2. 第 2 迭代：HealthKit 读取、照片叠加对比、目标与里程碑。
3. 第 3 迭代：小组件、导出与备份。
