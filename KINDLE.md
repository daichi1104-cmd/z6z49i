# Kindle 版の作り方と確認手順

調べた日：2026-11-17。KDP の仕様はよく変わります。入稿の直前に、KDP ヘルプの最新版をもう一度確かめてください。

## 1. 先に知っておくこと：日本語の本は Print Replica にできない

当初は「A5 判の PDF を Kindle Create の Print Replica で読み込む」予定でした。ところが KDP のヘルプには、**Kindle Create は日本語のリフロー型の本と Print Replica の本に対応していない**と、複数のページに書かれています（日本語に対応しているのはマンガ形式だけ）。

- 「Prepare Print Replica Books with Kindle Create」：Print Replica books are not supported in Japanese.
- 「What file formats are supported for eBook manuscripts?」：Kindle Create does not support reflowable or print-replica books in Japanese. (The manga format is available in Japanese.)

本書は日本語の本なので、この方法は使えません。

マンガ形式でも PDF は読み込めます。ただ、本書はマンガではないうえ、マンガ向けの「ガイド付きビュー」は本書の内容に合いません。そのため、この方法も使わないことにします。

## 2. 代わりの方法：固定レイアウトの EPUB を自分で作り、KDP に直接アップロードする

KDP では、固定レイアウトの本を **EPUB または KPF** で入稿できます（MOBI の受付は 2025年3月に終了）。本書では、次の流れで作ります。

```
build/book.pdf（A5判、組版済み）
   └─ 各ページを高解像度の画像にする
        └─ 1ページ＝1つの XHTML に画像を1枚ずつ置いた、固定レイアウトの EPUB にまとめる
             └─ Kindle Previewer 4 で確認
                  └─ KDP に EPUB と表紙（build/cover.jpg）をアップロード
```

- この方法なら、PDF と同じ見た目（譜例・表・改ページ）をそのまま保てます。
- 欠点：本文は画像になるので、文字の選択・検索・辞書・ハイライト・文字サイズの変更はできません。どれも Print Replica でも同じようにできなかったことなので、当初の予定から失うものはありません。
- 文字は小さくなりますが、読者がピンチで拡大できます。

### EPUB の仕様（Amazon Kindle パブリッシング・ガイドライン 2026.3 による）

| 項目 | 指定 |
|---|---|
| レイアウト | OPF に `<meta property="rendition:layout">pre-paginated</meta>` と `<meta name="fixed-layout" content="true"/>` |
| 元の解像度 | `<meta name="original-resolution" content="幅x高さ"/>`（必須。ページ画像と同じ縦横比にする） |
| 向き | `<meta name="orientation-lock" content="portrait"/>`（推奨） |
| ページ送り | 左から右（横書きの本）。`primary-writing-mode` は指定しない（既定値が horizontal-lr） |
| ページ画像 | JPEG。2倍に拡大してもぼやけない解像度にする。A5 の縦横比で **1762×2500 px**、画質88（1ページ300KB前後、全体で約27MB） |
| 目次 | EPUB の nav（目次）に、章と節へのリンクを入れる。Kindle のメニューの「目次」から各章へ飛べるようにする |
| リンク | 入れ子になったリンク（`<a>` の中の `<a>`）は禁止（販売停止の対象になる） |

画面との相性：Kindle のガイドラインは 1920×1200（縦横比1.6）の画面を基準にしています。A5 は縦横比が 1.414 なので、端末によっては上下に余白が出ます。固定レイアウトでは普通のことで、問題ありません。

### EPUB の作り方

```sh
python3 build.py            # → build/book.pdf
node tools/gen_cover.js     # → build/cover.jpg
python3 tools/make_epub.py  # → build/book.epub
```

- `tools/make_epub.py` は、PDF の各ページを JPEG にし、1ページ＝1つの XHTML に置いて EPUB にまとめます。先頭には表紙のページが入ります。
- 目次（Kindle のメニューに出る目次）は、PDF のしおりから章と節を取って作ります。「はじめに」の小見出しは載せず、最後に「奥付」を加えます。
- 書名・著者名（EPUB のメタデータ）は、スクリプト冒頭の `META` で指定します。

## 3. 確認の手順

### 3-1. 準備（著者のパソコンで行う）

1. **Kindle Previewer 4** を Amazon の公式サイトからダウンロードして入れる（Windows と Mac に対応）。
2. このリポジトリの最新版から、`build/book.epub` と `build/cover.jpg` を取り出す。

### 3-2. Kindle Previewer 4 で開く

1. Kindle Previewer を起動し、「ファイル」→「本を開く」で `book.epub` を選ぶ。
2. 変換が終わったら、**エラーと警告が 0 件**かどうかを確かめる。エラーや警告が残っていると販売できません。出た場合は、メッセージをそのままこちらに伝えてください。
3. 左上の端末の切り替えで、**タブレット**・**電子書籍リーダー（Kindle Paperwhite など）**・**スマートフォン**の3つを見る。

### 3-3. チェックリスト

各端末の表示で、次の点を見てください。

**全体**
- [ ] 表紙が正しく出る
- [ ] ページの順番が正しく、左から右へめくれる
- [ ] ページの端が切れていない（ページ番号まで見える）
- [ ] 空白のページが紛れ込んでいない

**読みやすさ**
- [ ] 電子書籍リーダー（白黒）で、本文が拡大しなくても何とか読める
- [ ] 拡大したとき、譜例の音符・弦番号（①〜⑥）・臨時記号がつぶれず、はっきり見える
- [ ] 表の罫線と、表の中の小さな文字が読める
- [ ] グレーの背景（囲み記事・表の見出し）が、白黒の端末でも文字と区別できる

**目次とリンク**
- [ ] Kindle のメニューの「目次」から、各章・各節へ飛べる
- [ ] 本の中の目次ページの項目をタップすると、その章へ飛べる（飛べなくても販売はできる。§4 を参照）

**重点的に見るページ**
- [ ] 扉・はじめに・目次・奥付
- [ ] 第1章の開放弦の表と、譜例1-1
- [ ] 2段譜の譜例（第5・6・8章、練習曲5・8 など）
- [ ] 第9章の練習曲のうち、長いもの（1ページに譜例が何段も入るページ）
- [ ] 付録B（スケールの運指）と付録C（用語集の長い表）

### 3-4. 実機で確かめる（できれば）

Kindle Previewer の表示と実機の見え方は、少し違うことがあります。KDP に下書きとしてアップロードし、オンラインのプレビューで見るか、手元の Kindle 端末やスマートフォンの Kindle アプリで、特に譜例の読みやすさを確かめてください。

## 4. まだ決めていないこと・気になること

- **本文の中の目次からのリンク**：画像だけのページでは、目次ページの各行をタップして飛ぶことはできません。透明なリンクを画像の上に重ねれば飛べるようになります（ガイドライン 12.5.5 の `position:absolute`）。手間がかかるので、まずは「Kindle のメニューの目次」だけで済ませ、必要なら後から足す予定です。
- **ページ番号**：紙面のページ番号（第1章＝1ページ）と Kindle の位置表示は一致しません。本文で「○ページ参照」と書かずに「第○章 ○.○節」と書いているので、問題は起きません。
- **出版するときの KDP の設定**：言語は「日本語」にする。AI 使用の申告は「はい」にし、本文と画像の両方を申告する。

## 参考にした資料

- Amazon Kindle パブリッシング・ガイドライン バージョン 2026.3（日本語版 PDF）：2.1.1 Kindle Create、2.2.1 Kindle Previewer、12.5.3 全画面用コンテンツを最適化する、13.1 メタデータのガイドライン、14 ポップアップなしの固定レイアウト本を作成する
- KDP ヘルプ：Prepare Print Replica Books with Kindle Create／What file formats are supported for eBook manuscripts?／Getting Started with Kindle Create／電子書籍の MOBI サポートに関してよく寄せられる質問
