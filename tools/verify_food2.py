#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验 FoodExtraDaily2.swift：列数、数值、分类白名单、id 唯一性、非法字符。"""

import os
import re
import sys

DOMAIN = "/workspace/summit-scale-ios/SummitScale/Sources/Domain"
NEW_FILE = os.path.join(DOMAIN, "FoodExtraDaily2.swift")
OLD_FILES = [
    "FoodLibrary.swift",
    "FoodExtraDaily.swift",
    "FoodExtraHotpot.swift",
    "FoodExtraCafe.swift",
]

CATEGORIES = [
    "主食", "家常菜", "肉蛋", "蛋奶", "豆类", "蔬菜", "水果", "坚果",
    "汤粥", "火锅", "快餐", "零食", "咖啡奶茶", "饮品", "调味",
]

LINE_RE = re.compile(r"^\s*([a-z0-9_]+)\|")
EMOJI_RE = re.compile(
    "[\U0001F000-\U0001FAFF\u2600-\u27BF\uFE0F\u2B00-\u2BFF]"
)
BAD_SEP_RE = re.compile(r"[\t,;；，、]|::")


def data_lines(path):
    """取出文件里 Raw 字符串块内的数据行（含行号）。"""
    out = []
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    for i, line in enumerate(raw.split("\n"), 1):
        if LINE_RE.match(line):
            out.append((i, line.rstrip("\n")))
    return out


def main():
    errors = {
        "columns": 0,
        "number": 0,
        "duplicate": 0,
        "category": 0,
    }
    detail = []

    # 1) 旧 id 全集
    old_ids = set()
    for name in OLD_FILES:
        p = os.path.join(DOMAIN, name)
        if not os.path.exists(p):
            detail.append("缺少文件: %s" % p)
            continue
        for _ln, text in data_lines(p):
            old_ids.add(text.strip().split("|")[0])

    # 2) 新文件
    new_rows = data_lines(NEW_FILE)
    ids = []
    cat_count = {}
    n_bad_cols = n_bad_num = n_bad_cat = 0
    for ln, text in new_rows:
        cells = text.strip().split("|")
        if len(cells) != 9:
            errors["columns"] += 1
            n_bad_cols += 1
            detail.append("行 %d 列数 %d != 9: %s" % (ln, len(cells), text.strip()))
            continue
        fid, name, cat = cells[0], cells[1], cells[2]
        ids.append(fid)
        if cat not in CATEGORIES:
            errors["category"] += 1
            n_bad_cat += 1
            detail.append("行 %d 分类越界: %s" % (ln, cat))
        cat_count[cat] = cat_count.get(cat, 0) + 1
        if not fid.startswith("d2_"):
            detail.append("行 %d id 前缀异常: %s" % (ln, fid))
        for idx in (3, 4, 5, 6, 7):
            try:
                float(cells[idx])
            except ValueError:
                errors["number"] += 1
                n_bad_num += 1
                detail.append("行 %d 第 %d 列无法解析: %s" % (ln, idx + 1, cells[idx]))
        if EMOJI_RE.search(text):
            detail.append("行 %d 含 emoji: %s" % (ln, text.strip()))
        if BAD_SEP_RE.search(text):
            detail.append("行 %d 含竖线以外的分隔符: %s" % (ln, text.strip()))

    # 3) 重复 id
    seen = {}
    for fid in ids:
        seen[fid] = seen.get(fid, 0) + 1
    dup_inner = sorted([k for k, v in seen.items() if v > 1])
    dup_old = sorted([k for k in seen if k in old_ids])
    errors["duplicate"] = len(dup_inner)
    for k in dup_inner:
        detail.append("内部重复 id: %s x%d" % (k, seen[k]))
    for k in dup_old:
        detail.append("与旧数据重复 id: %s" % k)

    # 4) 空行夹在数据中间
    with open(NEW_FILE, encoding="utf-8") as fh:
        text_all = fh.read()
    body = text_all.split('"""')
    blank_inner = 0
    if len(body) >= 3:
        inner = body[1].split("\n")
        for i, line in enumerate(inner):
            if line.strip() == "" and 0 < i < len(inner) - 1:
                blank_inner += 1
    size = os.path.getsize(NEW_FILE)

    print("=== FoodExtraDaily2.swift 校验结果 ===")
    print("文件: %s" % NEW_FILE)
    print("文件字节数: %d" % size)
    print("旧库 id 数: %d" % len(old_ids))
    print("新增条数: %d" % len(new_rows))
    print("涉及分类数: %d" % len(cat_count))
    print("分类分布:")
    for cat in CATEGORIES:
        if cat in cat_count:
            print("  %s: %d" % (cat, cat_count[cat]))
    print("列数错误: %d 条" % n_bad_cols)
    print("数值解析失败: %d 条" % n_bad_num)
    print("分类越界: %d 条" % n_bad_cat)
    print("id 重复: %d 条（内部 %d / 与旧库 %d）" % (
        len(dup_inner) + len(dup_old), len(dup_inner), len(dup_old)))
    print("字符串块内空行: %d" % blank_inner)
    if detail:
        print("--- 明细 ---")
        for d in detail:
            print(d)
    else:
        print("--- 明细: 无 ---")
    print("--- 抽查 5 条原始行 ---")
    for i in (0, 24, 60, 105, 149):
        if i < len(new_rows):
            print("行 %d: %s" % (new_rows[i][0], new_rows[i][1].strip()))

    ok = (
        len(new_rows) == 150
        and n_bad_cols == 0
        and n_bad_num == 0
        and n_bad_cat == 0
        and len(dup_inner) == 0
        and len(dup_old) == 0
        and blank_inner == 0
        and not detail
    )
    print("总体结论: %s" % ("通过" if ok else "未通过"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
