#!/usr/bin/env python3
"""
ARK STUDY LAB - 자동 분석 도구 (분석 전용 계정으로 동작)

사용법:
  ARK_ANALYST_EMAIL=... ARK_ANALYST_PASSWORD=... python3 ai_analyst.py fetch OUT_DIR
      → 초안이 필요한 기록을 OUT_DIR/pending.json 에 저장하고,
        공부 사진을 OUT_DIR/<log_id>.<확장자> 로 내려받음
  ARK_ANALYST_EMAIL=... ARK_ANALYST_PASSWORD=... python3 ai_analyst.py save DRAFTS_JSON
      → [{"log_id": ..., "draft_for_parent": ..., "teacher_notes": ...}, ...] 를 저장

분석 계정은 기록·사진을 읽고 초안을 저장하는 것만 할 수 있음(019 SQL 참고).
"""
import json
import os
import sys
import urllib.parse
import urllib.request

SUPABASE_URL = "https://ffzwgqqggwnhxigkjsum.supabase.co"
PUBLISHABLE_KEY = "sb_publishable_3qapTyE--7G3G3flR_D9jQ_45eztl_-"
BUCKET = "study-log-images"


def request(method, path, token=None, body=None, raw=False):
    headers = {"apikey": PUBLISHABLE_KEY}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(SUPABASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            content = res.read()
            if raw:
                return content
            return json.loads(content) if content else None
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"HTTP {e.code} {method} {path.split('?')[0]}: {msg}")


def login():
    email = os.environ.get("ARK_ANALYST_EMAIL")
    password = os.environ.get("ARK_ANALYST_PASSWORD")
    if not email or not password:
        raise SystemExit("ARK_ANALYST_EMAIL / ARK_ANALYST_PASSWORD 가 필요합니다")
    res = request("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})
    return res["access_token"]


def fetch(out_dir):
    token = login()
    os.makedirs(out_dir, exist_ok=True)
    rows = request("POST", "/rest/v1/rpc/get_logs_needing_ai_draft", token,
                   body={"max_days": int(os.environ.get("ARK_MAX_DAYS", "7")), "max_rows": 30}) or []
    for row in rows:
        row["image_file"] = None
        path = row.get("image_path")
        if not path:
            continue
        signed = request("POST", f"/storage/v1/object/sign/{BUCKET}/{urllib.parse.quote(path)}", token,
                         body={"expiresIn": 600})
        url = signed.get("signedURL") or signed.get("signedUrl")
        if not url:
            continue
        if not url.startswith("/storage/v1"):
            url = "/storage/v1" + url
        content = request("GET", url, raw=True)
        ext = os.path.splitext(path)[1] or ".jpg"
        file_path = os.path.join(out_dir, f"{row['log_id']}{ext}")
        with open(file_path, "wb") as f:
            f.write(content)
        row["image_file"] = file_path
    with open(os.path.join(out_dir, "pending.json"), "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    print(f"초안이 필요한 기록 {len(rows)}건, 사진 {sum(1 for r in rows if r['image_file'])}장 → {out_dir}")


def save(drafts_path):
    token = login()
    with open(drafts_path, encoding="utf-8") as f:
        drafts = json.load(f)
    saved = 0
    for d in drafts:
        request("POST", "/rest/v1/rpc/save_ai_draft", token, body={
            "target_log_id": d["log_id"],
            "draft": d["draft_for_parent"],
            "notes": d.get("teacher_notes"),
            "model_name": d.get("model", "claude"),
        })
        saved += 1
    print(f"초안 {saved}건 저장 완료")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("fetch", "save"):
        raise SystemExit(__doc__)
    if sys.argv[1] == "fetch":
        fetch(sys.argv[2])
    else:
        save(sys.argv[2])
