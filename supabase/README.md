# 初期DB構築

設計は [DB実装設計](../docs/db-implementation.md)、適用対象は [migrations](./migrations) を参照する。既存のアプリUI・依存関係は変更していない。

## migration

1. `20260927000100_initial_schema.sql`：publicの基礎5テーブル、制約、index、RLS、関数・トリガー。
2. `20260927000200_member_invitations.sql`：非公開schemaの招待管理と発行・参加RPC。
3. `20260927000300_private_storage.sql`：private bucketとStorage policy。
4. `20260928000100_shared_read_api.sql`：共有リンク保存先と限定公開の読取RPC。

適用先にはSupabase管理のauth.users・auth.uid()・storage.buckets・storage.objectsと、anon / authenticatedロールが必要。通常のSupabase migration実行ロール（postgres）で適用する。既存bucket・テーブル名の衝突はエラーで検出し、既存定義を無条件に書き換えない。

private schemaはData APIの公開schemaへ追加しない。ryoko_readerは内部関数専用で、anon・authenticatedへ継承させない。リモートへのpush・本番適用は今回実行していない。

## 利用できる操作

| 操作 | 経路 |
| --- | --- |
| 初回プロフィール・表示名変更 | profilesへの本人INSERT / display_name UPDATE |
| 旅行作成 | create_trip(name, start_date, end_date)。作成者参加行も同時作成 |
| 旅行公開範囲変更 | set_trip_visibility(trip_id, visibility)。作成者のみ |
| 参加者の表示名・画像パス取得 | get_trip_members(trip_id)。メンバーのみ |
| 招待発行 | create_trip_invitation(trip_id)。作成者のみ。返却tokenはURLとしてサーバー/画面側で扱う |
| 招待参加 | accept_trip_invitation(token)。認証・初回プロフィール必須。24時間・複数人利用。成功後のS03遷移はUI実装時に行う |
| 退出 | trip_membersの本人DELETE。作成者は不可 |
| 初回アバター紐付け | set_my_avatar(path)。Storage上の本人所有を検証。置換・削除は未開放 |
| 限定公開取得 | get_shared_trip(trip_id, token)。メモ・プロフィール・監査情報を除外 |
| 公開写真の配信対象パス | get_shared_photo_path(trip_id, photo_id, token)。画像配信そのものは未実装 |

## 実装保留の境界

旅程・写真のクライアント書き込み、旅行の基本情報編集・削除・期間短縮、画像置換・清掃、共有リンク発行・期限管理、日別・対象別編集権は未実装。これらは仕様上禁止されたのではなく、必要な専用処理が未実装のため直接DMLを開放していない。メンバー編集可能という要件は維持する。

共有リンク保存先にアプリから書き込むAPIはない。期限・失効・再発行・発行権限が決まるまで、実ユーザーへ共有トークンを発行しない。テストのfixtureは製品のリンク寿命を決めるものではない。

Storageはメンバー向けの読取と、本人アバター・参加旅行サムネイルのアップロードpolicyを実装。写真アップロードは親の編集保護が未実装のため未開放。直接上書き・直接削除・anonの直接読取も許可しない。ファイル形式・容量・画像内容の検証は別途設計が必要で、DB policyだけでは保証しない。未参照アップロードの清掃を含め、画像機能の完成とは扱わない。

公開画像やS08の他メンバーのアバターは、旅行文脈の認可を行うサーバー配信処理が必要。返却pathをそのままpublic URLと扱わない。Service Role Keyはクライアントへ渡さない。

## 検証

### Supabaseのローカル環境がある場合

DockerとSupabase CLIを用意し、使い捨てのローカルDBで適用する。

```powershell
supabase start
# ローカルDBを初期化するため、既存ローカルデータが必要なら先に退避する。
supabase db reset --local
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/initial-database.sql
```

テストSQLはROLLBACKで終了する。失敗時もpsqlの接続終了で未コミットfixtureを破棄する。テストは使い捨てDB専用で、既存実データのあるDBには実行しない。pgTAP形式ではないため、このSQLはpsqlで実行する。

### 今回実行したPGlite検証

アプリのpackage.jsonを変更せず、一時ディレクトリへ検証依存関係を置く。

```powershell
$dbTestTools = Join-Path $env:TEMP 'ryoko-cho-db-test-tools'
npm install --prefix $dbTestTools --no-audit --no-fund --ignore-scripts @electric-sql/pglite@0.5.8
$dbTestPackage = Join-Path $dbTestTools 'node_modules/@electric-sql/pglite/dist/index.js'
node supabase/tests/run-pglite.mjs $dbTestPackage
```

[pglite-bootstrap.sql](./tests/pglite-bootstrap.sql) はAuthのユーザーID・claims、Storageメタデータとロールの検証用代替であり、実Supabaseへ適用しない。実際のAuth認証、PostgREST、Storage API、画像本体、署名URL、複数接続の競合はこの検証には含まれない。

[initial-database.sql](./tests/initial-database.sql) は制約、RLS、専用RPC、限定公開の許可・拒否、Storageメタデータの許可・拒否を検証する。作成者DELETE policyの単独検証に限り、ROLLBACKされるトランザクション内で一時的にDELETEをGRANTする。本番の削除経路が実装済みという意味ではない。

## 実Supabaseとアプリ接続

2026-09-28に利用者がCLIで4本のmigrationを適用し、Local / Remoteの履歴一致を確認済み。上記の「リモート未適用」は初期DB実装時点の記録。Next.js側のクライアント・環境変数・実DBからの型再生成は [Supabase接続ガイド](../docs/supabase-client.md) を参照。
## 旅行読取の追加検証

[trip-reads.sql](./tests/trip-reads.sql)で、作成者・通常メンバーの取得と未認証・非参加者・退出済みの拒否を検証する。run-pglite.mjsは初期DBテストとこのテストの両方を実行する。アプリ側の呼び出し方法とテスト範囲は [旅行読取ガイド](../docs/trip-reads.md) を参照。