# メンバー向け旅行一覧・詳細の取得

## 範囲

[queries.ts](../src/lib/trips/queries.ts)にserver専用の読取関数を追加した。UI・既存書き込み処理・migration・RLSは変更していない。HTTP APIやServer Actionの公開エンドポイントも追加していない。Server Component / Route Handler / Server Actionから呼び出す。

旅行詳細は旅行本体の基本情報を意味する。旅程、メモ、写真一覧、参加者情報・人数、画像配信、非参加者の共有リンク閲覧は今回の取得に含まない。

## 使用方法

```ts
import { listMyTrips, getMyTrip, TripReadError } from "@/lib/trips/queries";

const page = await listMyTrips();
// page.trips: TripSummary[]
// page.nextCursor: 次の取得位置。nullなら続きなし。
if (page.nextCursor) {
  const nextPage = await listMyTrips({ cursor: page.nextCursor });
}

const trip = await getMyTrip(tripId);
```

一覧はpageSizeを1〜100で指定可能、既定50件。UUIDのID昇順を取得継続のための技術的な順序として使う。画面の一覧順、過去・今後の分類、ページ送りのUXを確定したものではない。表示順が決まった段階で取得契約を調整する。

RLS適用後のexact countと実際の取得件数からnextCursorを決めるため、API側の最大返却件数が指定pageSizeより小さくても続きが欠落しない。カーソルはUUID検証し、任意のカーソルでも参加権限を緩めない。複数ページ全体のスナップショットは保証せず、ページごとにその時点の参加状態を反映する。

| 戻り値 | 取得列 |
| --- | --- |
| TripSummary | id / name / start_date / end_date / thumbnail_path |
| TripDetail | TripSummaryの列 + visibility |

型は生成済みDatabase型のTablesからPickしている。selectには列を明記し、作成者IDや監査日時を今回の取得結果に含めない。thumbnail_pathはStorageのパスであり、公開URLや閲覧許可そのものではない。

## 認証・権限

1. getCurrentUser()でSupabase Authによる本人確認を行う。未認証ならDB照会しない。
2. 既存のserver clientでユーザーのJWTを使用する。ユーザーIDや認可用clientを呼び出し元から受け取らない。
3. trips_select_member policyのprivate.is_trip_member(id)を利用する。作成者IDだけで絞らず、作成者も通常メンバーも現在のtrip_members所属で判断する。
4. 参加確認と旅行取得を別々の照会に分けず、旅行SELECT自体にRLSを適用する。
5. 認証・所属・旅行結果をリクエスト間でキャッシュしない。退出後の次の照会ではアクセスを拒否する。

未認証はUNAUTHENTICATED。認証済みでも参加旅行がなければ一覧は空配列。詳細は非参加者・退出済み・存在しないIDを同じNOT_FOUNDとして扱い、旅行の存在を漏らさない。unlistedであっても、このメンバー用取得では非参加者に返さない。共有閲覧は別の検証経路を使う。

| TripReadError.code | 意味 |
| --- | --- |
| UNAUTHENTICATED | 有効な認証ユーザーがない |
| AUTH_UNAVAILABLE | Authとの通信等で認証を確認できない |
| INVALID_INPUT | UUID・ページサイズが不正 |
| NOT_FOUND | 詳細が存在しない、またはRLSにより閲覧不可 |
| READ_FAILED | DB取得に失敗。空配列・NOT_FOUNDとは区別 |

SQLやAuthの内部エラー本文を利用者向け結果へ流さない。呼び出し元はTripReadErrorを判別し、ログインへの遷移・404・再試行等をUI決定後に接続する。型定義やこのエラー分類を、HTTPレスポンス設計が確定したものとは扱わない。

## 検証

- npm run test:trips：8件成功。認証前の照会拒否、Auth障害、取得列、空一覧、詳細不可、退出後の再照会、API件数上限を含むカーソル継続、入力検証、DB障害。
- npm run test:supabase：既存Authテスト10件成功。
- npm run lint / npm run build：成功。エディタのProblems取得はツールエラーだったため、buildのTypeScript検証で補完。
- [trip-reads.sql](../supabase/tests/trip-reads.sql)：作成者・通常メンバーの取得、別旅行の拒否、非参加者のprivate / unlisted拒否、退出直後の拒否、認証IDなし・anon拒否を確認。
- [既存DBテスト](../supabase/tests/initial-database.sql)も回帰確認した。

SQLは使い捨てのPGliteへ4本の実migrationを適用し、authenticated / anonロールとauth.uid()相当のclaimsを設定して実行した。管理者権限はfixture作成にのみ使用し、取得の検証はAPIロールで行う。fixtureはROLLBACKされる。

実行手順は [DB構築README](../supabase/README.md) を参照。既存のrun-pglite.mjsは2本のSQLテストを実行する。SQLテストを実データのあるDBへ実行しない。

この検証は実Supabase AuthのJWT発行・PostgREST HTTP・複数接続の競合を含まない。実Supabaseへのデータ追加・変更は行っていない。実JWTでのエンドツーエンド確認は別途必要。