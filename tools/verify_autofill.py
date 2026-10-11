#!/usr/bin/env python3
"""自动补录去重的静态防回归检查。

背景：v0.3.1 出现过「手动记过晚餐 -> 杀掉 App 重开 -> 又被自动补一遍」。
根因是手动入账不写去重标记，而自动补录只认条目里的 externalID，
于是手动记的那些在它眼里等于没记过。

这里把几个关键不变量钉住，改坏了直接非零退出。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "SummitScale" / "Sources" / "Data" / "Store+Template.swift"


def function_body(name, text):
    """按大括号配平粗略取一个函数的函数体。"""
    m = re.search(r"func\s+" + name + r"\b", text)
    if not m:
        return None
    i = text.find("{", m.end())
    if i < 0:
        return None
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    return None


def main():
    if not SRC.exists():
        print("自动补录去重检查：找不到", SRC)
        return 1

    src = SRC.read_text(encoding="utf-8")
    problems = []

    # 1. 手动一键入账也要落标记，否则手动记过的套餐到点仍会被补
    ap = function_body("applyTemplate", src)
    if ap is None:
        problems.append("找不到 applyTemplate")
    elif "markAutoFilled" not in ap:
        problems.append(
            "applyTemplate 没调用 markAutoFilled：手动记过的套餐到点会被重复补一遍"
        )

    # 2. 自动补录写完条目后要落标记
    #    0.3.3 起自动补录拆成两步：pendingAutoFills 只算不写、applyAutoFills 才落库，
    #    中间夹一个「记进今天 / 今天不用」的确认，所以标记落在 applyAutoFills 里。
    raf = function_body("applyAutoFills", src)
    if raf is None:
        problems.append("找不到 applyAutoFills")
    elif "markAutoFilled" not in raf:
        problems.append("applyAutoFills 写入之后没有调用 markAutoFilled")

    # 2b. 只算不写的那一步绝不能碰库，否则确认框就成了摆设
    paf = function_body("pendingAutoFills", src)
    if paf is None:
        problems.append("找不到 pendingAutoFills")
    elif "addFood" in paf or "markAutoFilled" in paf:
        problems.append("pendingAutoFills 里出现了写库调用：弹确认之前就已经记账了")

    # 2c. 用户选「今天不用」也要落标记，否则同一天会反复弹
    saf = function_body("skipAutoFills", src)
    if saf is None:
        problems.append("找不到 skipAutoFills")
    elif "markAutoFilled" not in saf:
        problems.append("skipAutoFills 没落标记：选过「今天不用」还会一次次弹")

    # 3. 去重判断要读持久化标记，不能只看条目（否则删了条目会被重新补回来）
    haf = function_body("hasAutoFilled", src)
    if haf is None:
        problems.append("找不到 hasAutoFilled")
    elif "UserDefaults" not in haf:
        problems.append("hasAutoFilled 没读 UserDefaults 标记：删掉条目后会被重新补回来")

    # 4. 标记 key 必须带日期戳，否则跨天会误判成已记过
    flag = function_body("autoFillFlagKey", src)
    if flag is None:
        problems.append("找不到 autoFillFlagKey")
    elif "dayStamp" not in flag:
        problems.append("autoFillFlagKey 没带日期戳：跨天会误判为已记过")

    if problems:
        print("自动补录去重检查：不通过")
        for p in problems:
            print("  -", p)
        return 1

    print(
        "自动补录去重检查：通过"
        "（手动入账落标记 / 补录落标记 / 去重读持久化标记 / 标记带日期戳）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
