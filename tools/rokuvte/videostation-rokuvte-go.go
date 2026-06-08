package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

func respond(status string, contentType string, body []byte) {
	fmt.Printf("Status: %s\r\n", status)
	fmt.Printf("Content-Type: %s\r\n", contentType)
	fmt.Print("Cache-Control: no-store\r\n")
	fmt.Printf("Content-Length: %d\r\n", len(body))
	fmt.Print("\r\n")
	os.Stdout.Write(body)
}

func textStatus(status string, msg string) {
	respond(status, "text/plain; charset=utf-8", []byte(msg))
}

func webapiURL(values url.Values) string {
	return "http://127.0.0.1:5000/webapi/entry.cgi?" + values.Encode()
}

func httpPostForm(target string, values url.Values) ([]byte, error) {
	client := &http.Client{Timeout: 45 * time.Second}
	req, err := http.NewRequest("POST", target, strings.NewReader(values.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	return io.ReadAll(res.Body)
}

func httpGetText(target string) ([]byte, error) {
	client := &http.Client{Timeout: 45 * time.Second}
	res, err := client.Get(target)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	return io.ReadAll(res.Body)
}

func externalBase() (string, string) {
	host := os.Getenv("HTTP_HOST")
	if host == "" {
		host = "127.0.0.1:5000"
	}
	scheme := os.Getenv("REQUEST_SCHEME")
	if scheme == "" {
		if os.Getenv("HTTPS") == "on" {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}
	return scheme, host
}

func tokenizedExternalURL(source string, playlistURL string, sid string, token string) string {
	base, err := url.Parse(playlistURL)
	if err != nil {
		return strings.TrimSpace(source)
	}
	ref, err := url.Parse(strings.TrimSpace(source))
	if err != nil {
		return strings.TrimSpace(source)
	}
	merged := base.ResolveReference(ref)
	q := merged.Query()
	if sid != "" && q.Get("_sid") == "" {
		q.Set("_sid", sid)
	}
	if token != "" && q.Get("SynoToken") == "" {
		q.Set("SynoToken", token)
	}
	scheme, host := externalBase()
	merged.Scheme = scheme
	merged.Host = host
	merged.RawQuery = q.Encode()
	return merged.String()
}

func main() {
	params, _ := url.ParseQuery(os.Getenv("QUERY_STRING"))
	sid := params.Get("sid")
	if sid == "" {
		sid = params.Get("_sid")
	}
	token := params.Get("token")
	if token == "" {
		token = params.Get("SynoToken")
	}
	fileID := params.Get("file_id")
	if fileID == "" {
		fileID = params.Get("id")
	}
	profile := params.Get("profile")
	if profile == "" {
		profile = "sd_high"
	}
	audioTrack := params.Get("audio_track")
	if audioTrack == "" {
		audioTrack = "-1"
	}
	audioTrackInt, err := strconv.Atoi(audioTrack)
	if err != nil {
		audioTrackInt = -1
	}
	if sid == "" || fileID == "" {
		textStatus("400 Bad Request", "missing sid or file_id")
		return
	}

	auth := url.Values{}
	auth.Set("api", "SYNO.VideoStation2.Streaming")
	auth.Set("version", "1")
	auth.Set("method", "open")
	auth.Set("_sid", sid)
	if token != "" {
		auth.Set("SynoToken", token)
	}
	openURL := webapiURL(auth)

	fileValue := map[string]any{"id": fileID, "path": ""}
	if idNum, err := strconv.Atoi(fileID); err == nil {
		fileValue["id"] = idNum
	}
	hlsValue := map[string]any{"force_open_vte": false, "profile": profile, "audio_track": audioTrackInt}
	fileJSON, _ := json.Marshal(fileValue)
	hlsJSON, _ := json.Marshal(hlsValue)
	body := url.Values{}
	body.Set("hls", string(hlsJSON))
	body.Set("file", string(fileJSON))

	openBody, err := httpPostForm(openURL, body)
	if err != nil {
		textStatus("502 Bad Gateway", err.Error())
		return
	}
	var opened map[string]any
	if err := json.Unmarshal(openBody, &opened); err != nil {
		respond("502 Bad Gateway", "application/json; charset=utf-8", openBody)
		return
	}
	if opened["success"] != true {
		respond("502 Bad Gateway", "application/json; charset=utf-8", openBody)
		return
	}
	data, _ := opened["data"].(map[string]any)
	streamID, _ := data["stream_id"].(string)
	if streamID == "" {
		respond("502 Bad Gateway", "application/json; charset=utf-8", openBody)
		return
	}
	format, _ := data["format"].(string)
	if format == "" {
		format = "hls"
	}

	streamParams := url.Values{}
	streamParams.Set("api", "SYNO.VideoStation2.Streaming")
	streamParams.Set("version", "1")
	streamParams.Set("method", "stream")
	streamParams.Set("stream_id", streamID)
	streamParams.Set("format", format)
	streamParams.Set("_sid", sid)
	if token != "" {
		streamParams.Set("SynoToken", token)
	}
	playlistURL := webapiURL(streamParams)
	playlistBody, err := httpGetText(playlistURL)
	if err != nil {
		textStatus("502 Bad Gateway", err.Error())
		return
	}
	if !bytes.HasPrefix(bytes.TrimSpace(playlistBody), []byte("#EXTM3U")) {
		respond("502 Bad Gateway", "text/plain; charset=utf-8", playlistBody)
		return
	}

	lines := strings.Split(strings.ReplaceAll(string(playlistBody), "\r\n", "\n"), "\n")
	for i, line := range lines {
		stripped := strings.TrimSpace(line)
		if stripped == "" || strings.HasPrefix(stripped, "#") {
			continue
		}
		lines[i] = tokenizedExternalURL(stripped, playlistURL, sid, token)
	}
	respond("200 OK", "application/vnd.apple.mpegurl", []byte(strings.Join(lines, "\n")))
}
