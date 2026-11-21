#!/usr/bin/env python3
"""并行拉取 whisper.cpp 构建所需源码（GitHub API 文件清单 + jsDelivr CDN 下载）
用法：python3 scripts/fetch_whisper_src.py [tag]
产出：.cache/whisper-src/（供 build_whisper_xcframework.sh 使用）
"""
import json, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

TAG = sys.argv[1] if len(sys.argv) > 1 else "v1.9.5"
REPO = "ggml-org/whisper.cpp"
DEST = ".cache/whisper-src"
CDN = f"https://fastly.jsdelivr.net/gh/{REPO}@{TAG}/"

# 构建所需目录/文件（排除不用的 GPU 后端）
INCLUDE_PREFIXES = ("cmake/", "include/", "src/", "ggml/include/", "ggml/src/", "ggml/cmake/")
EXCLUDE_PARTS = ("ggml-cuda", "ggml-hip", "ggml-cann", "ggml-kompute", "ggml-vulkan",
                 "ggml-musa", "ggml-sycl", "ggml-zdnn", "ggml-opencl", "ggml-rpc",
                 "coreml", "ggml-zendnn")
ROOT_FILES = {"CMakeLists.txt", "ggml/CMakeLists.txt"}

def fetch(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "englishlab-build"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

print(f"获取 {TAG} 文件清单…")
tree = json.loads(fetch(f"https://api.github.com/repos/{REPO}/git/trees/{TAG}?recursive=1"))
paths = []
for item in tree["tree"]:
    if item["type"] != "blob":
        continue
    p = item["path"]
    if p in ROOT_FILES or (p.startswith(INCLUDE_PREFIXES) and not any(x in p for x in EXCLUDE_PARTS)):
        paths.append(p)
print(f"需下载 {len(paths)} 个文件")

os.makedirs(DEST, exist_ok=True)
failed = []

def download(p):
    dst = os.path.join(DEST, p)
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return p, True
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(3):
        try:
            data = fetch(CDN + p)
            with open(dst, "wb") as f:
                f.write(data)
            return p, True
        except Exception as e:
            err = str(e)
    return p, False

with ThreadPoolExecutor(max_workers=8) as pool:
    futures = {pool.submit(download, p): p for p in paths}
    done = 0
    for fut in as_completed(futures):
        p, ok = fut.result()
        done += 1
        if not ok:
            failed.append(p)
        if done % 20 == 0:
            print(f"  {done}/{len(paths)}…")

if failed:
    print("失败文件：", failed)
    sys.exit(1)
total = sum(os.path.getsize(os.path.join(DEST, p)) for p in paths)
print(f"✅ {len(paths)} 文件，{total/1e6:.1f} MB → {DEST}")
