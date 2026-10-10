#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为「山与秤」本地食物库抓配图，生成 FoodImages.swift。

流程：
1. 从 Domain 目录的 4 个 Swift 数据文件里按竖线格式提取食物条目（id / 名称）；
2. 逐条去下厨房搜索页抓候选菜谱卡片（菜谱 ID + 菜名 + data-src 图片地址，按页面顺序）；
3. 只接受菜名包含食物名的候选，取最靠前的一个；一个都不匹配就跳过（宁缺勿错图）；
4. 图片地址换成 320x320 裁剪，只保留下厨房图床域名；
5. 写出 FoodImages.swift 与匹配报告。

可复现执行：python3 /workspace/tools/fetch_food_images.py
重复执行会复用 /tmp/food_image_cache.json 里已抓到的结果（临时缓存，不是交付物）。
"""

import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15"
DOMAIN_DIR = "/workspace/summit-scale-ios/SummitScale/Sources/Domain/"
SOURCE_FILES = [
    "FoodLibrary.swift",
    "FoodExtraDaily.swift",
    "FoodExtraDaily2.swift",
    "FoodExtraHotpot.swift",
    "FoodExtraCafe.swift",
]
SWIFT_OUT = os.path.join(DOMAIN_DIR, "FoodImages.swift")
REPORT_OUT = "/workspace/tools/food_image_match_report.txt"
CACHE_PATH = "/tmp/food_image_cache.json"

SEARCH_URL = "https://www.xiachufang.com/search/?keyword={}"
SLEEP_RANGE = (0.3, 0.5)   # 每次请求之间的间隔，别给人家服务器压力
TIMEOUT = 20               # 单次请求超时秒数
RETRY = 1                  # 失败重试次数
IMG_HOSTS = ("i1.chuimg.com", "i2.chuimg.com")   # 下厨房七牛云图床

ID_RE = re.compile(r"^[A-Za-z0-9_]+$")
CARD_SPLIT_RE = re.compile(r'<div class="recipe recipe-')
RECIPE_ID_RE = re.compile(r'href="/recipe/(\d+)/"')
IMG_RE = re.compile(r'data-src="([^"]+)"')
NAME_RE = re.compile(r'<p class="name">\s*<a[^>]*>(.*?)</a>', re.S)
TAG_RE = re.compile(r"<[^>]+>")
SAFE_URL_RE = re.compile(r"https://[A-Za-z0-9:/?&=._%\-]+$")


def extract_entries():
    """提取全部食物条目，返回 [(id, 名称, 来源文件, 行号)]，按 id 去重保留第一次出现。"""
    entries = []
    seen = set()
    for filename in SOURCE_FILES:
        path = os.path.join(DOMAIN_DIR, filename)
        if not os.path.exists(path):
            print("警告：找不到数据文件 %s" % path)
            continue
        with open(path, encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, 1):
                text = line.strip()
                if "|" not in text:
                    continue
                parts = [x.strip() for x in text.split("|")]
                if len(parts) != 9:
                    continue
                food_id, name = parts[0], parts[1]
                if not ID_RE.match(food_id) or not name:
                    continue
                try:
                    for value in parts[3:8]:
                        float(value)
                except ValueError:
                    continue
                if food_id in seen:
                    print("警告：id 重复，跳过 %s（%s:%d）" % (food_id, filename, lineno))
                    continue
                seen.add(food_id)
                entries.append((food_id, name, filename, lineno))
    return entries


def query_name(name):
    """搜索词：去掉括号里的修饰，比如「米饭（蒸）」搜「米饭」。"""
    text = re.split(r"[（(]", name.strip())[0].strip()
    return text or name.strip()


def fetch_html(keyword):
    """抓搜索页，失败重试 RETRY 次。返回 (html, 错误说明)。"""
    url = SEARCH_URL.format(urllib.parse.quote(keyword))
    last_error = None
    for attempt in range(RETRY + 1):
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": UA, "Accept-Language": "zh-CN,zh;q=0.9"},
            )
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                if response.status != 200:
                    raise urllib.error.HTTPError(url, response.status, "非 200", response.headers, None)
                return response.read().decode("utf-8", "replace"), None
        except Exception as error:   # 网络抖动、超时、5xx 都算一次失败
            last_error = "%s %s" % (type(error).__name__, error)
            if attempt < RETRY:
                time.sleep(random.uniform(*SLEEP_RANGE))
    return None, last_error


def parse_cards(html):
    """解析菜谱卡片，按页面出现顺序返回 [{id,title,img}]。"""
    cards = []
    for chunk in CARD_SPLIT_RE.split(html)[1:]:
        recipe_id = RECIPE_ID_RE.search(chunk)
        image = IMG_RE.search(chunk)
        name = NAME_RE.search(chunk)
        if not (recipe_id and image and name):
            continue
        title = re.sub(r"\s+", " ", TAG_RE.sub("", name.group(1))).strip()
        cards.append({"id": recipe_id.group(1), "title": title, "img": image.group(1)})
    return cards


def polish_image(raw):
    """整理图片地址：换 320x320 裁剪，只留下厨房图床，返回 None 表示不可用。"""
    url = (raw or "").strip().replace("&amp;", "&")
    if url.startswith("http://"):
        url = "https://" + url[len("http://"):]
    match = re.match(r"https://([^/]+)/", url)
    if not match or match.group(1) not in IMG_HOSTS:
        return None
    url = url.replace("imageView2/1/w/215/h/136", "imageView2/1/w/320/h/320")
    if not SAFE_URL_RE.match(url):
        return None
    return url


def match_one(name, cards):
    """第一个「菜名包含食物名」的候选。返回 (结果字典, 失败原因)。"""
    keyword = query_name(name)
    for card in cards:
        if keyword and keyword in card["title"]:
            url = polish_image(card["img"])
            if url:
                return {"recipe_id": card["id"], "recipe_title": card["title"], "url": url}, None
    return None, "没有菜名包含「%s」的候选菜谱" % keyword


def load_cache():
    if os.path.exists(CACHE_PATH):
        try:
            with open(CACHE_PATH, encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {}
    return {}


def save_cache(cache):
    with open(CACHE_PATH, "w", encoding="utf-8") as handle:
        json.dump(cache, handle, ensure_ascii=False, indent=1)


def crawl(entries):
    """按搜索词抓取，同名的食物只发一次请求。返回 {搜索词: 结果}。"""
    cache = load_cache()
    keywords = []
    for _, name, _, _ in entries:
        keyword = query_name(name)
        if keyword not in keywords:
            keywords.append(keyword)
    total = len(keywords)
    for index, keyword in enumerate(keywords, 1):
        if keyword in cache:
            print("[%d/%d] 跳过缓存 %s" % (index, total, keyword))
            continue
        html, error = fetch_html(keyword)
        if html is None:
            cache[keyword] = {"error": error}
            print("[%d/%d] %s 抓取失败：%s" % (index, total, keyword, error))
        else:
            cards = parse_cards(html)
            result, reason = match_one(keyword, cards)
            if result:
                cache[keyword] = result
                print("[%d/%d] %s -> %s" % (index, total, keyword, result["recipe_title"][:24]))
            else:
                cache[keyword] = {"error": reason, "cards": len(cards)}
                print("[%d/%d] %s 未命中（候选 %d 个）" % (index, total, keyword, len(cards)))
        save_cache(cache)
        time.sleep(random.uniform(*SLEEP_RANGE))
    return cache


def build_mapping(entries, cache):
    """组装 id -> 图片地址，同时收集命中和未命中的明细。"""
    mapping = {}
    hits = []
    misses = []
    for food_id, name, filename, lineno in entries:
        keyword = query_name(name)
        record = cache.get(keyword) or {"error": "本次未抓取（缓存缺失）"}
        if "url" in record:
            mapping[food_id] = record["url"]
            hits.append((food_id, name, keyword, record))
        else:
            misses.append((food_id, name, keyword, record.get("error", "未知原因"), filename, lineno))
    return mapping, hits, misses


def write_swift(mapping):
    lines = [
        "import Foundation",
        "",
        "/// 本地食物库的配图。数据来自下厨房搜索页，按食物名匹配，匹配不到就不配图，",
        "/// 列表里会退回分类图标兜底。",
        "///",
        "/// 链接是七牛云图床，走网络加载；断网时上层会自动退回图标，不会空白。",
        "enum FoodImages {",
        "    /// 食物 id -> 图片地址。",
        "    private static let map: [String: String] = [",
    ]
    for food_id in sorted(mapping):
        lines.append('        "%s": "%s",' % (food_id, mapping[food_id]))
    lines += [
        "    ]",
        "",
        "    static func url(for id: String) -> String? {",
        "        map[id]",
        "    }",
        "}",
        "",
    ]
    content = "\n".join(lines)
    with open(SWIFT_OUT, "w", encoding="utf-8") as handle:
        handle.write(content)
    return content


def write_report(entries, cache, hits, misses, content):
    total = len(entries)
    searched = len(cache)
    hit_count = len(hits)
    rate = (hit_count * 100.0 / total) if total else 0.0
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    lines = []
    lines.append("下厨房配图匹配报告")
    lines.append("生成时间：%s" % stamp)
    lines.append("")
    lines.append("食物条目总数：%d（唯一 id）" % total)
    lines.append("实际搜索食物名数：%d（同名食物只搜一次）" % searched)
    lines.append("配图命中条数：%d" % hit_count)
    lines.append("命中率：%.1f%%" % rate)
    lines.append("未配图条数：%d" % len(misses))
    lines.append("FoodImages.swift 字节数：%d" % len(content.encode("utf-8")))
    lines.append("map 条目数：%d" % hit_count)
    lines.append("")
    lines.append("匹配规则：搜索词取食物名去掉括号修饰（如「米饭（蒸）」搜「米饭」）；")
    lines.append("只接受菜名包含搜索词的候选，取页面顺序最靠前的一个；图片换 320x320 裁剪，只留 chuimg.com 图床。")
    lines.append("")
    lines.append("== 命中明细 ==")
    lines.append("食物id | 食物名 | 搜索词 | 菜谱ID | 菜谱名 | 图片地址")
    for food_id, name, keyword, record in hits:
        lines.append("%s | %s | %s | %s | %s | %s" % (
            food_id, name, keyword, record["recipe_id"], record["recipe_title"], record["url"]))
    lines.append("")
    lines.append("== 未配图明细（留空，上层退回分类图标） ==")
    lines.append("食物id | 食物名 | 搜索词 | 原因")
    for food_id, name, keyword, reason, filename, lineno in misses:
        lines.append("%s | %s | %s | %s" % (food_id, name, keyword, reason))
    lines.append("")
    lines.append("== 未配图原因汇总 ==")
    counter = {}
    for _, _, _, reason, _, _ in misses:
        counter[reason] = counter.get(reason, 0) + 1
    for reason in sorted(counter, key=lambda k: -counter[k]):
        lines.append("%d 条：%s" % (counter[reason], reason))
    lines.append("")
    with open(REPORT_OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def main():
    entries = extract_entries()
    print("提取到食物条目 %d 条" % len(entries))
    cache = crawl(entries)
    mapping, hits, misses = build_mapping(entries, cache)
    content = write_swift(mapping)
    write_report(entries, cache, hits, misses, content)
    print("")
    print("条目总数 %d，命中 %d，命中率 %.1f%%，Swift 字节数 %d" % (
        len(entries), len(hits), len(hits) * 100.0 / max(len(entries), 1), len(content.encode("utf-8"))))
    print("输出：%s" % SWIFT_OUT)
    print("报告：%s" % REPORT_OUT)


if __name__ == "__main__":
    main()
