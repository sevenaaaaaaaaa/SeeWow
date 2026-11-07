#!/usr/bin/env bash
# 生成 QA 用的样片（跑一次即可；产物已在 qa/T-01/fixtures/ 里，体积都很小）。
#   clip-sdr.mp4       2s SDR，用于探针日志与「不误判 HDR」
#   clip-hdr10.mp4     3s HEVC 10-bit、bt2020 / PQ / HDR10 元数据，用于 HDR 探针（需要看画面时用）
#   clip-lifecycle.mp4 14s，够长到跑完 SELFTEST 的 全屏进→全屏出→关闭 三步
set -euo pipefail
cd "$(dirname "$0")"
ffmpeg -v error -f lavfi -i 'testsrc=size=320x180:rate=10' -t 2  -pix_fmt yuv420p -y clip-sdr.mp4
ffmpeg -v error -f lavfi -i 'testsrc2=size=320x180:rate=10' -t 3 -c:v libx265 -pix_fmt yuv420p10le \
  -x265-params 'colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400' \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -tag:v hvc1 -y clip-hdr10.mp4
ffmpeg -v error -f lavfi -i 'testsrc=size=320x180:rate=10' -t 14 -pix_fmt yuv420p -y clip-lifecycle.mp4
ls -la
