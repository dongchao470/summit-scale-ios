#!/usr/bin/env python3
"""生成「山与秤」App 图标（1024x1024 PNG），纯标准库实现，无第三方依赖。

用法:
    python3 scripts/make_icon.py
输出:
    SummitScale/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "SummitScale", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
)

SKY_TOP = (14, 24, 46)
SKY_BOTTOM = (13, 78, 88)
SUN = (255, 209, 116)
FAR_MOUNTAIN = (30, 62, 88)
NEAR_MOUNTAIN = (16, 36, 58)
SNOW = (228, 241, 250)
RIDGE_LINE = (122, 226, 214)


def mix(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def ridge(fx, center, peak, slope):
    return peak + slope * abs(fx - center)


def build_rows():
    rows = []
    sun_cx, sun_cy, sun_r = 0.735 * SIZE, 0.235 * SIZE, 0.078 * SIZE
    for y in range(SIZE):
        t = y / (SIZE - 1)
        sky = mix(SKY_TOP, SKY_BOTTOM, t ** 0.85)
        row = bytearray()
        for x in range(SIZE):
            fx = x / (SIZE - 1)
            r, g, b = sky

            dx = x - sun_cx
            dy = y - sun_cy
            dist = (dx * dx + dy * dy) ** 0.5
            if dist < sun_r:
                edge = min(1.0, (sun_r - dist) / (sun_r * 0.16))
                r, g, b = mix((r, g, b), SUN, edge)

            far = ridge(fx, 0.40, 0.345, 1.02)
            near = ridge(fx, 0.63, 0.515, 1.18)

            if 0.0 <= far <= 1.0 and t >= far:
                r, g, b = FAR_MOUNTAIN
                if t <= far + 0.035:
                    r, g, b = SNOW
            if 0.0 <= near <= 1.0 and t >= near:
                r, g, b = NEAR_MOUNTAIN
                if t <= near + 0.012:
                    r, g, b = RIDGE_LINE

            row += bytes((r, g, b))
        rows.append(row)
    return rows


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main():
    rows = build_rows()
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(png)
    print("wrote %s (%d bytes)" % (OUT, len(png)))


if __name__ == "__main__":
    main()
