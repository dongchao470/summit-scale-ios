"""校验配图索引。

0.3.4 build 7 点「饮食库」必崩，栈是
FoodItem.imageURL.getter -> one-time initialization function for map -> dictionaryLiteral，
根因是 FoodImages.map 那个 400 多项的字典字面量在标准库的 dictionaryLiteral 里 trap
（编译期不报错，运行期直接 EXC_BREAKPOINT）。0.3.5 build 8 换成 Set 字面量后照崩，
所以 0.3.6 改成「字符串常量 + 运行期切分」，彻底不碰字面量构造那条路径。

这个脚本守着三件事：
1. 配图索引不许再写成字典/集合字面量（第一条检查）；
2. id 唯一，且每个 id 都有对应的打包资源，少一个在真机上就是静默空白；
3. 顺手报一下覆盖率，别再说错「多少条有图」。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "SummitScale" / "Sources" / "Domain"
IMAGES = SRC / "FoodImages.swift"
ASSETS = ROOT / "SummitScale" / "Resources" / "Assets.xcassets" / "FoodImages"

LIBRARY_FILES = [
    "FoodLibrary.swift",
    "FoodExtraDaily.swift",
    "FoodExtraDaily2.swift",
    "FoodExtraHotpot.swift",
    "FoodExtraCafe.swift",
    "FoodExtraCooked.swift",
    "FoodExtraCFCT.swift",
]

ROW = re.compile(r"^\s*([A-Za-z0-9_]+)\|([^|]+)\|([^|]+)\|")
IDLIST = re.compile(
    r"private\s+static\s+let\s+idList\s*=\s*\"\"\"\n(.*?)\n\s*\"\"\"", re.S
)
# 字典字面量的行，形如 "key": "value",
LITERAL_ROW = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', re.M)


def main():
    problems = []
    text = IMAGES.read_text(encoding="utf-8")

    # 1. 不许再用字面量构造
    stale = LITERAL_ROW.findall(text)
    if stale:
        problems.append(
            f"配图索引又写成字面量了（{len(stale)} 行，例如 {stale[:3]}）。"
            "大块字面量会在真机上 trap，必须留在 idList 字符串里。"
        )

    # 2. 解析 idList
    m = IDLIST.search(text)
    if not m:
        problems.append("没能从 FoodImages.swift 解析出 idList，格式变了？")
        ids = []
    else:
        ids = m.group(1).split()
    idset = set(ids)

    seen = {}
    for index, key in enumerate(ids):
        if key in seen:
            problems.append(f'配图 id 重复："{key}"（第 {seen[key] + 1} 次与第 {index + 1} 次）')
        seen.setdefault(key, index)

    # 3. id 与打包资源一一对应
    if not ASSETS.is_dir():
        problems.append(f"配图资源目录不存在：{ASSETS}")
    else:
        missing = []
        for key in sorted(idset):
            imageset = ASSETS / ("food_" + key + ".imageset")
            jpg = imageset / (key + ".jpg")
            if not imageset.is_dir() or not jpg.is_file():
                missing.append(key)
        if missing:
            problems.append(
                f"{len(missing)} 个 id 缺少打包资源，例如：{missing[:5]}"
            )
        else:
            on_disk = {p.name[len("food_"):-len(".imageset")]
                       for p in ASSETS.glob("food_*.imageset")}
            extra = sorted(on_disk - idset)
            if extra:
                problems.append(f"{len(extra)} 个 imageset 没有对应 id，例如：{extra[:5]}")

    # 4. 全库条目与覆盖率
    items = []
    for name in LIBRARY_FILES:
        path = SRC / name
        if not path.exists():
            problems.append(f"缺少食物库文件：{name}")
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            row = ROW.match(line)
            if row:
                items.append((row.group(1), row.group(2).strip(), name))

    by_id = [i for i in items if i[0] in idset]
    dangling = sorted(idset - {i[0] for i in items})

    print(f"配图 id: {len(ids)}（唯一 {len(idset)}）")
    print(f"打包资源: {ASSETS}")
    print(f"食物库条目: {len(items)}")
    print(f"按 id 命中的条目: {len(by_id)}")
    if items:
        print(f"覆盖率: {len(by_id) / len(items) * 100:.1f}%")

    if dangling:
        # 只提示：有些图挂在历史 id 上，删条目时忘了摘图，不影响运行。
        print(f"\n注意：{len(dangling)} 个配图 id 在库里找不到对应条目")
        for key in dangling[:10]:
            print("  " + key)
        if len(dangling) > 10:
            print(f"  ...还有 {len(dangling) - 10} 个")

    print(f"\n=== 问题 {len(problems)} 条 ===")
    for problem in problems[:20]:
        print("  " + problem)

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
