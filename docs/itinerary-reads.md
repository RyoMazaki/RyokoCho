# メンバー向け旅程取得

## 範囲

[取得処理](../src/lib/itinerary/queries.ts)はserver専用の内部関数。
旅行・日付別の旅程一覧と、旅行内のアイテム詳細を取得する。
UI、Route Handler、Server Action、書き込み、migration、RLSの変更はない。
メモ（description）、写真、参加者、監査日時、共有リンクによる非参加者閲覧は含めない。
旅行一覧・旅行本体の取得は[既存の旅行取得](./trip-reads.md)を利用する。

## 呼び出し

Server Component / Route Handler / Server Actionから利用できる。Client Componentから直接importしない。

~~~ts
import {
  listMyItineraryItems,
  getMyItineraryItem,
  ItineraryReadError,
} from "@/lib/itinerary/queries";

const page = await listMyItineraryItems(tripId, "2026-10-01");
if (page.nextCursor) {
  const nextPage = await listMyItineraryItems(tripId, "2026-10-01", {
    cursor: page.nextCursor,
  });
}
const item = await getMyItineraryItem(tripId, itemId);
~~~

両関数のアイテム型は生成済みDatabase型からPickしたItineraryItem。
取得列は id / trip_id / date / category / title / sort_order / time_type /
exact_time / time_period / duration_minutes。
NULL・時刻・時間帯・日付はDBの値のまま返す。時刻の推定・タイムゾーン変換は行わない。

## 一覧・詳細の契約

- 一覧はtripIdとdateを必須とし、指定した旅行・日付に絞る。
- sort_order昇順。重複値はDBで禁止されていないため、同値のときだけID昇順を取得継続用に使う。時刻・カテゴリで並べ替えない。
- pageSizeは1〜100、既定50。nextCursorは最後の行の { sortOrder, id }、続きがなければnull。
- RLS適用後かつカーソル以後のexact countから継続を判定する。APIの返却件数上限がpageSizeより小さくても継続できる。
- カーソルは同じ旅行・日付の取得に使う。UUID・DB integer範囲の非負順序値を検証してからフィルターを構築する。
- ページ分割は取得上限への対策で、画面のページ送りUXを定めるものではない。
- 複数ページ全体のスナップショットは保証しない。途中で並び替え・追加・削除があった場合は最初から再取得が必要になり得る。
- 認証済みの一覧で取得対象がなければ空配列。旅程のない日、期間外でデータのない日、存在しない旅行、非参加・退出済みの旅行を区別しない。空配列だけで旅行の存在・参加状態を判断しない。
- 日付は実在するYYYY-MM-DD（0001〜9999年）を検証する。旅行期間との照合は読取では追加せず、日付で絞る。期間内に制限する書込側の要件は変更しない。
- 詳細はtripIdとitemIdの両方で絞る。別旅行のID、存在しないID、RLSで非表示のアイテムは同じNOT_FOUNDを返す。

## 認証・認可とエラー

呼び出すたびにgetCurrentUser()で本人を確認し、ユーザーJWTのserver clientを生成する。
認可用ユーザーID・clientを呼び出し元から受け取らない。
既存のitinerary_items_select_memberとprivate.is_trip_member(trip_id)によって、
旅程SELECTそのものに所属判定を適用する。
作成者・通常メンバーは共通の所属ルールで取得する。
unlistedだけではこの取得経路へのアクセスを許可しない。
Service Roleやリクエストをまたぐ結果・所属のキャッシュは使用しない。

| ItineraryReadError.code | 意味 |
| --- | --- |
| UNAUTHENTICATED | 認証ユーザーがいない・セッション失効 |
| AUTH_UNAVAILABLE | Auth障害等で本人確認できない |
| INVALID_INPUT | UUID・日付・ページサイズ・カーソルが不正 |
| NOT_FOUND | 詳細がない、指定旅行に属さない、または閲覧不可 |
| READ_FAILED | client作成・DB取得の失敗、必要な取得情報の欠落 |

内部のSQL・Authエラー本文は返さない。DB障害を空一覧やNOT_FOUNDと扱わない。
エラー分類は内部取得契約であり、画面表示やHTTPステータスの決定ではない。

## 検証

- npm run test:itinerary：認証、取得列と条件、ページ継続、日付・カーソル検証、退出後、障害分類。
- npm run test:trips / npm run test:supabase：既存取得・認証処理の回帰確認。
- npm run lint / npm run build。
- [itinerary-reads.sql](../supabase/tests/itinerary-reads.sql)：作成者・メンバー、日付別のsort_order順、同順序値カーソル、別旅行の詳細拒否、非参加・退出・未認証の拒否。
- SQLテストは[既存ランナー](../supabase/tests/run-pglite.mjs)で初期DB・旅行取得テストと一緒に実行する。手順は[DB構築README](../supabase/README.md)を参照。

SQLは使い捨てPGliteに実migrationを適用し、APIロールとauth.uid()相当のclaimsで検証する。
fixture作成だけ管理者で行い、終了時にROLLBACKする。
実SupabaseのJWT発行・PostgREST HTTP（複合orフィルターを含む）・複数接続の同時更新は別途検証が必要。

実行結果：旅程取得10件・旅行取得8件・Supabase基盤10件のテスト、
3本のSQLテスト、lint、build、git diff --checkは成功。
エディタのProblems取得はツールエラーだったため、buildのTypeScript検証で補完した。
