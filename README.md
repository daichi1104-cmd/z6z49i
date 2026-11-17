# 6弦ベースのためのジャズ理論（仮題）

6弦ベース（B-E-A-D-G-C）を基準にした、中級〜上級向けのジャズ理論書の原稿です。Kindle（固定レイアウト）での出版を予定しています。

- 企画・目次・進捗：[PLAN.md](PLAN.md)
- 原稿：`chapters/`（Markdown。譜例は LilyPond のコードとして本文に書く）
- 最新の PDF：[build/book.pdf](build/book.pdf)

## ビルド方法

必要なもの：LilyPond 2.24、Pandoc、Python 3、WeasyPrint、IPA フォント（明朝・ゴシック）

```sh
sudo apt-get install -y lilypond pandoc fonts-ipafont-mincho fonts-ipafont-gothic
pip install weasyprint
python3 build.py   # → build/book.pdf
```

譜例の書き方：

````md
```lilypond {#ex1-1 caption="譜例1-1　キャプション"}
\new Staff { \clef bass c4\4 d\3 e\3 f\3 }
```
````

第9章（練習曲）は `python3 tools/gen_etudes.py` で生成する（音は実音で入力し、弦の割り当てと押さえられるかを自動で検査）。

記譜は実音の 1オクターブ上。`\1`〜`\6` は弦番号（①=C弦 … ⑥=B弦）。
