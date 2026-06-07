#!/usr/bin/python3
import json
import os
import subprocess
import sys
import traceback
import urllib.parse
import urllib.request


def respond(status, content_type, body):
    if isinstance(body, str):
        body = body.encode("utf-8")
    sys.stdout.write(f"Status: {status}\r\n")
    sys.stdout.write(f"Content-Type: {content_type}\r\n")
    sys.stdout.write("Cache-Control: no-store\r\n")
    sys.stdout.write(f"Content-Length: {len(body)}\r\n")
    sys.stdout.write("\r\n")
    sys.stdout.flush()
    sys.stdout.buffer.write(body)


def webapi_url(params):
    query = urllib.parse.urlencode(params)
    host = os.environ.get("HTTP_HOST") or "127.0.0.1:5000"
    port = "5000"
    if ":" in host:
        port = host.rsplit(":", 1)[1]
    return f"http://127.0.0.1:{port}/webapi/entry.cgi?{query}"


def request_json(url, body=None):
    data = None
    headers = {}
    if body is not None:
        data = urllib.parse.urlencode(body).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=45) as res:
        return json.loads(res.read().decode("utf-8", "replace"))


def request_text(url):
    with urllib.request.urlopen(url, timeout=45) as res:
        return res.read().decode("utf-8", "replace")


def run_sql(sql):
    if os.geteuid() == 228233:
        args = ["psql", "-U", "VideoStation", "-d", "video_metadata", "-X", "-q", "-t", "-A", "-c", sql]
    else:
        command = f'psql -U VideoStation -d video_metadata -X -q -t -A -c "{sql.replace(chr(34), chr(92) + chr(34))}"'
        args = ["su", "-l", "VideoStation", "-s", "/bin/bash", "-c", command]
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, text=True)
    return result.stdout.strip()


def numeric_param(params, name):
    raw = (params.get(name) or [""])[0]
    return "".join(ch for ch in str(raw) if ch.isdigit())


def handle_watch_status(params):
    sid = (params.get("sid") or params.get("_sid") or [""])[0]
    if not sid:
        respond("400 Bad Request", "application/json; charset=utf-8", json.dumps({"success": False, "error": "missing sid"}))
        return

    position = numeric_param(params, "position") or "0"
    file_id = numeric_param(params, "file_id")
    mapper_id = numeric_param(params, "mapper_id")
    if not file_id and not mapper_id:
        respond("400 Bad Request", "application/json; charset=utf-8", json.dumps({"success": False, "error": "missing file_id or mapper_id"}))
        return

    if not mapper_id and file_id:
        mapper_id = run_sql(f"select mapper_id from video_file where id = {file_id} limit 1")
        mapper_id = "".join(ch for ch in mapper_id if ch.isdigit())
    if not file_id and mapper_id:
        file_id = run_sql(f"select id from video_file where mapper_id = {mapper_id} order by id limit 1")
        file_id = "".join(ch for ch in file_id if ch.isdigit())
    if not file_id or not mapper_id:
        respond("404 Not Found", "application/json; charset=utf-8", json.dumps({"success": False, "error": "file not resolved"}))
        return

    uid = run_sql("select uid from watch_status order by modify_date desc nulls last limit 1")
    uid = "".join(ch for ch in uid if ch.isdigit()) or "1026"
    sql = f"""
with updated as (
  update watch_status
  set position = {position}, modify_date = now()
  where uid = {uid} and video_file_id = {file_id} and mapper_id = {mapper_id}
  returning id
)
insert into watch_status(uid, video_file_id, mapper_id, position, create_date, modify_date)
select {uid}, {file_id}, {mapper_id}, {position}, now(), now()
where not exists (select 1 from updated)
returning id
"""
    run_sql(sql)
    respond("200 OK", "application/json; charset=utf-8", json.dumps({
        "success": True,
        "uid": int(uid),
        "file_id": int(file_id),
        "mapper_id": int(mapper_id),
        "position": int(position),
    }))


def external_base():
    host = os.environ.get("HTTP_HOST") or "127.0.0.1:5000"
    scheme = os.environ.get("REQUEST_SCHEME") or ("https" if os.environ.get("HTTPS") == "on" else "http")
    return scheme, host


def tokenized_external_url(source_url, playlist_url, sid, token):
    parsed = urllib.parse.urlparse(urllib.parse.urljoin(playlist_url, source_url.strip()))
    query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
    if sid and "_sid" not in query:
        query["_sid"] = [sid]
    if token and "SynoToken" not in query:
        query["SynoToken"] = [token]
    scheme, host = external_base()
    return urllib.parse.urlunparse((
        scheme,
        host,
        parsed.path,
        parsed.params,
        urllib.parse.urlencode(query, doseq=True),
        parsed.fragment,
    ))


def main():
    params = urllib.parse.parse_qs(os.environ.get("QUERY_STRING", ""), keep_blank_values=True)
    action = (params.get("action") or ["stream"])[0]
    if action == "watch_status":
        handle_watch_status(params)
        return

    sid = (params.get("sid") or params.get("_sid") or [""])[0]
    token = (params.get("token") or params.get("SynoToken") or [""])[0]
    file_id = (params.get("file_id") or params.get("id") or [""])[0]
    profile = (params.get("profile") or ["sd_high"])[0]
    audio_track = int((params.get("audio_track") or ["-1"])[0])

    if not sid or not file_id:
        respond("400 Bad Request", "text/plain; charset=utf-8", "missing sid or file_id")
        return

    auth = {
        "api": "SYNO.VideoStation2.Streaming",
        "version": "1",
        "method": "open",
        "_sid": sid,
    }
    if token:
        auth["SynoToken"] = token

    id_value = int(file_id) if file_id.isdigit() else file_id
    file_variants = [
        {"id": id_value, "path": ""},
        [{"id": id_value, "path": ""}],
        {"id": file_id, "path": ""},
        [id_value],
    ]
    hls_remux_base = {}
    hls_base = {"force_open_vte": False, "profile": profile}
    hls_force_base = {"force_open_vte": True, "profile": profile}
    if audio_track != -9999:
        hls_remux_base["audio_track"] = audio_track
        hls_base["audio_track"] = audio_track
        hls_force_base["audio_track"] = audio_track
    open_variants = [
        ("hls_remux", hls_remux_base),
        ("hls_remux", {**hls_remux_base, "device": "chromecast"}),
        ("hls", hls_base),
        ("hls", hls_force_base),
        ("hls", {**hls_force_base, "device": "chromecast"}),
    ]
    opened = None
    last_opened = None
    for open_key, open_value in open_variants:
        for file_value in file_variants:
            body = {
                open_key: json.dumps(open_value, separators=(",", ":")),
                "file": json.dumps(file_value, separators=(",", ":")),
            }
            candidate = request_json(webapi_url(auth), body)
            last_opened = candidate
            if candidate.get("success") and candidate.get("data", {}).get("stream_id"):
                opened = candidate
                break
        if opened:
            break
    if not opened.get("success") or not opened.get("data", {}).get("stream_id"):
        respond("502 Bad Gateway", "application/json; charset=utf-8", json.dumps(last_opened))
        return

    stream_id = str(opened["data"]["stream_id"])
    fmt = str(opened.get("data", {}).get("format") or "hls")
    stream_params = {
        "api": "SYNO.VideoStation2.Streaming",
        "version": "1",
        "method": "stream",
        "stream_id": stream_id,
        "format": fmt,
        "_sid": sid,
    }
    if token:
        stream_params["SynoToken"] = token
    playlist_url = webapi_url(stream_params)
    playlist = request_text(playlist_url)
    if not playlist.lstrip().startswith("#EXTM3U"):
        respond("502 Bad Gateway", "text/plain; charset=utf-8", playlist)
        return

    lines = []
    for line in playlist.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            lines.append(line)
        else:
            lines.append(tokenized_external_url(stripped, playlist_url, sid, token))
    respond("200 OK", "application/vnd.apple.mpegurl", "\n".join(lines) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        respond("500 Internal Server Error", "text/plain; charset=utf-8", traceback.format_exc())
