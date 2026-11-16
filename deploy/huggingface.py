"""band2score の Web アプリを Hugging Face Spaces（Docker）に置く。

    pip install huggingface_hub
    HF_TOKEN=hf_xxx python deploy/huggingface.py あなたのユーザー名/band2score

- Space が無ければ作り（Docker タイプ・公開）、あればファイルを最新にする
- Space 用の README（先頭に Space の設定を書いたもの）はこのスクリプトが作る
- パスワード（BAND2SCORE_PASSWORD）は、Space の Settings → Variables and secrets で
  「Secret」として自分で設定する（このスクリプトは扱わない）
- --dry-run を付けると、アップロードせずに置くファイルの一覧だけ表示する
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ["Dockerfile", "requirements.txt", "band2score"]

SPACE_README = """---
title: band2score
emoji: 🎸
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
short_description: バンドの音源から楽器ごとの楽譜を自動で作る
---

# band2score

バンドの音源（mp3・m4a・wav など）から、楽器ごとの楽譜（MusicXML・MIDI）とコード表を自動で作る Web アプリです。
スマホのブラウザで開き、ホーム画面に追加して使えます。

ソース: https://github.com/{github}
"""


def stage(dest: Path, github: str) -> list[str]:
    for name in FILES:
        src = ROOT / name
        if src.is_dir():
            shutil.copytree(src, dest / name, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(src, dest / name)
    (dest / "README.md").write_text(SPACE_README.format(github=github), encoding="utf-8")
    return sorted(str(p.relative_to(dest)) for p in dest.rglob("*") if p.is_file())


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("space", nargs="?", default=None,
                   help="Space の名前（ユーザー名/スペース名）。省略するとトークンの持ち主/band2score")
    p.add_argument("--github", default="daichi1104-cmd/z6z49i", help="README に載せるソースの場所")
    p.add_argument("--private", action="store_true", help="非公開の Space にする（作るときだけ有効）")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    if a.dry_run and not a.space:
        a.space = "you/band2score"
    with tempfile.TemporaryDirectory() as tmp:
        files = stage(Path(tmp), a.github)
        print(f"{len(files)} 個のファイルを置きます:")
        for f in files:
            print("  ", f)
        if a.dry_run:
            return 0

        from huggingface_hub import HfApi

        api = HfApi(token=os.environ.get("HF_TOKEN"))
        if not a.space:
            a.space = f"{api.whoami()['name']}/band2score"
        print(f"Space: {a.space}")
        api.create_repo(a.space, repo_type="space", space_sdk="docker", private=a.private,
                        exist_ok=True)
        api.upload_folder(repo_id=a.space, repo_type="space", folder_path=tmp,
                          commit_message="Update band2score", delete_patterns=["band2score/**"])
    owner, name = a.space.split("/")
    print("\nアップロードしました。ビルドに 10〜20分ほどかかります。")
    print(f"  Space の画面: https://huggingface.co/spaces/{a.space}")
    print(f"  アプリの URL: https://{owner.lower()}-{name.lower().replace('_', '-')}.hf.space")
    print("パスワードは Space の Settings → Variables and secrets で BAND2SCORE_PASSWORD（Secret）に設定してください。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
