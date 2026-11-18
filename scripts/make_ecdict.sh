#!/bin/bash
# 构建内嵌离线英汉词典：ECDICT 全量 SQLite → 常用词过滤 → 精简 SQLite
# 数据来源：https://github.com/skywind3000/ecdict （MIT License）
# 下载通道：hf-mirror 数据集镜像（快）→ GitHub API blob（慢，兜底）
# 用法：bash scripts/make_ecdict.sh
# 产出：Packages/VocabularyKit/Sources/VocabularyKit/Resources/ecdict.sqlite
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Packages/VocabularyKit/Sources/VocabularyKit/Resources/ecdict.sqlite"
SRC=".cache/ecdict-full.sqlite"
HF_URL="https://hf-mirror.com/datasets/iamzhangship/fluency-ecdict-offline/resolve/main/ecdict-ecdict-bc015ed2-v1.zip"

mkdir -p .cache "$(dirname "$OUT")"

if [ ! -f "$SRC" ]; then
  echo "下载 ECDICT 全量数据（约 52MB，仅首次）…"
  if curl -sL --retry 3 "$HF_URL" -o .cache/ecdict-hf.zip; then
    unzip -o -q .cache/ecdict-hf.zip -d .cache/
    mv .cache/ecdict.sqlite "$SRC"
    rm -f .cache/ecdict-hf.zip
  else
    echo "hf-mirror 失败，回退 GitHub API（较慢）…"
    SHA=$(curl -s --retry 3 "https://api.github.com/repos/skywind3000/ecdict/contents/ecdict.csv" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")
    curl -sL --retry 5 -H "Accept: application/vnd.github.raw" \
      "https://api.github.com/repos/skywind3000/ecdict/git/blobs/$SHA" -o .cache/ecdict.csv
    python3 - .cache/ecdict.csv "$SRC" <<'PY'
import csv, sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(dst)
conn.execute("""CREATE TABLE entries(word TEXT PRIMARY KEY, phonetic TEXT, translation TEXT,
    definition TEXT, pos TEXT, collins INTEGER, oxford INTEGER, tag TEXT, bnc INTEGER, frq INTEGER, exchange TEXT)""")
with open(src, newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        w = (r.get("word") or "").strip().lower()
        if not w: continue
        def num(k):
            try: return int(r.get(k) or 0)
            except ValueError: return 0
        conn.execute("INSERT OR IGNORE INTO entries VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (w, r.get("phonetic") or "", r.get("translation") or "", r.get("definition") or "",
             r.get("pos") or "", num("collins"), num("oxford"), r.get("tag") or "",
             num("bnc"), num("frq"), r.get("exchange") or ""))
conn.commit(); conn.close()
PY
  fi
fi

rm -f "$OUT"
sqlite3 "$OUT" <<SQL
ATTACH '$SRC' AS src;
CREATE TABLE dict(word TEXT PRIMARY KEY, phonetic TEXT, translation TEXT,
                  definition TEXT, pos TEXT, tag TEXT, exchange TEXT);
INSERT OR IGNORE INTO dict
SELECT lower(word), coalesce(phonetic,''), coalesce(translation,''),
       coalesce(definition,''), coalesce(pos,''), coalesce(tag,''), coalesce(exchange,'')
FROM src.entries
WHERE length(word) <= 40
  AND (coalesce(translation,'') != '' OR coalesce(definition,'') != '')
  AND (
    (' ' || coalesce(tag,'') || ' ') LIKE '% zk %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% gk %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% cet4 %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% cet6 %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% ky %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% toefl %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% ielts %'
    OR (' ' || coalesce(tag,'') || ' ') LIKE '% gre %'
    OR coalesce(collins,0) >= 3
    OR coalesce(oxford,0) = 1
    OR (coalesce(frq,0) BETWEEN 1 AND 20000)
    OR (coalesce(bnc,0) BETWEEN 1 AND 20000)
  );
VACUUM;
SQL

COUNT=$(sqlite3 "$OUT" "SELECT COUNT(*) FROM dict;")
SIZE=$(ls -la "$OUT" | awk '{printf "%.1f", $5/1e6}')
echo "✅ $COUNT 词条 → $OUT (${SIZE} MB)"
sqlite3 "$OUT" "SELECT word, substr(translation,1,40) FROM dict WHERE word='perseverance';"
