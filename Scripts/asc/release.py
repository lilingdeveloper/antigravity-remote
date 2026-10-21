#!/usr/bin/env python3
"""AGY Remote — App Store Connect 全流程发版脚本
支持子命令:
    release.py status         1.0.0
    release.py create-version 1.0.0 [--copyright '2026 Antigravity Remote Contributors']
    release.py setup-metadata 1.0.0     # 一键写入 12 语言 AppInfo + Version 描述/关键词/推广文本/隐私URL/支持URL + 年龄分级 + 审核备注(含Demo说明)
    release.py attach-build   1.0.0 --build 3
    release.py submit         1.0.0 [--submit]
"""
import argparse
import json
import sys
import time

import asc
from metadata_12langs import METADATA, PRIVACY_URL, SUPPORT_URL, MARKETING_URL, COPYRIGHT, REVIEW_DETAIL


def say(dry, msg):
    print(("[dry-run] " if dry else "") + msg, flush=True)


def cmd_status(a):
    v = asc.require_version(a.version)
    at = v["attributes"]
    print(f"版本 {a.version}  id={v['id']}  appStoreState={at.get('appStoreState')}  "
          f"appVersionState={at.get('appVersionState')}  releaseType={at.get('releaseType')}")
    b = asc.ok("GET", f"/v1/appStoreVersions/{v['id']}/build")["data"]
    if b:
        ba = b["attributes"]
        print(f"构建   {ba['version']}  processingState={ba['processingState']}  "
              f"usesNonExemptEncryption={ba.get('usesNonExemptEncryption')}")
    else:
        print("构建   (未挂构建)")
    problems = preflight(v, verbose=True)
    for sub in asc.open_submissions():
        print(f"提交   reviewSubmission {sub['id']}  state={sub['attributes']['state']}  "
              f"items={len(sub['relationships']['items']['data'])}")
    print("预检   " + ("✓ 可以提交" if not problems else f"✗ {len(problems)} 项未就绪"))


def preflight(v, verbose=False):
    problems = []
    b = asc.ok("GET", f"/v1/appStoreVersions/{v['id']}/build")["data"]
    if not b:
        problems.append("未挂构建 (release.py attach-build)")
    elif b["attributes"]["processingState"] != "VALID":
        problems.append(f"构建 processingState={b['attributes']['processingState']}")
    locs = asc.ok("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")["data"]
    by = {l["attributes"]["locale"]: l for l in locs}
    for loc in asc.LOCALES:
        l = by.get(loc)
        if not l:
            problems.append(f"{loc}: 缺本地化")
            continue
        if not (l["attributes"].get("description") or "").strip():
            problems.append(f"{loc}: description 为空")
        d = asc.ok("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets"
                          "?include=appScreenshots&limit=20")
        inc = {i["id"]: i["attributes"] for i in d.get("included", []) if i["type"] == "appScreenshots"}
        counts = {}
        for s in d["data"]:
            ids = [x["id"] for x in s["relationships"]["appScreenshots"]["data"]]
            done = sum(1 for i in ids if inc[i]["assetDeliveryState"]["state"] == "COMPLETE")
            counts[s["attributes"]["screenshotDisplayType"]] = (done, len(ids))
            if done == 0 or done != len(ids):
                problems.append(f"{loc}: {s['attributes']['screenshotDisplayType']} 截图 {done}/{len(ids)} COMPLETE")
        for need in ("APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"):
            if need not in counts:
                problems.append(f"{loc}: 没有 {need} 截图组")
        if verbose:
            shots = "  ".join(f"{k}={c[0]}/{c[1]}" for k, c in sorted(counts.items()))
            print(f"  {loc:8} desc={'✓' if (l['attributes'].get('description') or '').strip() else '✗'}  {shots}")
    if verbose:
        for p in problems:
            print(f"  ✗ {p}")
    return problems


def cmd_create_version(a):
    app_id = asc.get_app_id()
    v = asc.find_version(a.version)
    if v:
        print(f"版本 {a.version} 已存在: {v['attributes']['appStoreState']} ({v['id']}), 更新 copyright")
        if not a.dry_run:
            asc.ok("PATCH", f"/v1/appStoreVersions/{v['id']}", {
                "data": {
                    "type": "appStoreVersions",
                    "id": v["id"],
                    "attributes": {"copyright": a.copyright or COPYRIGHT, "releaseType": a.release_type}
                }
            }, expect=(200,))
        return
    attrs = {"platform": "IOS", "versionString": a.version, "releaseType": a.release_type, "copyright": a.copyright or COPYRIGHT}
    body = {"data": {"type": "appStoreVersions", "attributes": attrs,
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
    say(a.dry_run, f"POST /v1/appStoreVersions {json.dumps(attrs, ensure_ascii=False)}")
    if a.dry_run:
        return
    d = asc.ok("POST", "/v1/appStoreVersions", body, expect=(201,))
    print(f"✓ 已建版本 {a.version} ({d['data']['id']})")


def cmd_setup_metadata(a):
    app_id = asc.get_app_id()
    v = asc.require_version(a.version)
    vid = v["id"]

    # 0. 更新版本 copyright
    if not a.dry_run:
        asc.ok("PATCH", f"/v1/appStoreVersions/{vid}", {
            "data": {"type": "appStoreVersions", "id": vid, "attributes": {"copyright": COPYRIGHT}}
        }, expect=(200,))
    print(f"✓ 版本 {a.version} copyright 已设为 {COPYRIGHT}")

    # 1. 更新 AppInfo Localizations (name, subtitle, privacyPolicyUrl) & Age Rating
    infos = asc.ok("GET", f"/v1/apps/{app_id}/appInfos")["data"]
    editable_infos = [i for i in infos if i["attributes"].get("appStoreState") in (
        "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"
    )] or infos
    for info in editable_infos[:1]:
        iid = info["id"]
        locs = asc.ok("GET", f"/v1/appInfos/{iid}/appInfoLocalizations?limit=50")["data"]
        by_loc = {l["attributes"]["locale"]: l for l in locs}
        for loc in asc.LOCALES:
            m = METADATA[loc]
            attrs = {
                "subtitle": m["subtitle"],
                "privacyPolicyUrl": PRIVACY_URL,
            }
            if loc in by_loc:
                lid = by_loc[loc]["id"]
                say(a.dry_run, f"AppInfoLoc {loc}: PATCH subtitle & privacyPolicyUrl")
                if not a.dry_run:
                    # 尝试同时更新 name，若名称已被占用则仅更新 subtitle 和 privacyPolicyUrl
                    code, _ = asc.call("PATCH", f"/v1/appInfoLocalizations/{lid}", {
                        "data": {"type": "appInfoLocalizations", "id": lid, "attributes": {**attrs, "name": m["name"]}}
                    })
                    if code not in (200, 201):
                        asc.ok("PATCH", f"/v1/appInfoLocalizations/{lid}", {
                            "data": {"type": "appInfoLocalizations", "id": lid, "attributes": attrs}
                        }, expect=(200,))
            else:
                say(a.dry_run, f"AppInfoLoc {loc}: POST name, subtitle & privacyPolicyUrl")
                if not a.dry_run:
                    code, _ = asc.call("POST", "/v1/appInfoLocalizations", {
                        "data": {
                            "type": "appInfoLocalizations",
                            "attributes": {"locale": loc, "name": m["name"], **attrs},
                            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": iid}}}
                        }
                    })
                    if code not in (200, 201):
                        asc.ok("POST", "/v1/appInfoLocalizations", {
                            "data": {
                                "type": "appInfoLocalizations",
                                "attributes": {"locale": loc, "name": "AGY Remote - AI IDE Control", **attrs},
                                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": iid}}}
                            }
                        }, expect=(201,))

        # 设置年龄分级 (全部 NONE -> 4+)
        code, ard = asc.call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")
        if code == 200 and ard.get("data"):
            ard_id = ard["data"]["id"]
            age_attrs = {
                "alcoholTobaccoOrDrugUseOrReferences": "NONE",
                "contests": "NONE",
                "gambling": False,
                "gamblingSimulated": "NONE",
                "horrorOrFearThemes": "NONE",
                "matureOrSuggestiveThemes": "NONE",
                "medicalOrTreatmentInformation": "NONE",
                "profanityOrCrudeHumor": "NONE",
                "sexualContentGraphicAndNudity": "NONE",
                "sexualContentOrNudity": "NONE",
                "violenceCartoonOrFantasy": "NONE",
                "violenceRealistic": "NONE",
                "violenceRealisticProlongedGraphicOrSadistic": "NONE",
                "unrestrictedWebAccess": False,
                "kidsAgeBand": None,
                "lootBox": False,
            }
            if not a.dry_run:
                asc.call("PATCH", f"/v1/ageRatingDeclarations/{ard_id}", {
                    "data": {"type": "ageRatingDeclarations", "id": ard_id, "attributes": age_attrs}
                })
            print("✓ 年龄分级 (4+) 已配置")

    # 2. 更新 Version Localizations (description, keywords, promotionalText, whatsNew, supportUrl, marketingUrl)
    vlocs = asc.ok("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")["data"]
    vby = {l["attributes"]["locale"]: l for l in vlocs}
    # 首次发布 (1.0.0) 时 ASC 不允许写 whatsNew 字段（仅升级版可写），自动判断
    is_initial_v1 = (a.version == "1.0.0" or len(asc.ok("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=5")["data"]) <= 1)
    for loc in asc.LOCALES:
        m = METADATA[loc]
        vattrs = {
            "description": m["description"],
            "keywords": m["keywords"],
            "promotionalText": m["promotionalText"],
            "supportUrl": SUPPORT_URL,
            "marketingUrl": MARKETING_URL,
        }
        if not is_initial_v1:
            vattrs["whatsNew"] = m["whatsNew"]
        if loc in vby:
            lid = vby[loc]["id"]
            say(a.dry_run, f"VersionLoc {loc}: PATCH description/keywords/promo/supportUrl")
            if not a.dry_run:
                code, resp = asc.call("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {
                    "data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": vattrs}
                })
                if code not in (200, 201):
                    vattrs.pop("whatsNew", None)
                    asc.ok("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {
                        "data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": vattrs}
                    }, expect=(200,))
        else:
            say(a.dry_run, f"VersionLoc {loc}: POST 新语言本地化")
            if not a.dry_run:
                code, resp = asc.call("POST", "/v1/appStoreVersionLocalizations", {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": loc, **vattrs},
                        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}
                    }
                })
                if code not in (200, 201):
                    vattrs.pop("whatsNew", None)
                    asc.ok("POST", "/v1/appStoreVersionLocalizations", {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "attributes": {"locale": loc, **vattrs},
                            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}
                        }
                    }, expect=(201,))
    print("✓ 12 语言版本详情 (描述/关键词/推广文本/支持网址) 已全部写入")

    # 3. 更新 App Store Review Detail (联系人 + Demo 模式测试指南)
    code, rev = asc.call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    if not a.dry_run:
        if code == 200 and rev.get("data"):
            rid = rev["data"]["id"]
            asc.ok("PATCH", f"/v1/appStoreReviewDetails/{rid}", {
                "data": {"type": "appStoreReviewDetails", "id": rid, "attributes": REVIEW_DETAIL}
            }, expect=(200,))
        else:
            asc.ok("POST", "/v1/appStoreReviewDetails", {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": REVIEW_DETAIL,
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}
                }
            }, expect=(201,))
    print("✓ 审核联系信息与 Demo 模式审核测试说明已写入")


def cmd_attach_build(a):
    app_id = asc.get_app_id()
    v = asc.require_version(a.version)
    deadline = time.time() + a.wait * 60
    while True:
        d = asc.ok("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={a.build}"
                          f"&filter[preReleaseVersion.version]={a.version}&filter[preReleaseVersion.platform]=IOS"
                          "&limit=5")
        b = d["data"][0] if d["data"] else None
        state = b["attributes"]["processingState"] if b else "NOT_FOUND"
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            sys.exit(f"✗ 构建 {a.version} ({a.build}) processingState={state}")
        if a.dry_run or time.time() > deadline:
            print(f"构建 {a.version} ({a.build}) 当前 {state}" + ("" if a.dry_run else ", 等待超时"))
            if a.dry_run:
                return
            sys.exit(1)
        print(f"构建 {state}, 30 秒后重查...", flush=True)
        time.sleep(30)
    cur = asc.ok("GET", f"/v1/appStoreVersions/{v['id']}/build")["data"]
    if cur and cur["id"] == b["id"]:
        print(f"构建 {a.build} 已挂在 {a.version} 上, 跳过")
        return
    say(a.dry_run, f"PATCH appStoreVersion {v['id']} build → {b['id']} ({a.build})")
    if not a.dry_run:
        asc.ok("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build",
               {"data": {"type": "builds", "id": b["id"]}}, expect=(204,))
        print("✓ 构建已挂上")


def cmd_submit(a):
    app_id = asc.get_app_id()
    v = asc.require_version(a.version)
    state = v["attributes"]["appStoreState"]
    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE"):
        print(f"版本 {a.version} 已是 {state}, 无需再提交")
        return
    problems = preflight(v)
    if problems:
        print("✗ 预检未通过 (`release.py status` 看详情):")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    print("✓ 预检通过: 构建 VALID, 12 语言描述与截图齐全")

    drafts = [s for s in asc.open_submissions(states=("READY_FOR_REVIEW",))]
    sub = drafts[0] if drafts else None
    if sub:
        print(f"复用草稿 reviewSubmission {sub['id']}")
    else:
        say(a.dry_run, "POST /v1/reviewSubmissions (platform=IOS)")
        if not a.dry_run:
            sub = asc.ok("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}, expect=(201,))["data"]
            print(f"✓ 新建 reviewSubmission {sub['id']}")

    has_item = False
    if sub:
        items = asc.ok("GET", f"/v1/reviewSubmissions/{sub['id']}/items?include=appStoreVersion&limit=20")["data"]
        has_item = any((i["relationships"].get("appStoreVersion", {}).get("data") or {}).get("id") == v["id"]
                       for i in items)
    if not has_item:
        say(a.dry_run, f"POST /v1/reviewSubmissionItems (appStoreVersion {v['id']})")
        if not a.dry_run:
            asc.ok("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}}, expect=(201,))
            print("✓ 版本已加入提交")

    if not a.submit:
        print("已准备好, 未送审。确认无误后加 --submit 再跑一次。")
        return
    say(a.dry_run, f"PATCH /v1/reviewSubmissions/{sub['id'] if sub else '<new>'} submitted=true")
    if a.dry_run:
        return
    d = asc.ok("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions",
        "id": sub["id"], "attributes": {"submitted": True}}}, expect=(200,))
    print(f"✓ 已送审: reviewSubmission {sub['id']} → {d['data']['attributes']['state']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)

    p = sp.add_parser("status", help="查看版本是否可提交")
    p.add_argument("version")
    p.set_defaults(fn=cmd_status)

    p = sp.add_parser("create-version", help="新建或更新 App Store 版本")
    p.add_argument("version")
    p.add_argument("--copyright", default=COPYRIGHT)
    p.add_argument("--release-type", default="AFTER_APPROVAL", choices=["AFTER_APPROVAL", "MANUAL", "SCHEDULED"])
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_create_version)

    p = sp.add_parser("setup-metadata", help="一键写入 12 语言元数据、隐私政策URL、年龄分级与审核说明")
    p.add_argument("version")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_setup_metadata)

    p = sp.add_parser("attach-build", help="等构建 VALID 并挂到版本")
    p.add_argument("version")
    p.add_argument("--build", required=True, help="CFBundleVersion, 如 3")
    p.add_argument("--wait", type=int, default=45)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_attach_build)

    p = sp.add_parser("submit", help="预检 + 准备提交; 加 --submit 才真正送审")
    p.add_argument("version")
    p.add_argument("--submit", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_submit)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
