# 補助金コンパス

国・自治体の補助金を検索・相談できるWebアプリ（[Claude Artifact](https://claude.ai/code/artifact/d4f67270-f992-4e3a-81cb-ee9adb027b61)として公開）。

## データソース

- `data/jgrants_national.json` — デジタル庁「jGrants」公開APIから取得した国・自治体掲載の補助金データ（手動更新）
- `data/local_gov.json` — 独立行政法人中小企業基盤整備機構「支援情報ヘッドライン」RSSから日次で自動収集・蓄積している市区町村独自の補助金データ

## 構成

- `app_template.html` — アプリ本体のテンプレート（`/*__DATA__*/` にデータを埋め込んでビルド）
- `build.py` — RSSを取得して `data/local_gov.json` に新着分を追記し、`index.html` を再ビルドするスクリプト（スケジュール実行されるクラウドエージェントが毎日実行）
- `index.html` — ビルド済みの最終成果物（Claude Artifactとして再公開される）

## 自動更新

毎日、スケジュール済みのクラウドエージェントが `python3 build.py` を実行し、変更を commit・push した上でArtifactを再公開しています。
