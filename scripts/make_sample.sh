#!/bin/bash
# 生成示例学习素材：用 macOS say 逐句合成音频，精确计算每句时间轴生成 SRT。
# 依赖：macOS say / ffmpeg / ffprobe
# 用法：bash scripts/make_sample.sh  → 产出 Samples/learning_english.m4a + .srt
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Samples
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

VOICE="${VOICE:-Samantha}"
SENTENCES=(
"Today we are going to talk about how to learn English effectively."
"Many students study for years, but they still cannot speak with confidence."
"The secret is not talent. The secret is perseverance and daily practice."
"First, choose material that you genuinely enjoy, such as a podcast or a TV show."
"Listen to one short sentence, pause the audio, and then repeat it aloud."
"This method is called shadowing, and it trains your ears and your mouth together."
"When you meet a new word, do not memorize it alone. Learn it inside the sentence."
"Little by little, your listening and your pronunciation will improve."
"Remember, progress comes from consistency, not from intensity."
"Start today, keep going, and enjoy the journey of learning English."
)

# 逐句合成并测量时长
CONCAT_LIST="$TMP/concat.txt"
: > "$CONCAT_LIST"
OFFSET=0
INDEX=1
: > "$OUT/learning_english.srt"

fmt_time() {
  # 秒(浮点) -> HH:MM:SS,mmm
  python3 - "$1" <<'PY'
import sys
t = float(sys.argv[1])
h = int(t // 3600); m = int(t % 3600 // 60); s = int(t % 60)
ms = int(round((t - int(t)) * 1000))
if ms == 1000: s += 1; ms = 0
print(f"{h:02d}:{m:02d}:{s:02d},{ms:03d}")
PY
}

for SENT in "${SENTENCES[@]}"; do
  say -v "$VOICE" -o "$TMP/s$INDEX.aiff" "$SENT"
  ffmpeg -y -loglevel error -i "$TMP/s$INDEX.aiff" -ar 44100 -ac 1 "$TMP/s$INDEX.wav"
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/s$INDEX.wav")
  # 句间加 0.6s 静音
  START=$OFFSET
  END=$(python3 -c "print($OFFSET + $DUR)")
  {
    echo "$INDEX"
    echo "$(fmt_time "$START") --> $(fmt_time "$END")"
    echo "$SENT"
    echo ""
  } >> "$OUT/learning_english.srt"
  echo "file '$TMP/s$INDEX.wav'" >> "$CONCAT_LIST"
  ffmpeg -y -loglevel error -f lavfi -i anullsrc=r=44100:cl=mono -t 0.6 "$TMP/gap$INDEX.wav"
  echo "file '$TMP/gap$INDEX.wav'" >> "$CONCAT_LIST"
  OFFSET=$(python3 -c "print($END + 0.6)")
  INDEX=$((INDEX + 1))
done

ffmpeg -y -loglevel error -f concat -safe 0 -i "$CONCAT_LIST" -c:a aac -b:a 128k "$OUT/learning_english.m4a"
echo "✅ 生成完成："
ls -la "$OUT"
