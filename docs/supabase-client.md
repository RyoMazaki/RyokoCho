# Supabase接続・Auth基盤

## 構成

- [database.types.ts](../src/types/database.types.ts)：リンク済み実Supabaseのpublic schemaからCLIで生成。private / auth / storage schemaは含めない。
- [client.ts](../src/lib/supabase/client.ts)：Client Componentから使用するCookieベースのbrowser client。
- [server.ts](../src/lib/supabase/server.ts)：Server Component / Server Action / Route Handler向け。非同期のcookies()を使い、リクエストごとに生成する。
- [auth.ts](../src/lib/supabase/auth.ts)：getCurrentUser()でSupabase Authに検証を依頼し、SDKのdata / errorを返す。
- [proxy.ts](../src/proxy.ts)・[Cookie更新処理](../src/lib/supabase/proxy.ts)：getClaims()でJWTを検証・必要時更新し、後続リクエストとブラウザのCookieへ反映する。更新時のSDKのキャッシュヘッダーも保持する。
- [env.ts](../src/lib/supabase/env.ts)：公開用URL・publishable keyの取得と未設定チェック。

Proxyは認証必須へのリダイレクトを行わない。限定公開リンクの未ログイン閲覧を妨げず、保護するページ・Server Action・Route Handlerで認証を確認し、DBのRLS / GRANT / RPC認可も適用する。Proxyだけを認可境界にしない。

## 環境変数・起動

[.env.example](../.env.example)をプロジェクトルートの.env.localへコピーし、Supabase Dashboardの対象プロジェクトから値を設定する。

| 変数 | 設定値 |
| --- | --- |
| NEXT_PUBLIC_SUPABASE_URL | プロジェクトのURL（https://…supabase.co） |
| NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY | sb_publishable_で始まる公開用キー |

この基盤では新形式のpublishable keyを使用する。legacy anon JWTやservice_role JWT、sb_secret_キーは受け付けない。公開用キーはブラウザへ配信される前提であり、アクセス制御はユーザーJWTとRLS等で行う。管理用キーはこの実装に不要で、server clientもユーザー権限で接続する。NEXT_PUBLIC_の変数へsecret・service_roleを絶対に設定しない。

.env.localはGit管理対象外。設定後にnpm run devを実行する。NEXT_PUBLIC_の値を変更した場合は開発サーバーを再起動し、本番では再ビルドする。設定不足はクライアント生成時に明示的に失敗する。静的な初期画面のbuild成功だけでは接続成功を意味しない。

## 接続・認証取得

Client Component内で使用する：

```ts
import { createClient } from "@/lib/supabase/client";

const supabase = createClient();
const { data: { session }, error } = await supabase.auth.getSession();
// sessionは未ログインならnull。画面表示やSDK操作に使う。
// サーバーの認可には、このsessionや埋め込まれたuserをそのまま信用しない。
```

認証状態の変化を購読する場合はauth.onAuthStateChange()を使用し、Componentのcleanupでsubscription.unsubscribe()を呼ぶ。

Server Component / Server Action / Route Handler内で使用する：

```ts
import { getCurrentUser } from "@/lib/supabase/auth";

const { data: { user }, error } = await getCurrentUser();
// 認証済みならuser、未認証・失効等ならuserはnull。
// errorも確認し、未ログインと通信障害等を呼び出し元で区別する。
```

型付きのDB / RPC接続が必要なserver処理では以下を使用する：

```ts
import { createClient } from "@/lib/supabase/server";

const supabase = await createClient();
// supabase.from(...) / supabase.rpc(...) は生成したDatabase型を利用する。
```

server clientとAuth helperはserver-onlyで保護する。Client Componentにimportしない。server clientをモジュール変数へ保存したり、ユーザーごとの取得結果を共有キャッシュへ保存したりしない。トークンをprops・ログ・API応答へ不用意に含めない。

Server ComponentはCookieを書き換えられないため、更新の永続化はProxyが担当する。Server Action / Route Handlerではserver clientのCookie書き込みが利用できる。認証を扱うページにISRを使用せず、必要に応じてdynamic = "force-dynamic"を指定する。認証API等を追加する際は応答にCache-Control: private, no-storeを設定する。現在のProxyも対象応答に同ヘッダーを付ける。応答を差し替える場合、更新済みCookieとキャッシュヘッダーを必ず引き継ぐ。

## 型の再生成

CLIでログイン・対象プロジェクトへlink済みの環境で実行する：

```sh
npm run supabase:types
```

内部でsupabase gen types typescript --linked --schema publicを実行する。実DBのメタデータを読み取るだけでmigrationは適用しない。成功時のみUTF-8で型ファイルを更新し、生成失敗時は既存ファイルを保持する。migration適用後に再生成し、差分を確認してコミットする。生成型を手修正しない。

型はDB形状の情報であり、権限やCHECK制約をすべてTypeScriptで保証するものではない。型にInsert / Updateが存在しても、その操作がRLS / GRANT上許可されているとは限らない。

## 今回の範囲と次の作業

認証UIを追加し、メール・パスワード / Google認証、コールバック、ログアウト、S07表示名入力を実装した。設定と確認手順は [認証UIガイド](./auth-ui.md) を参照。旅行CRUD・招待復帰・プロフィール画像は未実装。メール確認の要否はDashboard設定に対応し、プロダクト上の最終決定は行っていない。

2026-09-28：利用者から実Supabaseへの4本のmigration適用・確認完了の報告あり。Local / Remoteの4バージョン一致を確認済み。今回、リンク済みプロジェクトから型生成も成功。これは実JWTによる全RLS操作・Storage実ファイル・同時実行の検証完了を意味しない。

## 参照

- [Supabase公式SSR設定](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [Supabase公式SSR詳細・キャッシュの注意](https://supabase.com/docs/guides/auth/server-side/advanced-guide)
- [Supabase公式型生成](https://supabase.com/docs/guides/api/rest/generating-types)
## 基盤の検証

- npm run lint
- npm run build（Next.js 16.3.6・TypeScript・Proxyの組み込み）
- npm run test:supabase（Node組み込みtest runner。認証UIの追加テストも含む）
- git diff --check

[基盤テスト](../tests/supabase.test.mjs)は秘密鍵形式の拒否、更新Cookieのrequest / response双方への引き継ぎとキャッシュヘッダー保持、未認証リクエストの通過、server clientのユーザー間分離、Auth検証エラーの保持を確認する。Auth SDKを差し替えた単体テストであり、実ログイン・トークン期限切れ・Google OAuthを検証するE2Eテストではない。エディタのProblems取得はツールエラーのため、buildのTypeScript検証で補完した。