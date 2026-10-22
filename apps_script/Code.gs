// 補助金コンパス — Apps Script Webアプリ
// GitHubリポジトリの最新 index.html を読み込んで表示する。データ更新は GitHub への push だけで反映される。
// 非公開リポジトリの場合: スクリプト プロパティ GITHUB_TOKEN に読み取り専用トークンを設定する。

const REPO = 'ari0415/hojokin-app';
const BRANCH = 'main';

function doGet() {
  const token = PropertiesService.getScriptProperties().getProperty('GITHUB_TOKEN');
  const res = token
    ? UrlFetchApp.fetch(`https://api.github.com/repos/${REPO}/contents/index.html?ref=${BRANCH}`, {
        headers: {
          Authorization: 'Bearer ' + token,
          Accept: 'application/vnd.github.raw',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        muteHttpExceptions: true,
      })
    : UrlFetchApp.fetch(`https://raw.githubusercontent.com/${REPO}/${BRANCH}/index.html`, { muteHttpExceptions: true });

  if (res.getResponseCode() !== 200) {
    return HtmlService.createHtmlOutput(
      '<p style="font-family:sans-serif">補助金コンパスを読み込めませんでした（GitHub応答 ' +
        res.getResponseCode() + '）。管理者にお知らせください。</p>'
    ).setTitle('補助金コンパス');
  }
  return HtmlService.createHtmlOutput(res.getContentText('UTF-8'))
    .setTitle('補助金コンパス')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}
