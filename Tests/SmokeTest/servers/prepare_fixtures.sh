#!/usr/bin/env bash
# Assemble the directory trees the smoke-test servers expose.
#
# Usage: prepare_fixtures.sh <out-root>
#
#   <out-root>/dav/             WebDAV share (Basic auth, port 8080)
#     Movies/sample.mkv            with sample.zh.ass + sample.en.srt sidecars
#     Movies/sample.mp4
#     shows/S01/episode-01.mp4
#     中文 目录/示例 视频.mp4
#   <out-root>/hls/                plain HTTP, no auth (port 8081)
#     sample.m3u8, seg_*.ts
#   <out-root>/smb/                SMB share MEDIA (port 1445)
#     Movies/sample.mkv, Movies/sample.mp4, sample.zh.ass, sample.en.srt
set -euo pipefail

root="${1:?usage: prepare_fixtures.sh <out-root>}"
media="$(cd "$(dirname "$0")/../media" && pwd)"

rm -rf "$root"
mkdir -p "$root/dav/Movies" "$root/dav/shows/S01" "$root/dav/中文 目录" \
         "$root/hls" "$root/smb/Movies"

cp "$media/sample.mp4" "$media/sample.mkv" "$media/sample.zh.ass" "$media/sample.en.srt" "$root/dav/Movies/"
cp "$media/sample.mp4" "$root/dav/shows/S01/episode-01.mp4"
cp "$media/sample.mp4" "$root/dav/中文 目录/示例 视频.mp4"
cp "$media/hls/"* "$root/hls/"
cp "$media/sample.mp4" "$media/sample.mkv" "$media/sample.zh.ass" "$media/sample.en.srt" "$root/smb/Movies/"

echo "fixtures ready under $root"
find "$root" -type f | sed "s|$root/||" | sort
