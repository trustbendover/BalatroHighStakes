#!/usr/bin/env python3
"""Balatro High Stakes logo (own pixel art, GPL-3.0 like the mod). Writes mod/assets/1x|2x/mp3p_logo.png.
Chunky 5x7 letters, dark outline + drop shadow, gold HIGH / red STAKES, two poker chips, a shine row."""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = {  # 5x7, '#' = pixel
 "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
 "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
 "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
 "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
 "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
 "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
 "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
 "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
 "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
 "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
 "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
 "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
}
GOLD, GOLD_HI, GOLD_LO = (234, 192, 88), (255, 228, 140), (196, 146, 52)
RED, RED_HI, RED_LO = (254, 95, 85), (255, 150, 140), (200, 60, 55)
BLUE, BLUE_HI = (0, 157, 255), (120, 200, 255)
WHITE, OUT, SHADOW = (255, 255, 255), (30, 43, 45), (0, 0, 0, 110)
W, H = 220, 54

def letters(img, text, x, y, cell, colours, wobble=None):
    """Draw text with cell-sized pixels. colours: (base, highlight, low) or a list per letter."""
    px = img.load()
    cx = x
    for i, ch in enumerate(text):
        if ch == " ":
            cx += 3 * cell; continue
        base, hi, lo = colours[i] if isinstance(colours, list) else colours
        dy = wobble[i % len(wobble)] if wobble else 0
        for r, row in enumerate(FONT[ch]):
            for c, v in enumerate(row):
                if v != "#": continue
                col = hi if r == 0 else (lo if r == 6 else base)
                for a in range(cell):
                    for b in range(cell):
                        X, Y = cx + c * cell + a, y + dy + r * cell + b
                        if 0 <= X < W and 0 <= Y < H: px[X, Y] = col + (255,)
        cx += 6 * cell
    return cx

def outline(img, thick=2, y_min=0):
    src = img.copy(); s = src.load(); d = img.load()
    for y in range(y_min, H):
        for x in range(W):
            if s[x, y][3] == 0:
                for dx in range(-thick, thick + 1):
                    for dy in range(-thick, thick + 1):
                        X, Y = x + dx, y + dy
                        if 0 <= X < W and 0 <= Y < H and s[X, Y][3] == 255:
                            d[x, y] = OUT + (255,); break
                    else: continue
                    break

def chip(img, cx, cy, r, col, hi):
    px = img.load()
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 <= r * r:
                ang_stripe = ((x - cx) * (y - cy)) == 0 and d2 > (r - 3) ** 2  # 4 white notches on the rim
                c = WHITE if ang_stripe or (r - 4) ** 2 < d2 <= (r - 3) ** 2 else (hi if y < cy - r // 2 else col)
                px[x, y] = c + (255,)

def make():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # small "BALATRO" (2px cells) between two chips
    small_w = 7 * 12 - 2
    sx = (W - small_w) // 2
    letters(img, "BALATRO", sx, 3, 2, (WHITE, WHITE, (200, 210, 212)))
    chip(img, sx - 14, 9, 6, RED, RED_HI)
    chip(img, sx + small_w + 13, 9, 6, BLUE, BLUE_HI)
    # big "HIGH STAKES" (3px cells), gold + red, gentle per-letter wobble
    big_w = 4 * 18 + 9 + 6 * 18 - 3
    bx = (W - big_w) // 2
    cols = [(GOLD, GOLD_HI, GOLD_LO)] * 4 + [None] + [(RED, RED_HI, RED_LO)] * 6
    cols = [c or (GOLD, GOLD_HI, GOLD_LO) for c in cols]
    letters(img, "HIGH STAKES", bx, 24, 3, cols, wobble=[0, -1, 0, 1, 0, 1, 0, -1, 0, 1, -1])
    outline(img, 1)        # thin around the small BALATRO so its letters stay open
    outline(img, 1, 19)    # chunky 2 px around HIGH STAKES
    # drop shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0)); s = sh.load(); p = img.load()
    for y in range(H - 3):
        for x in range(W - 3):
            if p[x, y][3] == 255: s[x + 2, y + 3] = SHADOW
    sh.alpha_composite(img)
    return sh

if __name__ == "__main__":
    logo = make()
    for scale, sub in ((1, "1x"), (2, "2x")):
        out = os.path.join(ROOT, "mod", "assets", sub, "mp3p_logo.png")
        logo.resize((W * scale, H * scale), Image.NEAREST).save(out)
        print("wrote", out)
    if len(sys.argv) > 1:
        logo.resize((W * 4, H * 4), Image.NEAREST).save(sys.argv[1]); print("wrote", sys.argv[1])
