# 補助金コンパス

国・自治体の補助金・助成金・給付金を検索・相談できるWebアプリ（[Claude Artifact](https://claude.ai/code/artifact/d4f67270-f992-4e3a-81cb-ee9adb027b61)として公開）。

## データソース

- `data/jgrants_national.json` — デジタル庁「jGrants」公開APIから取得した国・自治体掲載の補助金・助成金データ
- `data/local_gov.json` — 独立行政法人中小企業基盤整備機構「支援情報ヘッドライン」の検索結果ページから収集・蓄積している都道府県・市区町村独自の補助金・助成金・給付金・融資データ
- `data/curated.json` — 上記2つに載らない制度を手動で追加したデータ（例: 農水省委託事業で業界団体が事務局を務めるもの）
- `data/overrides.json` — 公式スケジュール（中小機構「補助金活用ナビ」）で確認した受付状況の補正
- `data/jgrants_detail.json` — jGrants詳細APIから取得した対象業種・利用目的・補助率・本文（キャッシュ）
- `data/local_detail.json` — 支援情報ヘッドラインの各記事から取得した業種・本文・掲載日・実施機関の元ページURL、掲載終了（記事削除）の有無（キャッシュ）

## 構成

- `app_template.html` — アプリ本体のテンプレート（`/*__DATA__*/` などのプレースホルダーにデータを埋め込んでビルド）
- `scripts/fetch_details.ps1` — 詳細データの取得（取得済みはスキップ、途中再開可）
- `scripts/build.ps1` — データファイルから `index.html` を組み立てる（ネットワーク不要）
- `build.py` — 同等のビルドのPython版（J-Net21の新着取得を含む）
- `index.html` — ビルド済みの最終成果物（Claude Artifactとして再公開される）

## 更新方法

クラウドでの自動実行は環境のネットワークポリシーで断念し、現在は手動運用。Claudeに「補助金アプリを更新して」と頼むと、ローカルでデータを再取得・再ビルド・push・Artifact再公開まで行う。
