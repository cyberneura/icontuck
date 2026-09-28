# Icontuck — エージェント向けメモ

ビルド・使い方・リリース手順は README.md を参照。public リポジトリなので README・UI 文字列・コードコメントは英語で書く。

## サードパーティーのライセンス表示

- `THIRD-PARTY-NOTICES.txt` と `Icontuck/ThirdPartyNotices.swift` は `scripts/generate-third-party-notices.sh` の生成物。手で編集しない。
- 依存を足す・上げる時は `./scripts/generate-third-party-notices.sh` を流し直してコミットする。PR の Test ワークフローが `--check` で古さを検出する。
- 現在は Apple のシステムフレームワークしか使っておらず、同梱するサードパーティーのライブラリは無い。Swift Package を足すとスクリプトはエラーで止まるので、`Package.resolved` の pins から各パッケージの LICENSE を載せるようにスクリプトを拡張すること (resolve は macOS 前提でよい)。GPL / LGPL / AGPL 系のライセンスの依存は入れる前に人間に確認する。
- アプリ内では、ステータスアイテムの右クリックメニューの "Third-Party Licenses…" で表示する (`AppDelegate.showThirdPartyLicenses`)。

## その他

- `Icontuck.xcodeproj/project.pbxproj` はファイル同期グループではない。Swift ファイルを足す時は PBXBuildFile / PBXFileReference / グループの children / Sources ビルドフェーズの 4 か所に登録する。
- Swift はこのリポジトリの PR の Test ワークフロー (macOS、署名なし Debug ビルド) でコンパイルを確認する。
- バージョンは `./scripts/release.sh [patch|minor|major]` だけが上げる (main に直接 push して Release ワークフローを起動する)。PR では `MARKETING_VERSION` を上げない。
