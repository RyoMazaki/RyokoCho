# 認証UIと確認手順

## 今回の実装

既存のbrowser / server / Auth clientを利用し、メール・パスワードとGoogle認証を提供する。旅行CRUD、招待参加、プロフィール画像、パスワード再設定は今回の実装対象外。

| URL | 画面・役割 |
| --- | --- |
| / | 未認証なら/login、認証済みでプロフィール未作成なら/profile、作成済みなら/tripsへ遷移 |
| /signup | メール登録・確認メール待ち表示・Google認証 |
| /login | メールログイン・Google認証 |
| /auth/callback | Google / メールPKCEコード交換、またはtype=emailのtoken_hash検証。成功後/、失敗時/auth/error |
| /auth/error | 期限切れ・使用済みリンク・OAuth中断等の案内 |
| /profile | S07の表示名登録・編集。未認証なら/loginへ遷移 |
| /trips | 認証後の仮ホーム。未認証なら/login、プロフィール未作成なら/profileへ遷移。旅行データ取得・CRUDは行わない |

/login・/signupも認証済みならプロフィール有無に応じて遷移する。ログアウトは/profile・/tripsからPOSTのServer Actionで実行し、現在のセッションのみ終了して/loginへ戻す。GETによるログアウトは設けない。

プロフィールは保存時に初めて作成する。Googleの名前・画像を自動保存しない。表示名は前後の空白を除去し、必須入力として空白だけの値を拒否する。文字数上限・一意制約は追加しない。任意画像の容量・形式・差し替え・清掃仕様は未決定のため、今回の画面には画像入力を設けない。

## 環境変数

[.env.example](../.env.example)を.env.localにコピーして、既存の2変数を設定する。追加の環境変数や管理キーは不要。

- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

[接続ガイド](./supabase-client.md)も参照。GoogleのClient secretはSupabase Dashboardへ設定し、Next.jsやブラウザには渡さない。

## Supabase DashboardとGoogle Cloudの設定

### 共通

AuthenticationのURL Configurationで、開発時のSite URLをhttp://localhost:3000にする。Redirect URLsにhttp://localhost:3000/auth/callbackを追加する。本番では実際のHTTPSドメインのSite URLと/auth/callbackを設定する。127.0.0.1、別ポート、プレビューURLを使う場合は、それぞれ明示的に登録する。

### メール

- Emailプロバイダーと新規サインアップを有効にする。
- Confirm emailの要否はプロダクト上の最終決定をせず、現在のDashboard設定に対応する。ONなら確認メール待ち、OFFなら発行されたセッションでプロフィール入力へ進む。
- パスワードの最低長・強度はSupabase側で設定する。アプリは任意の独自ルールを追加せず、拒否時に案内する。
- デフォルトのConfirm signupメール（ConfirmationURL）を使う場合は、登録したブラウザでリンクを開く。PKCE verifierがCookieにあるため、別ブラウザやメールアプリ内ブラウザではコード交換に失敗することがある。
- 別ブラウザでのメール確認にも対応させる場合、Confirm signupのリンクを次のように設定する。この実装のcallbackはtype=emailのみ受け付ける。

```html
<a href="{{ .SiteURL }}/auth/callback?token_hash={{ .TokenHash }}&type=email">メールアドレスを確認する</a>
```

Site URLを実際に使用する環境へ合わせる。開発・本番で別プロジェクトを使う場合は各環境に設定する。既存のメールテンプレートに/auth/confirmが設定されている場合は、今回の/auth/callbackへ変更する。

送信できる宛先・送信数はSupabaseのメールサービス設定に従う。任意ユーザーで検証・運用する場合は独自SMTPを設定し、送信ドメインと制限を確認する。確認メールが届かない場合はAuthログ、SMTP、迷惑メールフォルダを確認する。

### Google

1. Google CloudでOAuth同意画面とWebアプリケーション用OAuthクライアントを設定する。テスト公開状態の場合は検証するアカウントをテストユーザーへ登録する。
2. Googleの承認済みリダイレクトURIに、Supabase DashboardのGoogle設定に表示されるCallback URLを登録する。通常はhttps://PROJECT_REF.supabase.co/auth/v1/callback。これはNext.js側の/auth/callbackとは異なる。
3. SupabaseのGoogleプロバイダーを有効化し、GoogleのClient IDとClient secretを登録する。
4. SupabaseのRedirect URLsに、アプリ側のhttp://localhost:3000/auth/callback（本番は実ドメイン）が含まれることを確認する。

## メールサインアップの手動確認

1. npm run devで起動し、未認証のブラウザで/signupを開く。
2. 利用可能なメールアドレス・パスワード・確認用パスワードを入力する。
3. Confirm emailがONの場合、確認メール待ち表示を確認してメールのリンクを開く。OFFの場合は直接/profileへ進むことを確認する。
4. 表示名を保存し、/tripsの挨拶にその名前が表示されることを確認する。
5. ログアウトして/loginへ戻り、同じメールとパスワードで再ログインすると/tripsへ進むことを確認する。
6. /profileから表示名を変更し、再読込後も反映されることを確認する。

## Googleログインの手動確認

1. 未認証状態で/loginか/signupの「Googleで続ける」を押す。
2. Googleでアカウントを選択・同意し、アプリへ戻ることを確認する。
3. 新規ユーザーなら/profile、プロフィール作成済みなら/tripsへ進むことを確認する。
4. ログアウト後の再ログイン、同意のキャンセル時の/auth/error表示も確認する。

## 追加の手動確認

- 未認証で/profile・/tripsへ直アクセスしてもログイン画面へ移る。
- プロフィールを保存せず離脱しても、再ログイン時は/profileへ戻る。
- パスワード不一致、誤った認証情報、未確認メール、パスワード強度不足、通信障害、二重送信の表示。
- 使用済み・期限切れメール、無効なコード、Google設定不備。外部next URLが渡されても外部へ転送しない。
- プロフィール保存失敗時に入力が残り、成功表示や遷移をしない。
- ログアウト後の戻る操作・再読込で保護された内容を取得できない。別ユーザーの名前が混入しない。
- セッション期限切れ時にCookieが更新される。失効済みならログインへ戻る。
- モバイル幅、キーボード操作、読み上げ、実ブラウザでの入力と遷移。
- 実JWTとRLSで他者プロフィールを書き換えられない。管理者接続での確認だけにしない。

## 実装上の境界と検証

サーバーのgetAccount()はgetCurrentUser()で本人確認してからプロフィールを読む。DBエラーを「プロフィールなし」と扱わない。保存Actionは再認証し、クライアントのユーザーIDを受け付けない。初回INSERTはid / display_name、UPDATEはdisplay_nameのみ。既存のRLS / 列GRANTを使い、migrationは変更しない。

コールバックの遷移先は固定し、クエリのnext・error_descriptionを信用しない。トークンやコードを遷移先へ持ち越さず、Cache-ControlとReferrer-Policyを設定する。認証状態に依存するページは動的レンダリング。共有閲覧のために全ルートをログイン必須にはしない。

単体テストはSDKを差し替え、Cookie更新、認証・プロフィール取得失敗、コールバックの入力と遷移先、本人だけの保存、ログアウト失敗を確認する。実メール送信・Google同意・ブラウザCookieの一連のE2E検証は上記手動確認で行う。今回はブラウザツールが環境エラーで起動できず、ブラウザでの見た目・操作は未検証。

## 参考

- [Supabase Google認証](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Next.js・確認メールの設定](https://supabase.com/docs/guides/getting-started/tutorials/with-nextjs)
- [Supabase Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
### 今回実行した検証結果

- npm run lint：警告・エラーなし。
- npm run build：成功。認証依存ページの動的ルートとコールバックの組み込みを確認。
- npm run test:supabase：10件成功。
- git diff --check：成功。
- localhostのHTTP確認：/login・/signupはフォーム付きで200、/auth/errorは200、認証情報のない/auth/callbackは/auth/errorへ307。
- 未認証の/・/profile・/trips：ストリーミングHTML内の/loginへのリダイレクトを確認。プロフィール入力フォームを返さない。
- エディタのProblems取得はツールエラー。buildのTypeScript検証は成功。

実際のアカウント作成・メール送信・Google同意・実ユーザーのプロフィール更新は実行していない。Supabase・Googleの設定を確認したうえで、上記手順に沿って手動確認する。