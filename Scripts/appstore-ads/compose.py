# -*- coding: utf-8 -*-
"""把真实界面截图（raw/）套上各语言的广告文案，输出 App Store 尺寸的海报（out/）。
用法: compose.py <iphone|ipad> [lang ...]
"""
import os, sys, subprocess, html, shutil
sys.path.insert(0, os.path.dirname(__file__))
from ad_copy import COPY, SCENES

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

ASC_LOCALE_MAP = {
    "zh-Hans": "zh-Hans",
    "zh-Hant": "zh-Hant",
    "en": "en-US",
    "ja": "ja",
    "ko": "ko",
    "fr": "fr-FR",
    "de": "de-DE",
    "es": "es-ES",
    "ru": "ru",
    "pt": "pt-BR",
    "it": "it",
    "ar": "ar-SA",
}

ACCENT = {
    "chat":     ("#60a5fa", "rgba(59,130,246,0.30)"),
    "approval": ("#34d399", "rgba(16,185,129,0.28)"),
    "diffs":    ("#a78bfa", "rgba(139,92,246,0.28)"),
    "models":   ("#22d3ee", "rgba(6,182,212,0.28)"),
}
SIZES = {"iphone": (1320, 2868), "ipad": (2064, 2752)}
FONTS = ('-apple-system, "SF Pro Display", "PingFang SC", "PingFang TC", "Hiragino Sans", '
         '"Apple SD Gothic Neo", "Geeza Pro", "Helvetica Neue", sans-serif')


def card_html(kind, lang, scene, badge, title, sub, img):
    W, H = SIZES[kind]
    phone = kind == "iphone"
    k = 1.0 if phone else 1.30
    long_title = len(title) > (24 if lang in ("de", "ru", "fr", "pt", "es", "it") else 16)
    t_size = int((74 if long_title else 90) * k)
    dev_w = int((1120 if phone else 1620))
    badge_c, glow = ACCENT[scene]
    rtl = ' dir="rtl"' if lang == "ar" else ""
    return f"""<!DOCTYPE html><html lang="{lang}"{rtl}><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{width:{W}px;height:{H}px;overflow:hidden;background:#080c15;color:#fff;font-family:{FONTS};
  display:flex;flex-direction:column;align-items:center;position:relative}}
.glow{{position:absolute;width:{int(W*0.95)}px;height:{int(W*0.95)}px;border-radius:50%;top:{int(H*0.16)}px;
  background:radial-gradient(circle,{glow} 0%,rgba(8,12,21,0) 72%);filter:blur(70px);z-index:1}}
.head{{z-index:5;margin-top:{int(145*k)}px;text-align:center;padding:0 {int(68*k)}px;
  display:flex;flex-direction:column;align-items:center}}
.badge{{padding:{int(13*k)}px {int(30*k)}px;border-radius:999px;background:rgba(255,255,255,.07);
  border:1px solid rgba(255,255,255,.16);font-size:{int(30*k)}px;font-weight:700;letter-spacing:2px;
  color:{badge_c};margin-bottom:{int(30*k)}px;text-transform:uppercase}}
.title{{text-wrap:balance;font-size:{t_size}px;font-weight:800;line-height:1.2;letter-spacing:-1px;margin-bottom:{int(20*k)}px;
  background:linear-gradient(180deg,#fff 35%,#cbd5e1 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent}}
.sub{{font-size:{int(38*k)}px;line-height:1.45;color:#9fb0c8;max-width:{int(1120*k)}px}}
.dev{{z-index:5;margin-top:{int(60*k)}px;width:{dev_w}px;flex:1;overflow:hidden;
  border:{int(14*k)}px solid #1b1c20;border-bottom:none;border-radius:{int(86*k)}px {int(86*k)}px 0 0;
  background:#000;box-shadow:0 0 0 2px rgba(255,255,255,.14),0 40px 110px rgba(0,0,0,.9)}}
.dev img{{width:100%;display:block}}
</style></head><body><div class="glow"></div>
<div class="head"><div class="badge">{html.escape(badge)}</div>
<div class="title">{html.escape(title)}</div><div class="sub">{html.escape(sub)}</div></div>
<div class="dev"><img src="file://{img}"></div></body></html>"""


def clean_island(src, dst, kind="iphone"):
    try:
        from PIL import Image
        im = Image.open(src).convert("RGB")
        w, h = im.size
        px = im.load()
        xs0, xs1, ys1 = int(w * 0.34), int(w * 0.66), int(h * 0.06)
        dark = [(x, y) for y in range(ys1) for x in range(xs0, xs1) if sum(px[x, y]) < 45]
        if len(dark) > w * 0.05:
            l = min(x for x, _ in dark) - 10
            r = max(x for x, _ in dark) + 10
            t = max(min(y for _, y in dark) - 8, 0)
            b = max(y for _, y in dark) + 8
            for y in range(t, b + 1):
                fill = px[max(l - 4, 0), y]
                for x in range(l, r + 1):
                    px[x, y] = fill
        if kind == "ipad":
            x0, x1 = int(w * 0.080), int(w * 0.175)
            y0, y1 = int(h * 0.003), int(h * 0.025)
            for y in range(y0, y1):
                fill = px[min(x1 + 6, w - 1), y]
                for x in range(x0, x1):
                    px[x, y] = fill
        im.save(dst)
    except ImportError:
        shutil.copyfile(src, dst)


def render(kind, lang, idx, scene):
    img = os.path.join(HERE, "raw", kind, lang, f"{scene}.png")
    if not os.path.exists(img):
        return False
    cleaned = f"/tmp/_agy_clean_{kind}_{lang}_{scene}.png"
    clean_island(img, cleaned, kind)
    img = cleaned
    badge, title, sub = COPY[lang][SCENES.index(scene)]
    out_dir = os.path.join(HERE, "out", kind, lang)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{idx:02d}_{scene}.png")
    tmp = f"/tmp/_agy_ad_{kind}_{lang}_{scene}.html"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(card_html(kind, lang, scene, badge, title, sub, img))
    W, H = SIZES[kind]
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--screenshot={out}", f"--window-size={W},{H}", "--force-device-scale-factor=1",
                    f"file://{tmp}"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.remove(tmp)
    asc_loc = ASC_LOCALE_MAP.get(lang, lang)
    flat_out = os.path.join(HERE, "out", f"{kind}_{asc_loc}_{idx:02d}_{scene}.png")
    shutil.copyfile(out, flat_out)
    return True


if __name__ == "__main__":
    kind = sys.argv[1]
    langs = sys.argv[2:] or list(COPY)
    for lang in langs:
        for i, scene in enumerate(SCENES, 1):
            if render(kind, lang, i, scene):
                print("ok", kind, lang, scene, flush=True)
