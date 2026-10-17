#!/usr/bin/env python3
"""Готовит CDN-папку к публикации и обновляет встроенные в приложение копии.

1. Для каждого ресурса в каждом конфиге считает sha256 и размер —
   приложение проверяет целостность скачанного файла и не берёт подменённый.
2. Проверяет бюджет: все ресурсы одного конфига ≤ 6 МБ (ТЗ, трек «Приколы»).
3. Копирует конфиги и ресурсы в ios/SberKidsFun/FunLayerDefaults — это
   конфиг «по умолчанию»: приложение работает и без сети, и при битом CDN.

    python3 tools/build_cdn.py
"""
import hashlib
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CDN = os.path.join(ROOT, "cdn", "fun-layer", "v1")
BUNDLE = os.path.join(ROOT, "ios", "SberKidsFun", "FunLayerDefaults")
BUDGET = 6 * 1024 * 1024
CONFIGS = ["config.json", "config-winter.json", "config-party.json", "config-off.json"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def main():
    os.makedirs(BUNDLE, exist_ok=True)
    used = set()
    for name in CONFIGS:
        path = os.path.join(CDN, name)
        cfg = json.load(open(path, encoding="utf-8"))
        total = 0
        for key, asset in (cfg.get("assets") or {}).items():
            file = os.path.join(CDN, asset["url"])
            asset["sha256"] = sha256(file)
            asset["bytes"] = os.path.getsize(file)
            total += asset["bytes"]
            used.add(asset["url"])
        assert total <= BUDGET, f"{name}: {total} B > 6 MB"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
            f.write("\n")
        shutil.copy(path, os.path.join(BUNDLE, name))
        print(f"{name:20s} ресурсов {len(cfg.get('assets') or {}):2d}, {total / 1024:7.1f} КБ")
    for rel in sorted(used):
        shutil.copy(os.path.join(CDN, rel), os.path.join(BUNDLE, os.path.basename(rel)))
    size = sum(os.path.getsize(os.path.join(BUNDLE, f)) for f in os.listdir(BUNDLE))
    print(f"встроено в приложение: {size / 1024:.1f} КБ (бюджет прироста сборки — 3 МБ)")


if __name__ == "__main__":
    main()
