"""校验配图表。

0.3.3 build 6 点「饮食库」必崩，崩溃栈是
FoodItem.imageURL.getter -> one-time initialization function for map -> dictionaryLiteral，
原因是 FoodImages.map 这个字典字面量里有两个 "cf_latte"，Swift 的字典字面量遇到重复 key
是运行时 trap（编译期不报错）。而这行代码之前从没被执行过，所以一直没露头。

这个脚本就是那条漏掉的闸：查 key 唯一、查 URL 形态、顺便报一下配图覆盖率，
在编译之前跑，不许再有第二次。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "SummitScale" / "Sources" / "Domain"
IMAGES = SRC / "FoodImages.swift"
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


def main():
    problems = []
    text = IMAGES.read_text(encoding="utf-8")

    pairs = re.findall(r'^\s*"([^"]+)"\s*:\s*"([^"]*)"\s*,?\s*$', text, re.M)
    if not pairs:
        problems.append("FoodImages.swift 里没解析到任何配图条目，格式变了？")

    keys = [k for k, _ in pairs]
    seen = {}
    for index, key in enumerate(keys):
        if key in seen:
            problems.append(f'配图 key 重复："{key}"（第 {seen[key] + 1} 次与第 {index + 1} 次）')
        seen.setdefault(key, index)

    for key, url in pairs:
        if not url.startswith("https://"):
            problems.append(f'配图 URL 不是 https：{key} -> {url[:60]}')

    # 全库条目
    items = []
    for name in LIBRARY_FILES:
        path = SRC / name
        if not path.exists():
            problems.append(f"缺少食物库文件：{name}")
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            m = ROW.match(line)
            if m:
                items.append((m.group(1), m.group(2).strip(), name))

    keyset = set(keys)
    by_id = [i for i in items if i[0] in keyset]
    dangling = sorted(keyset - {i[0] for i in items})

    # 0.3.4 起配图改为打包进 Assets，id 和资源名必须一一对上，
    # 少一个在真机上就是静默空白，不会报错，所以这里当硬错误。
    asset_root = ROOT / "SummitScale" / "Resources" / "Assets.xcassets" / "FoodImages"
    missing_assets = []
    for key in sorted(keyset):
        imageset = asset_root / ("food_" + key + ".imageset")
        jpg = imageset / (key + ".jpg")
        if not imageset.is_dir() or not jpg.is_file():
            missing_assets.append(key)
    if missing_assets:
        problems.append(f"{len(missing_assets)} 个配图缺少打包资源，例如：{missing_assets[:5]}")
    else:
        print(f"打包资源齐备: {asset_root}")

    print(f"配图条目: {len(pairs)}（唯一 {len(keyset)}）")
    print(f"食物库条目: {len(items)}")
    print(f"按 id 命中的条目: {len(by_id)}")
    print(f"覆盖率: {len(by_id) / len(items) * 100:.1f}%")

    if dangling:
        # 只提示：有些图挂在历史 id 上，删条目时忘了摘图，不影响运行。
        print(f"\n注意：{len(dangling)} 个配图 key 在库里找不到对应条目")
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
