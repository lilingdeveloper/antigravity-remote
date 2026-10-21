#!/usr/bin/env python3
"""App Store Connect API 客户端 (专为 AGY Remote / com.liling.AntigravityRemote 定制)。
自动复用 ~/.appstoreconnect/config.json 中的 API Key 凭据，并自动查询 Bundle ID 对应的 APP_ID。
"""
import json
import os
import sys
import time
import warnings

warnings.filterwarnings("ignore")

BUNDLE_ID = "com.liling.AntigravityRemote"
API = "https://api.appstoreconnect.apple.com"

LOCALES = [
    "zh-Hans", "zh-Hant", "en-US", "ja", "ko", "fr-FR",
    "de-DE", "es-ES", "ru", "pt-BR", "it", "ar-SA"
]

CONFIG_DIR = os.path.expanduser(os.environ.get("ASC_CONFIG_DIR", "~/.appstoreconnect"))
_cached_app_id = os.environ.get("ASC_APP_ID")


def credentials():
    cfg = {}
    path = os.path.join(CONFIG_DIR, "config.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    key_id = os.environ.get("ASC_KEY_ID") or cfg.get("key_id")
    issuer = os.environ.get("ASC_ISSUER_ID") or cfg.get("issuer_id")
    if not key_id or not issuer:
        sys.exit(f"✗ 缺少 ASC 凭据: 请检查 {path}")
    key_path = os.path.expanduser(
        os.environ.get("ASC_KEY_PATH")
        or cfg.get("key_path")
        or os.path.join(CONFIG_DIR, "private_keys", f"AuthKey_{key_id}.p8")
    )
    if not os.path.exists(key_path):
        sys.exit(f"✗ 找不到私钥 {key_path}")
    return key_id, issuer, key_path


_token = {"value": None, "exp": 0}


def token():
    import jwt
    now = int(time.time())
    if _token["value"] and now < _token["exp"] - 60:
        return _token["value"]
    key_id, issuer, key_path = credentials()
    with open(key_path) as f:
        key = f.read()
    exp = now + 1100
    _token["value"] = jwt.encode(
        {"iss": issuer, "iat": now, "exp": exp, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    _token["exp"] = exp
    return _token["value"]


def call(method, path, body=None):
    import requests
    url = path if path.startswith("http") else API + path
    for attempt in range(5):
        try:
            r = requests.request(
                method,
                url,
                headers={
                    "Authorization": "Bearer " + token(),
                    "Content-Type": "application/json",
                },
                data=json.dumps(body) if body is not None else None,
                timeout=60,
            )
            if r.status_code in (500, 502, 503, 504) and attempt < 4:
                raise requests.exceptions.ConnectionError(f"HTTP {r.status_code}")
            break
        except requests.exceptions.RequestException:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))
    try:
        data = r.json()
    except Exception:
        data = {"raw": r.text}
    return r.status_code, data


def ok(method, path, body=None, expect=(200, 201, 204)):
    code, data = call(method, path, body)
    if code not in expect:
        raise RuntimeError(f"{method} {path} → {code}\n{json.dumps(data, ensure_ascii=False, indent=1)}")
    return data


def get_app_id():
    global _cached_app_id
    if _cached_app_id:
        return _cached_app_id
    d = ok("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&limit=5")
    if d.get("data"):
        _cached_app_id = d["data"][0]["id"]
        return _cached_app_id
    sys.exit(
        f"✗ App Store Connect 中尚未找到 Bundle ID 为 {BUNDLE_ID} 的 App 容器。\n"
        f"  （Apple 官方公开 API 禁止通过 POST /v1/apps 新建初始 App 壳，Bundle ID 已为您自动注册好：AGY Remote - {BUNDLE_ID}）\n"
        f"  请打开 https://appstoreconnect.apple.com/apps 点击左上角「+ → 新建 App」：\n"
        f"  • 平台：勾选 iOS\n"
        f"  • 名称：AGY Remote（或 AGY Remote - AI IDE Control）\n"
        f"  • 主要语言：简体中文 (Simplified Chinese)\n"
        f"  • 套装 ID (Bundle ID)：选择 AGY Remote - com.liling.AntigravityRemote\n"
        f"  • SKU：agyremote001\n"
        f"  点击创建后，重新运行本脚本即可全自动上传构建、12 语言元数据、截图并提交审核！"
    )


def find_version(version_string, platform="IOS"):
    app_id = get_app_id()
    d = ok(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions?filter[versionString]={version_string}"
        f"&filter[platform]={platform}&limit=5",
    )
    return d["data"][0] if d["data"] else None


def require_version(version_string):
    v = find_version(version_string)
    if not v:
        sys.exit(f"✗ ASC 上没有版本 {version_string} (先跑 release.py create-version {version_string})")
    return v


def open_submissions(states=("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES")):
    app_id = get_app_id()
    d = ok(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS"
        f"&filter[state]={','.join(states)}&include=items&limit=20",
    )
    return d["data"]


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if len(sys.argv) > 1 else 2)
    method, path = sys.argv[1].upper(), sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    code, data = call(method, path, body)
    print(code)
    print(json.dumps(data, ensure_ascii=False, indent=1))
