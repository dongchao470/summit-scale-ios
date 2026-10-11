"""校验配图。

0.3.4 build 7 点「饮食库」必崩，栈是
  FoodItem 的图字段 getter -> 配图表的一次性初始化 -> dictionaryLiteral
  -> EXC_BREAKPOINT / SIGTRAP
0.3.5 build 8 换成 Set 字面量后照崩，而且把 434 个 id 拿去实测（见
tools/repro_dictionary_trap.swift 与 CI 的 Diagnose dictionary literal 步骤），
字典字面量本身并不 trap —— 也就是说根因在别处，只是恰好落在配图表初始化那条路上。

所以 0.3.6 起配图索引不再有名单：FoodImages.assetName(for:) 直接拼资源名，
有没有图交给 UIImage(named:) 回答。没有静态存储，就没有初始化可崩。

这个脚本守着三件事：
1. FoodImages 不许再出现任何 static let / static var（第一条检查，回归守卫）；
2. 每个 imageset 有 jpg 与 Contents.json，且目录名是 food_<id>；
3. 报覆盖率：Assets 里有多少张图、对应多少个食物条目。
"""

import json
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
STATIC_STORAGE = re.compile(r"^\s*(?:private\s+|fileprivate\s+)?static\s+(?:let|var)\s", re.M)


def main():
    problems = []

    # 1. 回归守卫：配图索引里不许再有静态存储
    text = IMAGES.read_text(encoding="utf-8")
    storage = STATIC_STORAGE.findall(text)
    if storage:
        problems.append(
            f"FoodImages 又出现了静态存储（{len(storage)} 处）。"
            "那会带来一次性初始化，而两次真机崩溃就崩在那条路上。"
        )

    # 2. Assets 目录
    if not ASSETS.is_dir():
        problems.append(f"配图资源目录不存在：{ASSETS}")
        return report([], problems)

    imagesets = sorted(ASSETS.glob("food_*.imageset"))
    ids = []
    for imageset in imagesets:
        name = imageset.name
        if not name.startswith("food_") or not name.endswith(".imageset"):
            problems.append(f"资源目录命名不合规：{name}")
            continue
        key = name[len("food_"):-len(".imageset")]
        ids.append(key)

        manifest = imageset / "Contents.json"
        if not manifest.is_file():
            problems.append(f"{name} 缺 Contents.json")
        else:
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
                if not data.get("images"):
                    problems.append(f"{name} 的 Contents.json 里没有 images 项")
            except json.JSONDecodeError as exc:
                problems.append(f"{name} 的 Contents.json 不是合法 JSON：{exc}")

        pictures = [p for p in imageset.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")]
        if not pictures:
            problems.append(f"{name} 里没有图片文件")
        elif not (imageset / (key + ".jpg")).is_file() and not (imageset / (key + ".png")).is_file():
            problems.append(f"{name} 的图片文件名与 id 对不上：{[p.name for p in pictures]}")

    # 3. 食物库条目
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

    idset = set(ids)
    by_id = [i for i in items if i[0] in idset]
    orphans = sorted(idset - {i[0] for i in items})

    if orphans:
        # 只提示：删条目时容易忘记摘图，不影响运行。
        print(f"注意：{len(orphans)} 张图对应的条目已不在库里：{orphans[:8]}")

    return report(ids, problems, items, by_id)


def report(ids, problems, items=None, by_id=None):
    print(f"打包配图: {len(ids)} 张")
    if items is not None:
        print(f"食物库条目: {len(items)}")
        print(f"其中配了图的: {len(by_id)}")
        if items:
            print(f"覆盖率: {len(by_id) / len(items) * 100:.1f}%")
    print(f"\n=== 问题 {len(problems)} 条 ===")
    for problem in problems[:20]:
        print("  " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
