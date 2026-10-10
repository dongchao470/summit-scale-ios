#!/usr/bin/env python3
"""校验食物库数据。

解析 SummitScale/Sources/Domain 下四个 Swift 文件里的多行字符串，
逐行检查格式（9 段）、id 唯一性、数值可解析、以及热量与三大营养素是否自洽。
纯标准库，CI 与本地都能跑。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "SummitScale" / "Sources" / "Domain"
FILES = [
    "FoodLibrary.swift",
    "FoodExtraDaily.swift",
    "FoodExtraHotpot.swift",
    "FoodExtraCafe.swift",
]

CATEGORY_ORDER = [
    "主食", "家常菜", "肉蛋", "蛋奶", "豆类", "蔬菜", "水果", "坚果",
    "汤粥", "火锅", "快餐", "零食", "咖啡奶茶", "饮品", "调味",
]


def extract_block(path: Path):
    text = path.read_text(encoding="utf-8")
    match = re.search(r'"""\n(.*?)\n\s*"""', text, re.S)
    if not match:
        return None
    return match.group(1).split("\n")


def main() -> int:
    rows = []
    problems = []
    per_file = {}

    for name in FILES:
        path = SRC / name
        if not path.exists():
            problems.append(f"{name}: 文件不存在")
            continue
        lines = extract_block(path)
        if lines is None:
            problems.append(f"{name}: 没找到多行字符串")
            continue

        accepted = 0
        for index, line in enumerate(lines, 1):
            raw = line.strip()
            if not raw:
                continue
            parts = raw.split("|")
            if len(parts) != 9:
                problems.append(f"{name}:{index} 段数 {len(parts)}，应为 9 → {raw[:60]}")
                continue
            try:
                kcal = float(parts[3])
                protein = float(parts[4])
                carbs = float(parts[5])
                fat = float(parts[6])
                grams = float(parts[7])
            except ValueError:
                problems.append(f"{name}:{index} 数值解析失败 → {raw[:60]}")
                continue
            if grams <= 0:
                problems.append(f"{name}:{index} 一份克数为 0 → {raw[:60]}")
            rows.append({
                "file": name,
                "line": index,
                "id": parts[0],
                "name": parts[1],
                "category": parts[2],
                "kcal": kcal,
                "protein": protein,
                "carbs": carbs,
                "fat": fat,
                "grams": grams,
                "label": parts[8],
            })
            accepted += 1
        per_file[name] = accepted

    # id 唯一
    seen = {}
    for row in rows:
        if row["id"] in seen:
            problems.append(
                f"id 重复: {row['id']}（{seen[row['id']]} 与 {row['file']}:{row['line']}）"
            )
        seen[row["id"]] = f"{row['file']}:{row['line']}"

    # 热量自洽：kcal ≈ 碳水*4 + 蛋白*4 + 脂肪*9
    # 蔬菜类含膳食纤维、酒类热量主要来自酒精，本来就不走 4/4/9，单独豁免。
    EXEMPT_IDS = {"beer", "wine_red", "baijiu"}
    EXEMPT_CATEGORIES = {"蔬菜"}

    for row in rows:
        if row["kcal"] < 20:
            continue
        if row["id"] in EXEMPT_IDS or row["category"] in EXEMPT_CATEGORIES:
            continue
        computed = row["carbs"] * 4 + row["protein"] * 4 + row["fat"] * 9
        if computed <= 0:
            problems.append(f"热量为 0 但写明 {row['kcal']} → {row['id']}")
            continue
        drift = abs(computed - row["kcal"]) / row["kcal"]
        if drift > 0.20:
            problems.append(
                f"营养对不上热量: {row['id']} 标 {row['kcal']:.0f}，"
                f"按 4/4/9 算是 {computed:.0f}（差 {drift * 100:.0f}%）"
            )

    categories = {}
    for row in rows:
        categories.setdefault(row["category"], 0)
        categories[row["category"]] += 1

    print("=== 各文件条数 ===")
    for name, count in per_file.items():
        print(f"  {name}: {count}")
    print(f"  合计: {len(rows)}")

    print("\n=== 分类分布 ===")
    for category in CATEGORY_ORDER + sorted(set(categories) - set(CATEGORY_ORDER)):
        if category in categories:
            print(f"  {category}: {categories[category]}")

    unknown = [c for c in categories if c not in CATEGORY_ORDER]
    if unknown:
        print(f"\n注意：分类顺序表里没有登记 {unknown}")

    print(f"\n=== 问题 {len(problems)} 条 ===")
    for problem in problems[:40]:
        print("  " + problem)
    if len(problems) > 40:
        print(f"  ...还有 {len(problems) - 40} 条")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
