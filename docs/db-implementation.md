# Supabase / PostgreSQL DB実装設計

## 1. 対象と読み方

SQL制約・認可・保存整合性・Storageの実装境界を定義する。データの意味と必須性は [論理モデル](./data_model.md)、挙動は [MVP要件](./requirements.md)、操作フローは [画面設計](./screens.md)、判断理由は [設計判断](./decisions.md) を参照する。DDL全文は転記せず、[migration](../supabase/migrations/)を参照する。

- **実装済み**：第2〜6節のDB基盤と第8節の明記したStorage機能。アプリ機能の完成とは区別する。
- **要件・未実装**：第7節の保存・編集排他・削除保護。直接DMLで代用しない。
- **技術案・未決定**：採用前の方式は明記し、[第9節](#9-未決定事項)で残件を管理する。
- 検証項目は[第10節](#10-検証項目)、実装・検証範囲は[第11節](#11-実装状況と検証範囲)。

## 2. スキーマと型

基礎テーブルは `public.profiles`、`trips`、`trip_members`、`itinerary_items`、`itinerary_photos`。全カラムと必須性は [論理モデル](./data_model.md)、正確なDDLは [initial_schema](../supabase/migrations/20260927000100_initial_schema.sql) に対応する。

| 対象 | 現行のSQL型・初期値 |
| --- | --- |
| ID・ユーザー参照・親参照 | `uuid`。PKは `profiles.id = auth.users.id`、その他は `gen_random_uuid()` |
| 名前・メモ・画像キー・category・time_type・time_period | `text`。値域はCHECK、PostgreSQL ENUMは使用しない |
| 旅行期間・旅程日 | `date` |
| `exact_time` | `time without time zone`。絶対時刻への変換はしない |
| `sort_order` / `duration_minutes` | `integer` |
| `visibility` | `text NOT NULL DEFAULT 'private'` |
| `time_type` | `text NOT NULL DEFAULT 'none'` |
| `is_public` | `boolean NOT NULL DEFAULT false` |
| 作成・更新・参加日時 | `timestamptz NOT NULL DEFAULT now()`。監査トリガーでサーバー値を設定 |

認可資格はAPI非公開の `private` schemaに分離し、Data APIの公開schemaへ追加しない。

| テーブル | カラム・制約 | 用途 |
| --- | --- | --- |
| `private.trip_invitations` | UUIDのid・trip_id・issued_by、byteaのtoken_hash（UNIQUE・32 bytes）、timestamptzのcreated_at・expires_at。全列NOT NULL、期限は発行日時+24時間 | 参加招待。[member_invitations](../supabase/migrations/20260927000200_member_invitations.sql) |
| `private.trip_share_links` | UUIDのid・trip_id、byteaのtoken_hash（UNIQUE・32 bytes）、timestamptzのcreated_at（default now）。全列NOT NULL | 閲覧資格。[shared_read_api](../supabase/migrations/20260928000100_shared_read_api.sql)。期限・失効管理列と発行APIは未実装 |

両テーブルのPKはid（default `gen_random_uuid()`）。RLSを有効化し、一般ユーザーの直接SELECT / INSERT / UPDATE / DELETEは禁止。招待と閲覧資格を相互流用しない。

## 3. 制約と監査

| 対象 | 実装済みの保証 |
| --- | --- |
| `trips` | `end_date >= start_date`、visibilityは `private` / `unlisted` のみ |
| `trip_members` | `UNIQUE (trip_id, user_id)`。UPDATE禁止 |
| `itinerary_items` | categoryは `place` / `transportation`、titleは空文字不可、sort_orderは0以上、duration_minutesはNULLまたは正の整数 |
| 時間指定 | [論理モデルの時間対応表](./data_model.md#itinerary_items)の組み合わせと時間帯5択をCHECKで保証 |
| `itinerary_photos` | 親アイテムをロックする保護トリガーで最大5枚。INSERT時のtrue指定を拒否し、パス変更でfalseへ戻す。公開フラグだけの変更は作成者判定 |
| 監査・不変列 | profiles / trips / itinerary_itemsのcreated_at・updated_at、参加時のjoined_at、写真登録時のcreated_atを設定。PK・作成者・写真登録者・親参照・作成日時を勝手に変更させない |

`updated_at` はprofiles / trips / itinerary_itemsの更新時に `now()` を設定する。競合検知用の版番号ではなく、子更新からtripsへの自動伝播もない。写真保護トリガーだけで、編集権・実画像検証・清掃付きの書き込みが完成したとは扱わない。

以下は追加していない制約・保証である。

- 表示名のUNIQUEは設けない。同名を許可する。
- `(trip_id, date, sort_order)` と `storage_path` のUNIQUEは未採用。順序の採番・画像参照共有は未決定。
- 旅程日の旅行期間内チェックはサーバー保存処理で行う設計。単純なDB CHECKにはせず、専用保存処理は未実装。
- 表示名・旅行名の空文字CHECK、各名称の文字数上限、最大旅行日数・所要時間上限は未追加。現行の[プロフィール保存](../src/app/profile/actions.ts)は表示名をtrimし空白だけの入力を拒否するが、DB制約とは区別する。

## 4. FKと削除

| 子カラム → 親 | ON DELETE |
| --- | --- |
| `profiles.id` → `auth.users.id` | CASCADE |
| `trips.created_by` → `auth.users.id` | NO ACTION |
| `trip_members.trip_id` → `trips.id` | CASCADE |
| `trip_members.user_id` → `auth.users.id` | CASCADE |
| `itinerary_items.trip_id` → `trips.id` | CASCADE |
| `itinerary_photos.itinerary_item_id` → `itinerary_items.id` | CASCADE |
| `itinerary_photos.uploaded_by` → `auth.users.id` | NO ACTION |
| `private.trip_invitations.trip_id` / `private.trip_share_links.trip_id` → `trips.id` | CASCADE |
| `private.trip_invitations.issued_by` → `auth.users.id` | NO ACTION |

ON UPDATEは既定のNO ACTION。ユーザー参照をprofilesへ変更しない。NO ACTIONは採用済みで、将来のアカウント削除手順・匿名化等は未決定。

親削除のCASCADEを子のDELETE policyで止められると考えず、親側で削除認可・編集中データの保護を行う。Storageは連鎖削除されないため、画像キーをDB削除前に確保し[清掃処理](#8-storage)へ渡す。DB削除が失敗する可能性がある段階で画像だけ先に消さない。

## 5. Indexと取得順

基礎テーブルのPK・UNIQUEに加え、以下の補助indexを実装済み。

- `trips(created_by)`
- `trip_members(user_id, trip_id)`
- `itinerary_items(trip_id, date, sort_order)`
- `itinerary_photos(itinerary_item_id)`、`itinerary_photos(uploaded_by)`
- 招待・閲覧リンクそれぞれの `trip_id`（token_hashはUNIQUE）

旅程取得には明示的に日付・sort_order順を指定する。日付指定時はsort_order順とし、時刻順にはしない。同順序値の継続取得・ページングの契約は [旅程取得ガイド](./itinerary-reads.md) に従う。

## 6. 認可と取得契約

### 6.1 共通方針

publicの基礎5テーブルはRLS有効。通常のアプリ操作はユーザーJWTを使い、RLS・列GRANT・RPCの認可を組み合わせる。Service Roleを通常操作に常用しない。基礎表のanon直接SELECTは不可で、authenticatedでも非参加旅行は取得できない。

policyが存在しても直接DMLのGRANTがなければ実行不可。未実装の保存・排他・清掃を、所属判定だけのpolicyや追加GRANTで迂回させない。policyの追加では既存policyとのOR結合とUPDATEに必要なSELECTも検証する。

### 6.2 所属判定と関数所有者

`private.is_trip_member(trip_id)` は現在の `auth.uid()` の所属、`is_trip_creator(trip_id)` は作成者、`is_item_member(item_id)` は親旅行への所属を判定する。

現行は `STABLE SECURITY DEFINER` と専用所有者 `ryoko_reader`（NOLOGIN・NOINHERIT・NOBYPASSRLS）を使用する。この内部ロールだけのSELECT policyで再帰を避け、APIロールへ継承させない。RLSを迂回する管理ロール所有の旧案は採用していない。

関数は空のsearch_path・完全修飾名・固定SQLを使い、PUBLICのEXECUTEを取り消して必要なロールだけに許可する。判定ユーザーIDは引数で受け取らない。書込RPCと作成者参加トリガーはpostgres所有のSECURITY DEFINERで、明示的な本人・作成者認可を行う。トリガー関数の直接EXECUTEは許可しない。所有者やFORCE RLSの変更時は再帰・認可を再検証する。

### 6.3 現在の直接操作

以下はauthenticatedの実効権限。製品要件上の編集可否とは区別する。

| テーブル | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| profiles | 本人 | 本人のid・display_name | 本人のdisplay_name | 不可 |
| trips | メンバー | 不可 | 不可 | 不可 |
| trip_members | メンバー | 不可 | 不可 | 本人かつ非作成者 |
| itinerary_items | メンバー | 不可 | 不可 | 不可 |
| itinerary_photos | 親旅行のメンバー | 不可 | 不可 | 不可 |

tripsのINSERT / UPDATE / DELETE基礎policyは実装済みだが、直接GRANTはない。旅程・写真の書込policyと一般ユーザー向け専用保存処理は未実装。プロフィール画像の初回紐付けは専用RPCを使う。

### 6.4 更新経路の境界

今後の専用処理でも、変更列と操作種別を限定する。メンバーの旅行基本情報編集と作成者だけのvisibility変更、メモ保存と旅程順序保存、写真差し替えと公開切替を分離する。別旅行・別アイテムへの親FKの付け替えは提供しない。

画像キーは任意文字列の更新を許可せず、実オブジェクト・bucket・対象旅行／アイテム・アップロード主体を検証する。`uploaded_by = auth.uid()` やStorage側の認可だけで、不正なDBパス登録を防げるとは扱わない。

<a id="membership"></a>

### 6.5 旅行作成・参加・退出

- `create_trip` は本人をcreated_byとして登録する。`AFTER INSERT` トリガーが作成者の参加行を同じトランザクションで作り、片方だけ残さない。INSERT RETURNING時の所属判定順序を避けるため専用RPCを使用する。
- `set_trip_visibility` は作成者だけが実行できる。一般公開はCHECKで拒否する。
- `create_trip_invitation` は作成者を検証して招待を発行し、生トークンと期限を返す。DBにはSHA-256ハッシュを保存する。
- `accept_trip_invitation` は本人認証・プロフィール作成済みを要求する。旅行ロック後に期限を再検証し、重複参加はON CONFLICTで防ぐ。24時間以内は複数人が利用でき、参加でトークンを消費しない。
- 退出は本人かつ非作成者の参加行DELETEのみ。他者追加・退出、作成者退出、参加行の付け替えを許可しない。

招待UI・認証後の復帰は別途実装する。単純なGET・URLプレビューだけで参加確定せず、認証済みの保護された参加リクエストを使う。参加確認画面を追加せず、成功時はS03へ遷移する。失効・転送可否は未決定。

### 6.6 親削除と写真

親削除に伴う写真メタデータの削除は [FKと削除](#4-fkと削除)、編集中データの保護は [保存処理](#7-未実装の保存処理と整合性) に従う。

<a id="shared-read"></a>

### 6.7 非参加者閲覧・参加人数・プロフィールの取得

メンバー用取得と公開用RPCを分離し、非参加者には未ログイン・ログイン済み非メンバーとも同じ制限を適用する。限定公開の閲覧に匿名サインインや参加登録を要求しない。

| 経路 | 認可と返却範囲 |
| --- | --- |
| `get_trip_members` | 対象旅行の所属を検証し、表示名・画像キーのみ返す。profilesとのINNER JOINのため未作成プロフィールは含めない |
| `get_shared_trip` | 旅行ID・閲覧トークン・unlistedを検証。旅行基本情報・thumbnail_path・参加人数・旅程基本情報・公開写真IDを返す |
| `get_shared_photo_path` | 同じ旅行認可に加え、写真の所属・is_public・パスの旅行／アイテムを検証。重複参照パスはエラー |

公開取得にはメモ、参加者行、表示名、アバター、作成者・投稿者ID、監査情報を含めない。人数はDBで数え、参加者行をブラウザへ渡さない。非公開旅行では旅程・人数・サムネイル・写真を返さず、写真trueだけでも許可しない。将来の一般公開でも非公開写真とメモ・プロフィール等の除外は維持する。

S08の取得は別旅行の所属では代用できない。メンバー向け旅行・参加者と旅程の呼出契約は [旅行取得](./trip-reads.md)・[旅程取得](./itinerary-reads.md) を参照する。パス取得は画像配信・署名URL発行そのものではなく、第8節の認可が別途必要。

### 6.8 閲覧用共有リンク

`private.trip_share_links` と読取RPCは実装済み。現行は保存済みハッシュ・対象旅行・unlistedの一致を確認する範囲で、発行権限・期限・失効・再発行の管理APIは未実装。これらを決めるまで実ユーザーへ発行しない。招待の24時間を自動適用しない。

旅行IDだけ、未検証トークン、招待トークン、クライアントの「検証済み」フラグでは許可しない。生トークンを通常の旅行取得結果・ログ・外部への参照情報へ漏らさず、資格が異なる利用者間で応答をキャッシュ共有しない。

非公開化後は既存リンクでの再取得・新規画像URL発行を拒否する。発行済み画像URLの扱いは第9節の残件。将来のpublic導入時はCHECK・認可を拡張し、`visibility != 'private'` の一律許可にしない。

## 7. 未実装の保存処理と整合性

以下は確定要件を実現するための保存契約。編集権・画像清掃付きの専用処理は未実装。

### 保存単位と変更列

- 既存旅程の基本項目・順序は旅行IDと対象日を検証し、日単位で1つのDBトランザクションにする。順序のみならsort_orderだけ、メモならdescriptionだけを更新し、変更しない列は送らない。
- 既存メモ・既存アイテムへの写真アップロードは即保存。古い一括更新や編集破棄で、即保存内容・新規保存済み行を巻き戻さない。
- 新規アイテム・メモ・写真はモーダル保存で一連の登録とし、キャンセルでは確定しない。DBとStorageの部分失敗を全成功と扱わない。
- 日付移動を提供する場合は元・先の両日を検証し、通常の日単位更新に黙って混ぜない。旅程日はサーバーで旅行期間内を確認し、直接DMLによる迂回を許可しない。

### 編集排他と削除保護

対象日の並び替え中は同日の別の並び替え・追加・削除・日付移動を禁止する。本人も未保存の並び替え中は新規追加不可。別日の並び替えとメモ・写真変更は許可し、同じメモ・同じ写真の競合を別に防ぐ。

**技術案（未実装）**：期限付き編集権を `(trip_id, date)`、メモのitem_id、写真のphoto_idごとに保持する。補助データにはFK・CASCADE、対象キーのUNIQUE、保有者・セッション・期限を持たせる。直接DMLは禁止し、所属を確認する取得・更新・解放・状態取得関数を使う。非参加者に編集者情報を返さない。DDL・期限・更新間隔は未決定。

別タブ・別端末をユーザーIDだけで同じ権利と扱わない。取得後は最新データを読み、保存と同じ短いトランザクションで本人・所属・セッション・期限を再検証する。失効後の古い入力の自動再送を避け、同一セッションの遅い要求でも新しい入力を巻き戻さない。基本項目編集にも読み込み時の値との比較等で競合を検出する案とし、updated_atだけを厳密な版番号としない。

削除・期間短縮は並び替え・メモ・写真変更・アップロード中の対象を保護する。編集終了後に再確認する方式が候補で、強制削除は追加しない。編集開始と削除は共通ガードを同じ順序で短くロックし、確認と削除の間の新規編集を防ぐ。操作中ずっとDBトランザクションや旅行全体のロックを保持しない。期限切れのアップロード完了はDB登録を拒否し清掃する。

順序の採番・UNIQUE採否は未決定。採用する場合の候補は `UNIQUE (trip_id, date, sort_order) DEFERRABLE INITIALLY IMMEDIATE` で、並び替えのトランザクション内だけ遅延させる。

### 写真登録・差し替え・期間短縮

- 写真登録は親をロックして現在数と追加数を確認し、5枚上限を守る。保護トリガーに加え、所属・投稿者・実画像・編集保護の検証が必要。
- 差し替えは既存行の新キーへの更新とし、6枚目を一時登録しない。パスとfalseを同時確定し、旧画像は後から清掃する。作成者の差し替えも例外にしない。uploaded_byは現DBどおり元の登録者を保持する。
- 期間短縮は利用者の了承後に対象と編集状態を再検証し、期間変更・範囲外旅程と写真メタデータ削除を同一トランザクションで行う。キャンセルは無変更。確認後に削除対象が変われば再確認し、画像清掃用キーは削除前に確保する。確認文言は [日付要件](./requirements.md#日付) を参照する。

## 8. Storage

### 実装済みのbucket・policy

3bucketはprivate。キー形式は下表を設計上の規約とし、現policyはUUIDの親部分と所属・DB参照を検証する。末尾のファイル名・形式・容量まで検証済みとは扱わない。

| bucket | キー形式 | authenticatedの直接SELECT / INSERT |
| --- | --- | --- |
| avatars | `<user_id>/<object_uuid>.<ext>` | 本人のuser_id配下 / 本人のuser_id配下 |
| trip-thumbnails | `<trip_id>/<object_uuid>.<ext>` | 所属とDB参照・パスの一致 / 対象旅行のメンバー |
| itinerary-photos | `<trip_id>/<item_id>/<object_uuid>.<ext>` | 所属と写真行・親ID・パスの一致 / 不可（親の編集保護が未実装） |

対象3bucketの直接UPDATE・DELETE、anon直接読取は禁止。restrictive policyで既存の緩いpolicyとのOR結合による迂回を防ぐ。他bucketはこの制限の対象外。

`set_my_avatar` は本人所有の実オブジェクトを確認し、未設定からの紐付け（同一パスの再設定可）だけを許可する。置換・削除は未開放。アバター・サムネイルのINSERT policyがあっても、画像入力・置換・清掃機能の完成を意味しない。

### 配信・参照の契約

DBには用途ごとのbucket内キーを保存し、外部URL・署名URL・期限は保存しない。`storage.objects` への独自FKは作らず、本体操作はStorage APIを使う。

公開画像と他メンバーのアバターは認可済みサーバー配信が未実装。アバターは本人または対象旅行のS08資格、サムネイルは旅行閲覧資格、写真は旅行資格と写真公開条件を確認する。DB取得・Storage・署名URL発行で条件を揃え、パスを知るだけで配信しない。旅行写真の権限をStorageのowner_idだけに限定しない。

署名URLの有効期間・退出や非公開化後の即時遮断方針は未決定。差し替えは新キーを使い、古いURLで新画像を取得させない。同じ画像の複数参照と公開状態混在は未決定で、現行の公開パスRPCは重複参照を拒否する。storage_pathのUNIQUEを設けたわけではない。

### 未実装の登録・清掃

1. アップロード前に本人・対象旅行・親を認可し、削除から保護する。拡張子だけでなく許可形式・内容を検証する（制限値は未決定）。
2. 新キーへアップロードし、DB登録時に権限・実体・bucket・パス・アップロード主体を再確認する。
3. DB登録失敗は未参照画像を清掃する。置換は新参照確定後、削除は対象キー確保とDB削除後に旧画像を清掃する。別行から参照中のキーを無条件に削除しない。
4. 清掃失敗・プロセス停止にも再試行できるよう対象を永続化する。ジョブ基盤・outbox等の方式は未採用。メモリ上のキー保持だけで完了扱いにしない。

新規アイテムは親作成と画像アップロードの順序、途中状態の公開防止、失敗補償・キャンセル・再送の重複防止を設計する。一時領域を採用する場合は配信から隔離し、所有者と対象を検証して確定・清掃する。親存在チェックを単に外す案は採用しない。

旅行削除後は所属行も消えるため、清掃は削除前に認可・確定した対象をサーバーで処理する。任意のクライアント指定パスをService Roleで消さない。並行アップロード・置換による取りこぼしを防ぎ、親削除後に完了した画像も清掃する。アカウント削除時のアバターも別途対象となる。

## 9. 未決定事項

確定済み要件を未決定へ戻さず、以下を対象機能の実装前に具体化する。

| 分類 | 残件 |
| --- | --- |
| 閲覧リンク | 発行権限・期限・失効・再発行・配布UI。一般公開は将来対応 |
| 招待 | 失効・転送可否、管理列の拡張、URL・UIへの接続 |
| 編集 | 編集権DDL・期限・更新間隔・競合処理、順序の採番・UNIQUE、基本項目の競合検出 |
| 保存・削除 | 新規親と画像の登録順序・補償・再送、清掃の永続的再試行方式 |
| 入力 | 旅行名の空文字・空白、旅程名の空白、各名称の文字数上限。表示名の現在のアプリ検証は第3節参照 |
| 画像 | 形式・容量・圧縮・リサイズ、同一オブジェクトの参照共有、写真表示順・派生画像 |
| 時刻 | 秒入力、日跨ぎ、海外旅行の時刻・タイムゾーン |
| 配信 | 署名URLの期間、退出・非公開化後の発行済みURLの扱い |
| 履歴・モデル | 退出済み投稿者の表示、差し替え者の監査、子更新の旅行更新日時への伝播、将来のアカウント削除・履歴保持 |

認証のメール確認・中断再開、メモ送信契機・保存中の閉じる操作、写真操作・削除調整・日付切替等のUX残件は [画面設計](./screens.md#8-残る未決定事項) を参照する。認証の現行実装は [認証UIガイド](./auth-ui.md)。未採用のモデル拡張は [論理モデル](./data_model.md#未決定事項)。

## 10. 検証項目

変更した処理に応じ、以下を検証する。すべてが実装・検証済みという意味ではない。

- **制約・トランザクション**：必須性・default・値域・時間の対応・日付前後・重複参加・FK削除、作成者同時参加と作成直後の取得、失敗時の部分更新防止。既存データがあれば制約違反候補・画像参照も確認する。
- **認可**：未認証・非参加者・通常メンバー・作成者・退出済みでSELECT / INSERT / UPDATE / DELETE、RPC、列改変・ID偽装・自己加入・他者退出・作成者退出の拒否。RLS再帰や関数・viewの迂回も確認する。
- **共有・招待**：無効・別旅行・種別違いのトークン、24時間境界・待機後再検証・複数人利用・再送、非公開化後の拒否、人数以外の参加者情報・メモ・非公開写真の非漏洩、共有キャッシュによる漏洩防止。
- **排他・保存**：同日と別日の並び替え、メモ・写真の独立変更、同一対象・別タブ・期限切れ・退出後の競合、日付移動の両日検証、遅い保存と古い一括更新による巻き戻し防止。
- **写真・削除**：5枚目成功・6枚目拒否と同時登録、差し替えのfalseリセット・公開変更権限、キャンセル無変更・対象変化時の再確認、編集中・アップロード中の親削除防止。
- **Storage・障害**：別旅行や偽IDのパス・他者画像の登録・不正なURL発行の拒否、DBと配信の認可一致、DB失敗・Storage失敗・プロセス停止・並行削除からの再試行、未参照画像と実体なし参照の検出。

隔離DBの再実行手順は [DB構築README](../supabase/README.md#検証)。実JWT・PostgREST・Storage API・複数接続の検証は代替DBテストと区別する。

## 11. 実装状況と検証範囲

| migration | 実装済み範囲 |
| --- | --- |
| [initial_schema](../supabase/migrations/20260927000100_initial_schema.sql) | 基礎5テーブル・制約・index・RLS・GRANT・監査・作成者参加・写真保護、旅行作成・公開範囲変更・参加者取得RPC |
| [member_invitations](../supabase/migrations/20260927000200_member_invitations.sql) | 招待保存・発行・参加RPC |
| [private_storage](../supabase/migrations/20260927000300_private_storage.sql) | private bucket・Storage policy・初回アバター紐付けRPC |
| [shared_read_api](../supabase/migrations/20260928000100_shared_read_api.sql) | 閲覧リンク保存先・限定公開取得・公開写真パス検証RPC |

**未実装**：編集権付き旅程・メモ・写真の保存、旅行基本情報編集・期間短縮・削除、画像配信・置換・清掃、共有リンク管理。製品上のメンバー編集権限を否定するものではなく、安全な専用経路が未完成のため直接DMLを開放していない。

アプリの実装範囲・取得契約は [接続基盤](./supabase-client.md)、[認証UI](./auth-ui.md)、[旅行・参加者取得](./trip-reads.md)、[旅程取得](./itinerary-reads.md) を参照する。DBのRPCやpolicyがあることと、画面・サーバー処理が接続済みであることは別に確認する。

既存の[DBテスト](../supabase/tests/run-pglite.mjs)は、PGliteへ全migrationを適用し、初期DB・旅行取得・旅程取得のSQLを実行する。管理者はfixture作成等に限定し、APIロールとauth.uid()相当のclaimsで認可を検証、fixtureはROLLBACKする。旅行DELETE policyの単独テストの一時GRANTを実際の削除APIと混同しない。

2026-09-28に利用者が実Supabaseへ4本のmigrationを適用し、Local / Remoteの履歴一致を確認済み。実DBからの型生成も成功している。ただし、実SupabaseのJWT・PostgREST・Storage HTTP、実ファイル・署名URL、複数接続での競合は未検証。PGliteのStorage検証はメタデータpolicyだけで、未開放の書き込み機能の完成を意味しない。
