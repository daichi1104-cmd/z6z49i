# band2score

バンドの音源（mp3 / wav など）を、**楽器ごとの楽譜**に自動で変換するツールです。

```
song.mp3
  │
  ├─ [1] 音源分離（Demucs）        … ボーカル / ギター / ベース / ピアノ / ドラム / その他 に分ける
  ├─ [2] テンポ・拍の推定（librosa）
  ├─ [3] 採譜
  │     ├ 音程のある楽器 → basic-pitch（Spotify の AI 採譜モデル）
  │     └ ドラム        → 帯域ごとの打点検出でキック / スネア / ハイハットに分ける
  └─ [4] 楽譜を作る（music21）    … リズムを 16分音符単位にそろえ、調を推定して MusicXML に
```

## 出力されるもの

`output/<曲名>/` に次のファイルができます。

| ファイル | 内容 |
|---|---|
| `<曲名>.musicxml` | 楽譜。**MuseScore**（無料）で開くと表示・編集・印刷・PDF化ができます |
| `<曲名>.mid` | 採譜結果の MIDI（DAW で鳴らして確認するとき用） |
| `<曲名>.pdf` | MuseScore が入っていれば自動で作られます |
| `stems/*.wav` | 分離した楽器ごとの音声 |

## インストール

Python 3.10 以上が必要です。

```bash
python -m venv .venv
source .venv/bin/activate          # Windows は .venv\Scripts\activate
pip install -r requirements.txt
pip install --no-deps basic-pitch  # basic-pitch は依存関係が古いので別に入れる
```

- 初回実行時に Demucs のモデル（約 80MB）が自動でダウンロードされます。
- PDF も欲しい場合は [MuseScore](https://musescore.org/) を入れ、`mscore` か `musescore` コマンドが使えるようにしてください。
- NVIDIA の GPU があれば音源分離が速くなります（無くても CPU で動きます。3〜4分の曲で数分かかります）。

## 使い方

```bash
python -m band2score song.mp3
```

主なオプション:

| オプション | 説明 |
|---|---|
| `-o 出力先` | 出力フォルダを指定 |
| `--only bass drums` | 指定したパートだけ楽譜にする |
| `--tempo 128` | テンポがずれるときに BPM を手で指定 |
| `--grid 8` | リズムを 8分音符単位でそろえる（細かすぎる楽譜になるとき） |
| `--model htdemucs` | 4パート（vocals / drums / bass / other）の分離モデルを使う |
| `--stems-dir フォルダ` | 分離済みの `vocals.wav` などを使い、分離を省略する |

## 試してみる（テスト音源）

合成音で作ったテスト用のバンド音源（120 BPM・8小節）で動作を確認できます。

```bash
python tests/make_test_song.py test_data
python -m band2score test_data/test_band.wav                              # 分離から全部
python -m band2score test_data/test_band.wav --stems-dir test_data/stems  # 分離を省略
```

`--stems-dir` を使った場合の、正解 MIDI と比べた精度（音程と開始時刻 ±50ms が合っている割合）:

| パート | 正しく取れた音 | 余分に出た音 |
|---|---|---|
| メロディ | 97% | 3% |
| ベース | 97% | 16%（倍音を拾った誤検出） |
| ピアノ（和音） | 100% | 20%（倍音を拾った誤検出） |
| ドラム | 98% | 0% |

## できること・できないこと

自動採譜は完璧ではありません。**下書きを自動で作り、MuseScore で手直しする**使い方を想定しています。

- ◎ ベース・ボーカルのような単音のパートはかなり正確です
- ○ ピアノ・ギターの和音は取れますが、倍音（1オクターブ上などの音）を拾った余分な音が混ざります
- ○ ドラムはキック・スネア・ハイハットの 3種類だけを区別します（タム・シンバルは区別しません）
- △ テンポが途中で変わる曲、4/4拍子以外の曲にはまだ対応していません
- △ 分離がうまくいかない楽器（シンセ、ストリングスなど）は `Other` パートにまとめて入ります

## テスト

```bash
pip install -r requirements-dev.txt
pytest
```

## ファイル構成

```
band2score/
  cli.py         コマンドの入口・処理の流れ
  separate.py    音源分離（Demucs）
  transcribe.py  テンポ推定・採譜（basic-pitch / ドラム検出）
  score.py       楽譜（MusicXML）と MIDI の生成
  models.py      データ型と楽器ごとの設定
tests/
  make_test_song.py  テスト音源の生成
  test_pipeline.py   テスト
```
