#!/usr/bin/env python3
"""用 Scripts/appstore-ads/out/*.png 替换某个版本的 App Store 截图 (转 JPEG 上传)。"""
import argparse
import hashlib
import io
import os
import sys
import time

import asc

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.normpath(os.path.join(HERE, "..", "appstore-ads", "out"))
SETTYPE = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129"}
ORDER = ["01_chat", "02_approval", "03_diffs", "04_models"]


def jpeg_bytes(png):
    try:
        from PIL import Image
        buf = io.BytesIO()
        Image.open(png).convert("RGB").save(buf, "JPEG", quality=92)
        return buf.getvalue()
    except ImportError:
        import subprocess, tempfile
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tf:
            tmp_jpg = tf.name
        try:
            subprocess.run(["/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", "92", png, "--out", tmp_jpg],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            with open(tmp_jpg, "rb") as f:
                return f.read()
        finally:
            if os.path.exists(tmp_jpg):
                os.remove(tmp_jpg)


def upload_one(set_id, name, data):
    import requests
    d = asc.ok("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
        "attributes": {"fileName": name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}},
        expect=(201,))
    sid = d["data"]["id"]
    for op in d["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        h = {x["name"]: x["value"] for x in op["requestHeaders"]}
        r = requests.request(op["method"], op["url"], headers=h, data=chunk, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"put {name}: {r.status_code} {r.text[:200]}")
    asc.ok("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}},
        expect=(200,))
    return sid


def wait_complete(ids):
    states = {}
    for _ in range(120):
        for i in ids:
            d = asc.ok("GET", f"/v1/appScreenshots/{i}?fields[appScreenshots]=assetDeliveryState")
            states[i] = d["data"]["attributes"]["assetDeliveryState"]["state"]
        if all(s == "COMPLETE" for s in states.values()):
            return
        if any(s == "FAILED" for s in states.values()):
            raise RuntimeError(f"asset FAILED (重跑即可, FAILED 的会被删掉重传): {states}")
        time.sleep(4)
    raise RuntimeError(f"timeout: {states}")


def ensure_set(loc_id, sets, stype, dry_run):
    if stype in sets:
        return sets[stype]
    if dry_run:
        return None
    d = asc.ok("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": stype},
        "relationships": {"appStoreVersionLocalization": {"data": {
            "type": "appStoreVersionLocalizations", "id": loc_id}}}}}, expect=(201,))
    s = d["data"]
    s.setdefault("relationships", {})["appScreenshots"] = {"data": []}
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="ASC 上的版本号, 如 1.0.0")
    ap.add_argument("--dir", default=DEFAULT_DIR, help=f"PNG 目录 (默认 {DEFAULT_DIR})")
    ap.add_argument("--dry-run", action="store_true", help="只对账并打印计划, 不上传/删除")
    ap.add_argument("locales", nargs="*", help="ASC 语言码, 默认全部")
    a = ap.parse_args()

    locales = a.locales or asc.LOCALES
    missing = [f"{dev}_{loc}_{o}.png" for loc in locales for dev in SETTYPE for o in ORDER
               if not os.path.exists(os.path.join(a.dir, f"{dev}_{loc}_{o}.png"))]
    if missing:
        sys.exit(f"✗ {a.dir} 缺 {len(missing)} 张图, 例如 {missing[:3]} (先跑 compose.py)")

    v = asc.require_version(a.version)
    print(f"版本 {a.version}: {v['attributes']['appStoreState']} ({v['id']})")
    for sub in asc.open_submissions():
        print(f"⚠️  存在未结束的 reviewSubmission {sub['id']} ({sub['attributes']['state']})")

    d = asc.ok("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")
    locs = {l["attributes"]["locale"]: l["id"] for l in d["data"]}
    for loc in locales:
        if loc not in locs:
            sys.exit(f"✗ 版本 {a.version} 没有本地化 {loc} (先跑 release.py setup-metadata {a.version})")
        d = asc.ok("GET", f"/v1/appStoreVersionLocalizations/{locs[loc]}/appScreenshotSets"
                          "?include=appScreenshots&limit=20")
        sets = {s["attributes"]["screenshotDisplayType"]: s for s in d["data"]}
        inc = {i["id"]: i["attributes"] for i in d.get("included", []) if i["type"] == "appScreenshots"}
        for dev, stype in SETTYPE.items():
            s = ensure_set(locs[loc], sets, stype, a.dry_run)
            current = [x["id"] for x in s["relationships"]["appScreenshots"]["data"]] if s else []
            have = {}
            for i in current:
                ck = inc[i].get("sourceFileChecksum")
                if ck and ck not in have and inc[i]["assetDeliveryState"]["state"] != "FAILED":
                    have[ck] = i
            plan = []
            for o in ORDER:
                data = jpeg_bytes(os.path.join(a.dir, f"{dev}_{loc}_{o}.png"))
                plan.append((o, data, have.get(hashlib.md5(data).hexdigest())))
            keep = {sid for _, _, sid in plan if sid}
            to_upload = sum(1 for _, _, sid in plan if not sid)
            to_delete = [i for i in current if i not in keep]
            if a.dry_run:
                print(f"[dry-run] {loc} {dev}: 复用 {len(keep)} 传 {to_upload} 删 {len(to_delete)}")
                continue
            new = [sid or upload_one(s["id"], f"{dev}_{loc}_{o}.jpg", data) for o, data, sid in plan]
            wait_complete(new)
            for i in to_delete:
                asc.ok("DELETE", f"/v1/appScreenshots/{i}", expect=(204,))
            asc.ok("PATCH", f"/v1/appScreenshotSets/{s['id']}/relationships/appScreenshots",
                   {"data": [{"type": "appScreenshots", "id": i} for i in new]}, expect=(204,))
            print(f"{loc} {dev}: +{to_upload} -{len(to_delete)}", flush=True)


if __name__ == "__main__":
    main()
