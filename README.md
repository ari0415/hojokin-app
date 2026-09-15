# 補助金コンパス

国・自治体の補助金・助成金・給付金を検索・相談できるWebアプリ（[Claude Artifact](https://claude.ai/code/artifact/d4f67270-f992-4e3a-81cb-ee9adb027b61)として公開）。

## データソース

- `data/jgrants_national.json` — デジタル庁「jGrants」公開APIから取得した国・自治体掲載の補助金・助成金データ
- `data/local_gov.json` — 独立行政法人中小企業基盤整備機構「支援情報ヘッドライン」の検索結果ページから収集・蓄積している都道府県・市区町村独自の補助金・助成金・給付金・融資データ
- `data/curated.json` — 上記2つに載らない制度を手動で追加したデータ（例: 農水省委託事業で業界団体が事務局を務めるもの）

## 構成

- `app_template.html` — アプリ本体のテンプレート（`/*__DATA__*/` にデータを埋め込んでビルド）
- `build.py` — J-Net21を再取得して `data/local_gov.json` に新着分を追記し、`data/jgrants_national.json` と `data/curated.json` を合わせて `index.html` を再ビルドするスクリプト
- `index.html` — ビルド済みの最終成果物（Claude Artifactとして再公開される）

## 更新方法

クラウドでの自動実行は環境のネットワークポリシーで断念し、現在は手動運用。Claudeに「補助金アプリを更新して」と頼むと、ローカルでデータを再取得・再ビルド・push・Artifact再公開まで行う。
