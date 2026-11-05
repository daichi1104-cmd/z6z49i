# ジャンプ・アドベンチャー（Roblox アスレチック）

全12ステージの Roblox 用アスレチック（Obby）ゲームです。[Rojo](https://rojo.space/) 形式で作っています。

## ステージ

| # | 内容 |
|---|------|
| 1 | 階段ジャンプ（やさしい） |
| 2 | 細い一本橋 |
| 3 | 溶岩の上の飛び石 |
| 4 | 動く足場 |
| 5 | はしご（トラス）登り |
| 6 | 高低差のある小さな足場 |
| 7 | 回転バーを飛び越える |
| 8 | 乗ると消えるガラスの床 |
| 9 | 溶岩の飛び石 → さらに細い橋 |
| 10 | 動く足場の乗り継ぎ |
| 11 | 高いはしご → 小さな足場ジャンプ |
| 12 | 回転バー2連（逆回転） → ゴール |

- チェックポイントに乗ると、やられてもそこから再開できます
- 進んだステージは DataStore に保存され、次に遊ぶときも続きから始まります
- 画面左の「↩ 戻る」でチェックポイントへ戻り、「最初から」を2回押すとスタートに戻ります

## ファイル構成

```
default.project.json        Rojo のプロジェクト設定
src/shared/Config.luau      ゲーム名・ステージ数などの設定
src/server/CourseBuilder.luau  コースを組み立てる処理（障害物の種類・ステージ構成）
src/server/Main.server.luau    チェックポイント・即死・消える床・保存
src/client/StageUI.client.luau 画面表示（ステージ数、ボタン、お知らせ）
```

## ビルド

```sh
mkdir -p build
rojo build -o build/ObbyAdventure.rbxl
```

## アップロード（Open Cloud）

```sh
curl -X POST \
  "https://apis.roblox.com/universes/v1/<UNIVERSE_ID>/places/<PLACE_ID>/versions?versionType=Published" \
  -H "x-api-key: <API_KEY>" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @build/ObbyAdventure.rbxl
```

API キーには、対象の体験に対する `universe-places` の **write** 権限が必要です。
