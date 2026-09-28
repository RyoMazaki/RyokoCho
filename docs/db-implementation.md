# Supabase / PostgreSQL DB実装設計

## 1. 位置付けと前提

現行DB設計を初期migrationの基準とする。実装範囲・未実装の専用処理・検証結果は第11節を参照。実Supabaseへの4本のmigration適用と履歴一致の確認は2026-09-28に利用者が完了。アプリ接続基盤は [Supabase接続ガイド](./supabase-client.md) を参照。

参照資料：

- [product.md](./product.md)
- [requirements.md](./requirements.md)
- [screens.md](./screens.md)
- [data_model.md](./data_model.md)
- [AGENTS.md](../AGENTS.md)
- [decisions.md](./decisions.md)

アプリはNext.jsの初期画面が中心。初期DB定義は [migrations](../supabase/migrations) に追加した。既存DBからの移行を前提にしない。

以下の3つを区別する。

- **既存仕様**：資料で明記されている型、関係、制約、権限。
- **技術提案**：既存仕様を実現するためのdefault、index、トランザクション、権限実装。
- **未決定事項**：プロダクト判断や資料間の整合が必要な内容。権限を推測して付与しない。

本書のCREATE TABLE案の対象は `public.profiles`、`public.trips`、`public.trip_members`、`public.itinerary_items`、`public.itinerary_photos` の5テーブルとする。招待管理・閲覧用共有リンク・編集権の保存構造は詳細仕様に応じて別途設計するため、この5テーブルのDDLだけでMVP全体が完成するわけではない。認証はSupabase管理の `auth.users` を利用し、メール・パスワードとGoogle Accountに対応する。Apple AccountはMVP対象外。`trip_days`、category別詳細テーブル、メンバーのroleは追加しない。

## 2. 確定した方針と将来の拡張

以下は [decisions.md](./decisions.md) に記録した確定事項であり、未決定の選択肢として扱わない。

| 論点 | 確定方針 | DB実装設計への反映 |
| --- | --- | --- |
| 非参加者の旅行閲覧 | MVPは限定公開。共有リンクの閲覧条件を満たす人がログイン不要でS05・C01を閲覧 | 旅行はvisibilityで管理、初期値private、変更は作成者のみ。一般公開は将来対応。メモ・S08は公開せず人数のみ返す |
| 写真の公開設定 | 初期値false、差し替え後もfalse。任意変更は作成者のみ | メンバー全員が差し替え・削除可能。最大5枚。非公開旅行の写真単独公開は不可。限定公開・将来の一般公開とも写真falseは非参加者に返さない |
| 旅行期間外の旅程 | 原則期間内。短縮時は確認了承後に範囲外旅程を削除 | 単純なDB CHECKにはしない。期間変更とDB削除を同一トランザクションで扱い、写真本体は別途清掃 |
| 時間の整合性 | `exact` は正確な時刻のみ必須、`period` は時間帯のみ必須、`none` は両方NULL | DB CHECKで保証する確定仕様としてDDLに反映 |
| category | `place` と `transportation` の2種類 | `place` に場所・その場所で行うこと・滞在中の行動を含め、`action` は追加しない |

写真の `is_public` は旅行単位の公開範囲を表すものではない。写真の型・参照先は維持し、旅行の範囲は以下のvisibilityで管理する。ユーザー削除FKは本書のNO ACTIONを採用する。

旅行の公開範囲は、非公開・限定公開・将来の一般公開を区別する。MVPで提供するのは非公開と限定公開で、初期値は非公開。変更は旅行作成者のみ。

| 公開範囲 | 非参加者の閲覧 | 提供時期 |
| --- | --- | --- |
| 非公開 (`private`) | 不可。写真の公開設定がtrueでも不可 | MVP・初期値 |
| 限定公開 (`unlisted`) | 共有リンクの閲覧条件を満たす人がログイン不要で閲覧 | MVP |
| 一般公開 (`public`) | 限定公開と区別した一般向け閲覧。検索・一覧等の具体的仕様は後日決定 | 将来。MVPでは選択・保存・閲覧許可しない |

限定公開は、これまでの共有リンクの議論に基づき「リンクを知る人が閲覧できる」として設計する。閲覧用リンクの期限・失効・再発行方法と発行操作の権限は未決定。参加用招待URLの24時間を閲覧リンクへ自動適用しない。共有リンクの閲覧でメンバー登録・編集権限は付与しない。

旅行を閲覧できる非参加者にも、写真は `itinerary_photos.is_public = true` のものだけを返す。この条件は限定公開・将来の一般公開で共通。非公開旅行の写真だけを単独公開することはない。メモ・参加者一覧・表示名・プロフィール画像・投稿者情報は返さず、人数のみ返す。

### 公開範囲を拡張するためのモデル変更

旧 `trips.is_public boolean` 案を `trips.visibility text NOT NULL DEFAULT 'private'` に置き換える。理由は限定公開と一般公開を区別するため。写真の `itinerary_photos.is_public` は変更しない。公開状態booleanに追加フラグを組み合わせる代替案もあるが、不正な組み合わせと条件分岐を増やすため単一の範囲値を選ぶ。

MVPのCHECKは `private / unlisted` のみ許可する。将来の `public` はここでは保存・認可を許可せず、導入時にCHECK・公開判定・切替UIをmigration等で拡張する。既存データの型変換やページ・写真モデルの作り直しを避けるが、将来変更をゼロにはしない。旧boolean案は未実装であり、現時点のデータ移行は不要。将来もし旧案のDBが存在する場合は、trueを一般公開へ自動変換せず別途移行判断する。

MVPの非参加者閲覧は `visibility = 'unlisted'` と共有リンクの検証をANDで満たすことが条件。非公開は写真・人数・サムネイルも返さない。一般公開の将来追加では旅行の閲覧判定を拡張し、既存の許可列・写真フラグ・メンバー編集判定を再利用する。メンバー用機能だけでMVP完成とは扱わない。

## 3. 型と共通の技術方針

| 用途 | PostgreSQL型・方針 |
| --- | --- |
| ID、ユーザー参照 | `uuid`。`profiles.id` は `auth.users.id` と同じ値。その他のPKは `DEFAULT gen_random_uuid()` |
| 名前・本文・パス | `text`。アイテム名は空文字不可。空白だけの扱い・文字数上限等は残件 |
| 旅行日・旅程日 | `date`。時刻やタイムゾーン変換を持ち込まない |
| 正確な時刻 | `time without time zone`。モデルの `time` を明示したもの。絶対時刻への変換、海外旅行のタイムゾーン、秒の入力可否は別途決定 |
| 作成・更新・参加日時 | `timestamptz NOT NULL DEFAULT now()`。DBで記録し、表示時に必要なタイムゾーンへ変換 |
| 順序・所要時間 | `integer`。小数や時刻順への置換は行わない |
| category・時間指定方法 | モデルどおり `text` + `CHECK`。PostgreSQL ENUMは導入しない |
| 旅行の公開範囲 | `text NOT NULL DEFAULT 'private'` + CHECK。MVPはprivate / unlisted |
| 写真の公開可否 | `boolean NOT NULL DEFAULT false`。限定公開と一般公開で共通の非参加者向けフィルタ |

`updated_at` のdefaultはINSERT時にしか働かない。`profiles`、`trips`、`itinerary_items` には `BEFORE UPDATE` トリガーで `NEW.updated_at = now()` とする技術案を採用する。`created_at`、`joined_at` は利用者による変更を許可せず、INSERT時もサーバー生成値とする。必要なトリガー・関数は初期migrationに含めた。

`now()` はトランザクション開始時刻であり、厳密な変更回数や競合検知用のバージョンではない。子の旅程更新で親の `trips.updated_at` を更新するかは未決定で、自動伝播は追加しない。

## 4. CREATE TABLE案

以下は型、NULL許可、PK / FK / CHECK / UNIQUEをレビューするためのDDL例である。RLS、GRANT、トリガー、Storage設定まで含む実行用スクリプトではない。

**採用した実装**：`trips.created_by` と `itinerary_photos.uploaded_by` は、既存のNOT NULLを維持し `ON DELETE NO ACTION` とする。参照が残るユーザーの物理削除を失敗させ、旅行・写真の意図しない消失を防ぐ。これは将来のアカウント削除機能・履歴保持仕様を確定するものではない。`SET NULL` の採用にはモデルのNullable変更が必要。

```sql
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY
    REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name text NOT NULL,
  avatar_path text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  thumbnail_path text,
  visibility text NOT NULL DEFAULT 'private',
  created_by uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trips_visibility_check CHECK (visibility IN ('private', 'unlisted')),
  CONSTRAINT trips_date_range_check CHECK (end_date >= start_date)
);

CREATE TABLE public.trip_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL
    REFERENCES public.trips (id) ON DELETE CASCADE,
  user_id uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trip_members_trip_user_key UNIQUE (trip_id, user_id)
);

CREATE TABLE public.itinerary_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL
    REFERENCES public.trips (id) ON DELETE CASCADE,
  date date NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  sort_order integer NOT NULL,
  time_type text NOT NULL DEFAULT 'none',
  exact_time time without time zone,
  time_period text,
  duration_minutes integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT itinerary_items_title_check CHECK (title <> ''),
  CONSTRAINT itinerary_items_time_period_check
    CHECK (time_period IS NULL OR time_period IN ('朝', '昼', 'おやつ', '夕方', '夜')),
  CONSTRAINT itinerary_items_category_check
    CHECK (category IN ('place', 'transportation')),
  CONSTRAINT itinerary_items_time_type_check
    CHECK (time_type IN ('none', 'exact', 'period')),
  CONSTRAINT itinerary_items_time_consistency_check CHECK (
    (time_type = 'exact' AND exact_time IS NOT NULL AND time_period IS NULL)
    OR (time_type = 'period' AND exact_time IS NULL AND time_period IS NOT NULL)
    OR (time_type = 'none' AND exact_time IS NULL AND time_period IS NULL)
  ),
  CONSTRAINT itinerary_items_sort_order_check CHECK (sort_order >= 0),
  CONSTRAINT itinerary_items_duration_check
    CHECK (duration_minutes IS NULL OR duration_minutes > 0)
);

CREATE TABLE public.itinerary_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  itinerary_item_id uuid NOT NULL
    REFERENCES public.itinerary_items (id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  is_public boolean NOT NULL DEFAULT false,
  uploaded_by uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

FKの参照先はモデルどおり `auth.users.id` とし、都合で `profiles.id` へ変更しない。全FKの `ON UPDATE` は既定の `NO ACTION` とし、IDの変更を通常操作として提供しない。

### 制約を追加しない項目

- `profiles.display_name` のUNIQUEは禁止。同名を許可する既存仕様に従う。
- `(trip_id, date, sort_order)` のUNIQUEは保留。モデルではMVP必須ではなく、並び替え方式と合わせて決定する。
- `storage_path` のUNIQUEは保留。同じオブジェクトの複数参照を許すか未決定。
- `display_name`、旅行の `name` の空文字・空白のみの扱いは未決定。旅程の `title` は必須入力のため空文字禁止を追加し、空白のみの扱いは保留。
- 写真は最大5枚を7節の処理で保証する。未確定の文字数上限・最大旅行日数・所要時間上限などは追加しない。

### FK削除の一覧

| 子カラム → 親 | ON DELETE | 状態・効果 |
| --- | --- | --- |
| `profiles.id` → `auth.users.id` | `CASCADE` | 既存仕様。プロフィール行を削除 |
| `trips.created_by` → `auth.users.id` | `NO ACTION` | 作成旅行があればユーザー削除を拒否 |
| `trip_members.trip_id` → `trips.id` | `CASCADE` | 既存仕様。旅行削除時に参加行を削除 |
| `trip_members.user_id` → `auth.users.id` | `CASCADE` | 既存仕様。ユーザー削除時に参加行を削除 |
| `itinerary_items.trip_id` → `trips.id` | `CASCADE` | 既存仕様。旅行削除時に旅程を削除 |
| `itinerary_photos.itinerary_item_id` → `itinerary_items.id` | `CASCADE` | 既存仕様。旅程削除時に写真メタデータを削除 |
| `itinerary_photos.uploaded_by` → `auth.users.id` | `NO ACTION` | アップロード履歴があればユーザー削除を拒否 |

`NO ACTION` のFKによりユーザー削除が失敗した場合、同じSQLトランザクション内のCASCADEもロールバックされる。Storageの削除はロールバックされないため、アカウント削除処理で先に画像を無条件削除しない。

## 5. Index案

PKとUNIQUEにはPostgreSQLがindexを作る。FKの子側には自動作成されないため、参照・削除確認・RLS・一覧取得に必要なものを追加する。

```sql
CREATE INDEX trips_created_by_idx
  ON public.trips (created_by);

CREATE INDEX trip_members_user_trip_idx
  ON public.trip_members (user_id, trip_id);

CREATE INDEX itinerary_items_trip_date_order_idx
  ON public.itinerary_items (trip_id, date, sort_order);

CREATE INDEX itinerary_photos_item_idx
  ON public.itinerary_photos (itinerary_item_id);

CREATE INDEX itinerary_photos_uploaded_by_idx
  ON public.itinerary_photos (uploaded_by);
```

| index | 主な用途 |
| --- | --- |
| `trips(created_by)` | 作成旅行の照会、ユーザー削除時のFK確認 |
| `trip_members(trip_id, user_id)`（UNIQUEによるもの） | 旅行メンバー一覧、対象旅行の所属確認、旅行削除時の子行検索 |
| `trip_members(user_id, trip_id)` | 自分の参加旅行一覧、ユーザー削除時の子行検索 |
| `itinerary_items(trip_id, date, sort_order)` | 日付タブ・旅行全体の旅程取得、旅行削除時の子行検索 |
| `itinerary_photos(itinerary_item_id)` | アイテムの写真一覧、RLSの親参照、旅程削除時の子行検索 |
| `itinerary_photos(uploaded_by)` | ユーザー削除時のFK確認 |

同じ先頭列を持つ単独indexは重複追加しない。検索要件のない名前・本文の全文検索indexも作らない。実装後にRLSを含む実際のクエリで `EXPLAIN (ANALYZE, BUFFERS)` を確認する。

旅程取得は日付指定時に `ORDER BY sort_order`、旅行全体では `ORDER BY date, sort_order` とする。indexがあるだけでは順序は保証されない。時刻・時間帯・推定時刻で並び替えない。`sort_order` が重複した場合の正式な順序は未決定であり、ID順を仕様として追加しない。

## 6. RLSとSQL権限

### 6.1 共通方針

5テーブルすべてで `ENABLE ROW LEVEL SECURITY` を行う。通常の書き込みはSupabase AuthのユーザーJWTを使用し、`TO authenticated` のpolicyとSQLのGRANTを両方設定する。

非参加者の閲覧はMVP要件であり、未ログインとログイン済み非メンバーの両方に対応する。6.3はメンバー向け基礎policy、6.7は公開用の取得契約を示す。公開用読取関数は実装した。排他処理等の残件は第11節に示す。ログイン要否やMVP採用自体を未決定に戻さない。閲覧のためのAuthユーザー作成・匿名サインインは要求しない。

通常のWeb操作でService Roleを常用しない。Service RoleやDB所有者はRLSを迂回できるため、管理処理にも明示的な認可が必要。Service Role Key、secret keyをクライアントへ渡さない。

### 6.2 所属判定と循環参照の回避

以下はpolicyで使用する判定の契約であり、関数名は技術提案である。

| 判定 | 意味 |
| --- | --- |
| `private.is_trip_member(trip_id)` | 現在の `auth.uid()` が非NULLで、同じ `trip_id, user_id` の参加行が存在する |
| `private.is_trip_creator(trip_id)` | 対象旅行の `created_by = auth.uid()` |
| `private.is_item_member(item_id)` | 対象アイテムが存在し、その `trip_id` のメンバーである |

`trip_members` のSELECT policy内から同じテーブルをRLS付きで再参照すると再帰する。`trips` と `trip_members` が互いのpolicyを経由する循環にも注意する。

判定関数はAPI非公開の `private` schemaに置く `STABLE SECURITY DEFINER` 関数を提案する。所有者を対象表のRLSを迂回できる管理ロールとし、必要な存在判定だけを行う。これにより再帰を避ける。`search_path = ''`、完全修飾テーブル名、固定SQLを用い、動的SQLを避ける。判定対象のユーザーIDを引数で受けず、関数内の `auth.uid()` を使う。

関数の既定の `PUBLIC` 実行権限をREVOKEし、policy評価に必要なロールに限りschemaのUSAGEと関数のEXECUTEを許可する。関数所有権の変更や `FORCE ROW LEVEL SECURITY` の導入は判定経路を変えるため、再帰・認可テストなしで行わない。書き込みRPCやトリガー関数は別途最小権限で設計し、一般的な任意テーブル操作関数にしない。

### 6.3 操作別policy案

以下は基礎テーブルに対するメンバー用policy案で、許可対象は `authenticated`。公開用の関数・配信経路は6.7に別記する。SELECT / DELETEは `USING`、INSERTは `WITH CHECK`、UPDATEは既存行の `USING` と更新後の `WITH CHECK` の両方に条件を設定する。「保留」はpolicyとGRANTを付けず、実装済み機能と扱わない。

| テーブル | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `profiles` | 本人の行。S08用の他者表示は6.7の旅行単位の取得経路で提供 | `id = auth.uid()`。S07の初回保存で作成 | 旧・新とも `id = auth.uid()`。更新可能列を限定 | 直接削除は保留。Auth削除に伴うCASCADEのみ既存仕様 |
| `trips` | 基礎表は `is_trip_member(id)`、公開取得は6.7 | `created_by = auth.uid()`。visibilityの初期値private | メンバーの基本情報編集。公開変更は作成者専用処理、期間短縮は確認済み専用処理。編集排他も検証 | 作成者のみ。編集排他とStorage清掃を伴う専用処理 |
| `trip_members` | `is_trip_member(trip_id)`。非参加者には行を公開しない | 一般ユーザーの直接追加は許可しない。作成者の初期行はトリガー、招待参加は検証済み専用処理 | 許可しない。参加行の付け替えを防止 | `user_id = auth.uid()` かつ `NOT is_trip_creator(trip_id)` |
| `itinerary_items` | `is_trip_member(trip_id)` | メンバー。対象日が並び替え中でないことと日付範囲を検証する専用処理 | メンバー。順序は日別編集権、メモは対象別編集権で検証。変更列を分けた専用処理 | メンバー。対象日の並び替え・対象アイテムの編集と調整する専用処理。画像清掃を伴う |
| `itinerary_photos` | 基礎表は `is_item_member(itinerary_item_id)`、公開取得は6.7 | メンバー、投稿者本人、初期値false。5枚上限と画像整合を専用処理で検証 | 差し替えは全メンバー・必ずfalseへリセット。公開設定の任意変更は作成者のみ | 全メンバー。専用処理でDBとStorageを削除 |

このmatrixは操作別の認可契約であり、一般ユーザーへ直接書き込みを一律GRANTする意味ではない。メンバー・作成者の判定に加え、編集排他・5枚制限・日付検証・公開リセット等をDB側で迂回不能にする。専用処理へ集約する操作では直接DMLをREVOKEする。並び替え中は対象日の別の並び替え・アイテム追加・削除・日付移動を禁止する。メモ・写真は並び替え中でも変更でき、同じメモ・同じ写真への変更は個別に競合を防ぐ。旅行削除・期間短縮では編集中のアイテムを消さないよう調整する。表中の編集権は操作別に判定し、並び替えの権利をメモ・写真にも一律要求しない。

従来の所属確認だけの旅程UPDATE policy例は、今回の操作別の競合防止を保証できないため採用しない。対象操作は7節の編集権検証と短いDBトランザクションを経由させる。RLS・GRANT・専用関数の実行権限をセットで実装する。

PostgreSQLの通常のpolicyは複数あるとORで結合される。後から追加する閲覧policyが書き込みまで開放しないよう、安易に `FOR ALL` を使用しない。UPDATEに必要なSELECT policyも併せて検証する。

### 6.4 行の認可だけでは保護できない列

RLSは列の不変性や旧値から新値への遷移を単独では保証しない。メンバーが `created_by` を変更して権限を奪わないよう、更新経路と列を限定する。以下は更新対象の契約であり、直接GRANTする列の一覧ではない。公開設定・期間短縮・旅程・写真は専用処理へ集約し、直接DMLをREVOKEする技術案とする。

| テーブル | 専用処理等で更新する列・条件 |
| --- | --- |
| `profiles` | `display_name`, `avatar_path` |
| `trips` | メンバー：`name`, `start_date`, `end_date`, `thumbnail_path`。`visibility` は作成者限定。期間短縮と編集排他は専用処理で検証 |
| `itinerary_items` | `date`, `category`, `title`, `description`, `sort_order`, `time_type`, `exact_time`, `time_period`, `duration_minutes` |
| `trip_members` | なし |
| `itinerary_photos` | `storage_path` の差し替えはメンバー、同時に `is_public = false`。`is_public` 単独切替は作成者のみ |

`DEFAULT false` だけではINSERT時のtrue指定や、差し替え時の公開状態継承を防げない。新規登録はfalseで作り、作成者の明示的な公開操作だけがtrueへ変更できる。差し替え処理は新パスとfalseを同一DB更新で確定し、作成者が差し替えた場合も例外にしない。一般メンバーは差し替えの結果としてfalseに戻せるが、公開状態だけを任意に切り替えられない。DB関数内で旧行・新値・操作種別を検証し、直接更新経路を残さない。

全PK、`created_by`、`uploaded_by`、作成・参加日時、親への所属FKは変更不可とする技術案。旅行間・旅程間の付け替え機能は仕様にないため提供しない。`updated_at` はトリガー専用。INSERTも列権限またはトリガーで監査日時の持ち込みを防ぐ。

画像パス列の更新権限だけでは、他旅行の画像パスを貼り付ける操作を防げない。パス整合をDB側で検証するか、当該列への直接書き込みをREVOKEして認可済みの専用処理に限定する。Storage側のRLSだけでDBへの不正なパス登録まで防げると考えない。

### 6.5 旅行作成・参加・退出

旅行作成時に `trips` と作成者の `trip_members` を必ず同じトランザクションで作る。技術案は `AFTER INSERT ON trips` の専用トリガーで作成者の参加行を追加する方式とする。トリガーは認証済み本人を `created_by` として受け入れる経路からのみ実行され、参加行を作る処理に限定する。通常ユーザーにはトリガー関数の直接EXECUTEを許可しない。

これにより、作成直後のSELECTに必要な所属情報も同じトランザクション内に存在し、作成途中の失敗でメンバーのない旅行を残さない。モデルが検討を認めているトリガーによる保証の具体案であり、メンバー概念の変更ではない。実装時はINSERTの `RETURNING` とSELECT policyも含めて確認する。

作成者以外の参加は招待URL経由とし、MVPではS08から旅行作成者だけが招待できる。発行処理は `trips.created_by = auth.uid()` をDB側でも検証する。参加時は認証ユーザーを識別し、招待の対象旅行と有効性を検証して参加行を追加する。`user_id = auth.uid()` だけの自己加入や、旅行閲覧URLだけによる加入は許可しない。

招待URLは発行から24時間有効。サーバーの発行日時と期限を保存し、認証・S07初回入力後、参加確定時に期限を再検証する。参加確認画面は設けず、登録成功後はS03（旅行一覧・ホーム）へ遷移する。同じ招待URLは有効期限内に複数人が利用でき、参加成功で消費・無効化しない。失効・転送可否は未決定。検証から参加行作成までの競合を防ぎ、再送で重複参加させない。URLプレビュー・先読みの単純なGETだけで参加行を作らず、ブラウザでの認証済み処理から保護された参加リクエストを送る。

招待検証情報の保存案は、API非公開領域に旅行参照・トークンのハッシュ（UNIQUE）・発行者・発行日時・有効期限を持つ専用テーブルとする。生トークンを旅行の取得結果やログへ残さない。旅行削除時はCASCADE、旅行参照へindexを設ける。一般ユーザーの直接SELECT / INSERT / UPDATE / DELETEは禁止し、作成者認可の発行処理とトークン検証の参加処理に限定する。複数人で再利用するため単一の使用済みフラグで消費しない。失効仕様決定後に必要列を具体化する。保存先と発行・参加RPCは初期migrationに実装した。

退出は自分の参加行だけを削除でき、作成者の退出・他者の強制退出は許可しない。退出で過去の `uploaded_by` は消さない。アップロード時のメンバー要件を、将来もメンバーであり続けるFK制約として実装しない。

### 6.6 CASCADEと写真削除の関係

旅行作成者は旅行を、メンバーは旅程を削除できるため、既存モデルのCASCADEによりその配下の写真メタデータも消える。子のDELETE policyを定義しなくても、FKのCASCADEは子のRLSによって同様には制限されない。

写真単体も全メンバーが削除可能と確定したため、親の旅程削除に伴う写真削除と権限上は整合する。親削除・期間短縮時も編集排他を守り、画像の削除対象をDB削除前に確保する。

### 6.7 非参加者閲覧・参加人数・プロフィールの取得

確定した取得範囲は以下のとおり。非参加者には未ログインとログイン済み非メンバーを含む。

| 対象 | メンバー | 非参加者 |
| --- | --- | --- |
| S05の旅行・日別旅程、C01の基本情報 | 公開状態によらず可 | 限定公開の共有リンクを検証できた旅行のみログイン不要。同じS05 |
| `description` の共有メモ | 閲覧・編集可 | 取得不可 |
| 参加者情報 | S08で表示名・任意画像を閲覧可 | 参加人数のみ。参加者行・表示名・画像は取得不可 |
| 写真 | 全写真を閲覧可 | `is_public = true` かつ写真公開条件を満たすものだけ |
| 書き込み | メンバー・作成者の操作別権限に従う | 不可 |

MVPの非参加者には `visibility = 'unlisted'` かつ有効な閲覧資格のある旅行だけを返す。写真にはさらに `itinerary_photos.is_public = true` を要求する。非公開旅行は写真の値にかかわらず旅程・人数・サムネイル・写真を返さない。将来の一般公開でも写真falseを返さず、メモ・投稿者情報・内部ユーザー参照も返さない。

**技術案：公開用・メンバー用の取得経路を分ける。** 基礎テーブルの旅程SELECTはメンバーに限定し、`anon` と `authenticated` が呼び出せる公開用の読み取り関数を用意する。関数は対象旅行の閲覧条件を検証し、S05・C01に必要な許可列だけを明示的に返す。`description`、作成者・投稿者ID、監査・制御情報を含む `SELECT *` は使わない。RLSだけで同じ行のメモ列を隠せると考えない。

非参加者の基礎テーブル直接取得はSQL権限とメンバー限定RLSで拒否し、公開関数だけを経由させる。ログイン済み非メンバーにもメモが漏れないよう検証する。公開関数でRLSを迂回する必要がある場合は、専用の最小権限所有者、固定SQL、空の `search_path`、完全修飾名、限定したEXECUTE権限と明示的な旅行認可を用いる。任意の列・条件を実行する汎用関数にはしない。安全なview等で同じ契約を満たす代替案も可能だが、直接取得の迂回を残さない。

参加人数は旅行閲覧条件を検証した取得経路から件数だけを返す。参加者行をブラウザへ渡して数えさせない。S08用のプロフィール取得は旅行IDと呼び出し元の所属を検証し、その旅行の参加者の表示名・画像だけを返す案とする。別旅行で同じユーザーのプロフィールを見る権限があっても、対象旅行の非メンバーにその参加関係を公開しない。プロフィールの自己編集権限は変更しない。

画像取得・署名付きURL発行にも同じ旅行単位の認可と写真公開判定を適用する。アバターは本人または認可されたS08用の経路、サムネイルはS05の旅行閲覧条件に従う。公開閲覧用の許可をINSERT / UPDATE / DELETEへ広げない。

### 6.8 限定公開の共有リンクと将来の一般公開

**技術案**：推測困難な閲覧用トークンを発行し、API非公開領域に旅行FK・トークンハッシュ（UNIQUE）・発行日時を保存する。参加招待とは別の資格とし、検証処理・保存先を分離する。旅行へのFKはCASCADE、旅行参照にindexを設ける。一般ユーザーの直接SELECT / INSERT / UPDATE / DELETEを禁止し、専用処理で管理する。発行権限・期限・失効・再発行仕様は未決定なので、対応列と管理操作は確定後に具体化する。旅行の公開範囲を変更できるのは作成者のみという条件は維持する。

S05と同じルートへトークンを渡す案とし、パスが同じでも資格のない旅行IDだけで閲覧を許可しない。生トークンを旅行・旅程の取得結果、ログ、他サイトへの参照情報へ漏らさず、検証情報を含む応答を認可の異なる利用者間でキャッシュ共有しない。

6.7の取得関数はトークン等を明示的に受け、対象旅行との対応・visibility・有効性を検証して許可列だけ返す。クライアントからの「検証済み」フラグは信用しない。基礎テーブルのanon SELECTを広げず、ログイン済み非メンバーにも同じ制限を適用する。人数取得・写真配信・署名付きURL発行もこの認可を経由させる。Storageの直接アクセスだけでは共有リンクの資格を検証できない設計の場合、認可済み配信処理へ限定して迂回を防ぐ。

将来は旅行閲覧判定に一般公開の分岐を追加する。メンバー判定、共有リンク検証、公開範囲判定、写真のis_publicフィルタを別の責務とし、`visibility != 'private'` の一律許可にはしない。MVPでは未知の値・public・検証できないトークンを拒否する。限定公開から非公開へ戻した後は既存リンクで旅行取得・新規画像URL発行を許可しない。発行済み画像URLの失効は8.3の残件とする。

## 7. 複数行・複数テーブルの整合性

### 旅程の一括保存と並び替え

既存旅程の基本項目・順序等はS05の「更新」で日単位に保存する。RPC等は `trip_id` と対象日を受け、同日・同旅行の変更だけを1つのDBトランザクションで適用する。ブラウザからの独立UPDATEの連続で部分保存させない。日付移動を提供する場合は移動元・先の両日を検証する専用処理とし、通常の日単位更新へ黙って混ぜない。

並び替え中は対象日の別の並び替え・アイテム追加・削除・日付移動を禁止する。並び替え本人も未保存の状態で追加しない。メモ・写真は並び替え中でも変更可能とし、同じメモ・同じ写真の変更だけを別途競合制御する。異なる日の並び替えを旅行全体の長時間ロックで禁止しない。

順序保存では `sort_order` だけ、メモ保存では `description` だけを変更する。基本項目を同時に保存する場合も明示的な変更列だけを送り、古いメモ・写真・変更していない項目を上書きしない。同じアイテム行の更新が重なる瞬間は短いDB行ロックで順番に処理する。写真は別テーブルだが、親削除・5枚上限との競合も検証する。ユーザーが操作している時間全体をDBトランザクションにはしない。

順序の一意性をDBで保証する場合は `UNIQUE (trip_id, date, sort_order) DEFERRABLE INITIALLY IMMEDIATE` を候補とし、並び替えトランザクション内だけ遅延させる。採番方式・採否は未決定で現DDLには含めない。所属確認だけのUPDATEを許可せず、専用処理で認可・編集権・変更列を検証する。

### 操作別の編集権と削除調整の技術案

有効期限付き編集権を使う案とする。業務データの `trip_days` は作らず、編集制御用の補助データとして管理する。

| 対象 | 排他キー案 | 保護する操作 |
| --- | --- | --- |
| 日の並び替え | `(trip_id, date)` | 同日の別の並び替え・追加・削除、移動元または先が対象日となる日付移動を拒否 |
| アイテムのメモ | `itinerary_item_id` とメモ種別 | 同じメモの編集・保存を競合させない。日の並び替え権とは独立 |
| 既存写真 | `photo_id` と写真種別 | 同じ写真の差し替え・削除・公開切替を競合させない。日の並び替え権とは独立 |

補助テーブルには対象へのFK・CASCADE、保有ユーザー、編集セッション識別子、有効期限、対象キーのUNIQUEを設ける。一般ユーザーの直接SELECT / INSERT / UPDATE / DELETEは許可せず、所属を検証した取得・更新・解放・状態取得の専用関数を使う。非参加者に編集者情報を返さない。具体的DDLは後続の実装設計で定める。

別タブ・別端末も同じユーザーIDだけでは権利を共有させない。取得後に最新データを再読込し、書き込みと同じ短いトランザクション内で期限・本人・セッションを再検証する。期限切れ・退出後・古いセッションの保存は拒否し、再取得だけで古い入力を自動送信しない。同一セッション内も保存要求を順序制御し、遅い古い要求が新しい入力を巻き戻さないようにする。リース期間・更新間隔・競合時の表示は残る技術・UX設計事項。

旅行削除・期間短縮は、削除対象の日の並び替え、アイテムのメモ編集、写真変更・アップロードの進行状況と調整する。操作開始から保存完了までの対象アイテム保護を保持し、アップロード中にも親を消さない。対象が編集中なら削除を実行せず、編集終了後に再確認する方式を技術案とする。待機・再試行のUIは未決定で、強制終了・強制削除機能は追加しない。

編集権取得と削除処理は、旅行行等の共通ガードを同じ順序で短くロックし、「編集中でないことの確認」と「削除」の間に新たな編集を開始させない。通常のメモ・写真保存と日の並び替えも必要な瞬間だけ直列化し、旅行全体の長時間占有はしない。個別アイテム削除でも同じ保護を検証する。期限切れのアップロードが後から完了してもDB登録は拒否し、未参照画像を清掃する。

日単位の基本項目編集についても、古い値の無条件上書きを防ぐ。変更した項目の読み込み時の値と現在値を比較して競合時に保存を拒否する方式等を候補とする。並び替え専用の権利を旅行全体の編集禁止へ拡張しない。

### 写真の枚数と差し替え

1アイテムにつき最大5枚。単純なCHECKや画面だけの件数確認では保証しない。専用のDB登録処理が親アイテムをロックして現在数と追加数を検証し、登録を同一トランザクションで行う。直接DMLを禁止し、全登録経路を同じ規約に従わせる。差し替えは既存行の新パスへの更新として扱い、6枚目を一時登録しない。

差し替え画像は新しいStorageキーへアップロードし、DBのパス更新と非公開リセットを一緒に確定する。同じキーを上書きすると、古い公開URLで新画像まで見える可能性があるため使用しない。旧画像は参照変更成功後に清掃する。`uploaded_by` は元の登録者を保持する技術案とし、差し替え者の監査履歴が必要かは別途検討する。投稿者は編集・削除権限の所有者ではない。

### メモ・写真・新規アイテムの保存

既存メモは `description` の単一テキストをC01内で即保存する。既存アイテムの写真アップロードも即時に保存処理を行い、S05の更新を待たない。即保存用の処理と既存旅程の一括更新は変更対象を分け、古いメモで上書きしない。並び替え用の編集権は要求せず、同じメモ・写真の個別の競合制御と削除防止に従う。メモ送信の契機、保存中の閉じる操作は未決定。

新規入力はモーダルの「保存」で親アイテム・メモ・写真を合わせて登録し、「キャンセル」では登録を確定しない。S05の更新待ちにはしない。DB内の親行・写真メタデータはトランザクションで整合させるが、Storageとは原子的にコミットできない。8.4の失敗処理と合わせて登録順序・補償・再試行を設計する。保存途中のキャンセル・部分失敗時のUIは未決定。

未保存の並び替え中は本人も新規追加できない。日単位更新または並び替えの破棄後に新規追加する。画面内の未送信状態はクライアントで管理するが、編集権・対象日・採番の整合性はサーバー/DBでも検証する。新規保存済みの行や即保存メモを古い一括更新で消さない。

### 旅行期間と旅程日

旅程日は原則として旅行期間内とし、MVPではアプリケーション側で検証する。単純なDB CHECKにはしない。サーバー保存処理が日付範囲を確認し、クライアントの入力チェックだけに依存しない。期間・旅程の更新は直接DMLを制限した専用処理へ集約し、検証を迂回させない。

期間短縮で範囲外アイテムがある場合、画面は「期間外になった旅程は削除されます。よろしいですか。」と確認し、メモ・写真も削除対象と併記する。了承後にサーバーが編集権と対象を再確認し、期間変更と範囲外アイテム・写真メタデータの削除を同一DBトランザクションで行う。キャンセルでは変更しない。

確認時から対象が変わった場合は、未確認の対象を黙って追加削除せず再確認を求める。削除する画像パスを先に確保して清掃を再試行できるようにする。DB CASCADEだけではStorage画像は消えない。

### プロフィールの作成

認証後にS07で表示名と任意画像を初回入力し、保存時に本人の `profiles` 行を作成する。同じ画面の通常保存では更新する。PK/FKはユーザー当たり最大1行を保証するが、入力前には行が存在しないことを許容する。初回入力未完了ならS07へ戻し、招待経由では入力完了後に参加処理へ復帰する。ログイン不要の旅行閲覧にはS07を要求しない。

本人IDを検証して作成し、再送で重複行を作らない。名前の自動生成やメールアドレスの流用、サインアップ時に名前を必須とする別フローは採用しない。メール確認等、初回入力の中断・再開UI、画像保存の失敗処理は残る設計事項とする。

## 8. Supabase Storageとの関係

### 8.1 Bucket・パスの技術案

用途ごとに以下のprivate bucketを使う案とする。名称は提案であり、ファイルサイズ・MIME制限は仕様決定後に設定する。

| 用途 | bucket案 | オブジェクトキー案 | DB上の参照 |
| --- | --- | --- | --- |
| プロフィール画像 | `avatars` | `<user_id>/<object_uuid>.<ext>` | `profiles.avatar_path` |
| 旅行サムネイル | `trip-thumbnails` | `<trip_id>/<object_uuid>.<ext>` | `trips.thumbnail_path` |
| 旅程写真 | `itinerary-photos` | `<trip_id>/<item_id>/<object_uuid>.<ext>` | `itinerary_photos.storage_path` |

各カラムの用途からbucketを一意に決め、DBにはbucket内のオブジェクトキーだけを保存する。署名付きURL、URLの期限、外部URLは保存しない。UUIDベースのキーで上書き衝突を避ける。拡張子だけで画像形式を信用せず、許可形式とファイル内容を検証する。

`storage.objects` への独自FKは作らない。DB行とオブジェクト本体の存在は別に確認し、アップロード成功後の参照登録失敗も処理する。Supabase管理テーブルをSQLで直接削除してもファイル本体の安全な削除処理にはならないため、アップロード・削除はStorage APIを使う。

### 8.2 Storage policy・配信認可案

`storage.objects` の各policyでは必ず `bucket_id` を限定する。パス中のUUIDは不正な値を安全に拒否し、パス文字列だけでなく実在する旅行・旅程・所属関係を確認する。ユーザーが任意のフォルダ名を作れることを前提にする。

| bucket | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `avatars` | 本人、または6.7の旅行所属を確認したS08用取得・URL発行経路。非参加者向けには返さない | 本人のuser_id配下 | 原則付与せず、新キーへのアップロードで置換 | 本人の画像の置換・後始末経路を候補とする。画像の削除UIは別途仕様化 |
| `trip-thumbnails` | メンバーと、6.7のS05閲覧条件を満たす非参加者 | 対象旅行のメンバー | 原則付与せず、新キーで置換 | 旅行編集権限による置換・旅行削除時の後始末 |
| `itinerary-photos` | 対応写真行と6.7の閲覧条件を検証 | 所属・対象・親削除との調整を確認。並び替え中も可。5枚制限はDB登録でも保証 | 直接上書きは許可せず、新キーへの差し替え | 全メンバーの認可済み削除処理、または親削除・失敗時の清掃処理 |

写真INSERTはまだ写真行がないアップロード段階のため、既存の写真行を必須にせず親旅程と所属を検証する。その後のメタデータ登録時は、実オブジェクトの存在、bucket、旅行・旅程とパスの一致、アップロード主体をサーバーまたはDB側で確認する。DBの `uploaded_by = auth.uid()` だけでは実際のアップロード者の証明にならない。

Storageの `owner_id` だけを旅行写真の閲覧権限に使用しない。アップロード者以外の旅行メンバーも閲覧できる必要がある。一方、失敗アップロードの後始末に必要なアップロード主体の確認には利用できる。投稿者に限らず全メンバーが写真単独削除できるため、`owner_id` だけでその権限を制限しない。

上表のSELECTは配信に必要な認可条件を示す。旅行文脈のないアバター直接SELECTを広く許可する意味ではなく、基礎オブジェクトの直接取得と認可済みサーバー配信のSQL権限を分離して実装する。

### 8.3 非参加者公開とURL

private bucketを使用し、認可済みダウンロードまたは署名付きURLで配信する案とする。public bucketではURLを知る相手がオブジェクトを取得でき、メンバー限定の写真要件に対応できない。

署名付きURLは期限内であれば受け取った人が利用でき、退出や公開設定の変更だけで即失効するとは限らない。URL有効期間と、退出・非公開化時にどこまで即時遮断するかは未決定。DBのSELECT policy、StorageのSELECT policy、URL発行処理で同じ閲覧条件を適用する。`is_public` に基づく非参加者への配信を有効にする際は、6.7の写真閲覧判定をDB・Storage・URL発行で共通にし、片方だけ緩めない。`is_public` はbucketのpublic設定ではなくDBの写真単位の値であり、`true` でもprivate bucketを利用できる。

同じStorageオブジェクトを複数の写真行で参照し、`is_public` が混在すると、公開側から取得した画像本体を非公開側だけ秘匿することはできない。複数参照の可否と公開設定の整合ルールは、非参加者配信の有効化前に決定する。無条件にどれか1行が公開なら配信可能とするpolicyを追加しない。

### 8.4 アップロード・置換・削除の失敗処理

DBトランザクションとStorage APIをまとめて原子的にコミットすることはできない。

新規モーダルの保存前は選択画像を登録済みと扱わない。現在のStorage INSERT案は実在する親アイテムを必要とするため、新規保存では親の作成とアップロードの順序・途中状態の公開防止・失敗時の補償を設計する必要がある。別案として一時アップロード領域を使う場合は、通常配信から隔離し、所有者・対象旅行を検証して確定・清掃する。方式は未採用であり、親存在チェックを単に外して対応しない。保存前キャンセルや途中失敗で生じた未参照画像の清掃と、再送時の重複防止も必要。

1. アップロード前に本人と対象旅行・旅程を認可する。
2. 新しいキーへアップロードし、DB登録時に権限とオブジェクト整合性を再確認する。
3. DB登録が失敗した場合は未参照オブジェクトを削除する。削除失敗は再試行可能に記録する。
4. 写真差し替えでは新パスとfalseの同時確定後に旧画像を清掃する。アバター・サムネイル置換は、新画像の参照をDBで確定してから旧画像を削除する。旧画像が他レコードから参照されていないことを確認する。
5. 旅行・旅程・写真を削除する場合、CASCADEでパス情報が消える前に削除対象を確保する。DB削除後にStorage APIで消し、失敗しても再試行可能にする。

旅行を消すと参加行も消え、ユーザーJWTではStorage削除の所属判定を満たせなくなる。後始末は、削除前に認可・確定した対象だけを扱うサーバー処理が必要。ブラウザから渡された任意パスをService Roleで削除してはならない。

削除対象の永続化には既存のジョブ基盤またはDBと同時に記録するoutboxが候補だが、現状どちらもない。プロセス停止を含む再試行を保証する方式は実装前に決める必要がある。追加テーブルは本提案では作らない。メモリ上にパスを持つだけの処理を「確実な削除」と扱わない。

削除と並行するアップロード・置換で取りこぼさないよう、DB側の操作を直列化し、親が消えて登録できなかった画像は未参照画像の後始末へ回す。参照共有の可否が未決定なので、単一行の削除だけで同じキーを無条件に消す設計は採用しない。プロフィール画像もAuthユーザー削除時に別途後始末が必要となる。

## 9. 未決定事項

今回確定したMVPの非公開・限定公開と将来の一般公開、作成者権限、写真5枚・差し替えリセット・非公開写真の保護、招待24時間・複数人利用・S03遷移、日単位保存・操作別排他、期間短縮時削除、時間帯5択を未決定へ戻さない。

| 分類 | 残る判断・設計 |
| --- | --- |
| 限定公開 | 閲覧用共有リンクの期限・失効・再発行・発行権限。一般公開は将来対応 |
| 認証 | メール確認、パスワード再設定、認証の中断・再開。方式はメール・パスワードとGoogleで確定 |
| 招待 | 失効・転送可否、上記残件に応じた保存構造 |
| 編集 | 編集権の期限・更新間隔・競合時UI、削除調整のUI、並び替えの採番・UNIQUE、日付切替・離脱時の未保存処理 |
| 保存 | メモ送信契機、写真操作の確定UI、途中失敗・補償・再試行 |
| 入力・画像 | 名前の空白だけの扱い・文字数、画像形式・容量・圧縮、写真表示順、同一オブジェクトの参照共有 |
| 時刻 | 秒、日跨ぎ、海外時刻。時間帯は朝・昼・おやつ・夕方・夜で確定 |
| 配信・削除 | 発行済み画像URLの失効、削除失敗の永続的な再試行方式 |
| プロフィール | 退出済み投稿者のメンバー向け表示 |
| アカウント削除 | MVP画面は追加しない。ユーザー参照FKはNO ACTIONを採用。将来の削除手順・履歴保持は未決定 |
| その他 | 子更新の旅行更新日時への伝播、将来の作成者移譲等は先回りして追加しない |


## 10. 実装前後の検証項目

以下を検証項目とする。隔離環境での結果と実Supabaseで未検証の範囲は第11節に示す。

- DDL：基礎5テーブルの全カラム・必須性・FKがモデルと一致し、同日旅行は成功、終了日逆転・負の順序・所要時間0・不正category・時間指定の矛盾・重複参加は失敗する。
- NULL：任意項目はNULL可能、必須項目はNULL不可。CHECK単独ではNULL拒否にならない箇所をNOT NULLで補えている。写真の `is_public` 省略時はfalse、明示NULLは拒否される。
- 追加制約：旅行のvisibility初期値privateとMVPでpublicを拒否すること、空のアイテム名と5択外の時間帯の拒否、5枚目成功・6枚目拒否（同時登録含む）を確認する。
- 排他：同日の並び替え中は別の並び替え・追加・削除・日付移動を拒否する。別日の並び替えとメモ・写真変更は成功し、順序保存で内容を巻き戻さない。同じメモ・写真の競合、別タブ、期限切れ・退出後の保存を拒否する。日付移動は元・先の両日を確認する。
- 期間短縮・旅行削除：キャンセルは無変更、了承後は期間と範囲外旅程・写真メタデータを一括更新する。編集中・アップロード中の対象を消さず、新規編集開始との競合も検証する。対象変化時は再確認し、DB削除後に画像を清掃する。
- 公開：メンバーは写真のtrue / false両方を閲覧できる。非参加者はfalseを閲覧できず、trueでも決定した旅行・写真の公開条件を満たさなければ拒否される。閲覧許可で書き込みや公開設定変更が可能にならない。
- 公開情報：未ログインとログイン済み非メンバーが有効な限定公開リンクからS05・C01を閲覧でき、メモ・参加者行・表示名・アバター・投稿者IDを取得できない。直接テーブルアクセス、公開関数、画像URL発行を含めて検証する。人数だけが返り、メンバーのS08表示は成功する。
- 招待・プロフィール：非作成者の発行を拒否し、発行後24時間で参加不可となる。認証・S07後にも期限を再検証し、確認画面なしで登録する。再送で参加・プロフィールを重複させず、同じURLで複数の認証ユーザーが参加でき、成功後にS03へ遷移する。
- 保存単位：既存メモと写真の即保存、新規モーダルの保存・キャンセルを検証する。一括更新で即保存メモや新規登録を巻き戻さず、DB・Storageの部分失敗を全成功と扱わない。
- 公開設定：通常メンバーの旅行・写真公開切替を拒否する。新規写真はfalse、全メンバーの差し替えでfalseへ戻り、作成者のみ再公開できる。パス差し替えとリセットを分離できず、古いURLで新画像を取得できないことを確認する。
- RLS：未認証・非参加者・通常メンバー・作成者・退出済みユーザーで全表のSELECT / INSERT / UPDATE / DELETEを実際のJWTから検証する。管理者接続だけでテストしない。
- 権限：他者を作成者／投稿者に偽装できない。作成者・親FK・監査日時を書き換えられない。自己加入、他者退出、作成者退出、非作成者の旅行削除が拒否される。
- トランザクション：旅行作成失敗で片方の行だけ残らない。作成直後の返却・SELECTが成立する。一括保存失敗で部分更新されず、同時編集でも採用した順序制約を守る。
- 再帰：所属判定が無限再帰にならず、関数やview経由でRLSを迂回して情報を取得できない。viewを追加する場合も呼び出し元の権限を使う設計か確認する。
- 削除：旅行→参加・旅程→写真のCASCADE、ユーザー参照のNO ACTION、失敗時のロールバックを確認する。既存の写真単独削除policyが親CASCADEを止めると誤認しない。
- Storage：別旅行のパス、偽のitem_id、不正UUID、他者の画像登録、権限のないURL発行が拒否される。DBとStorageの閲覧条件が一致する。
- 障害：アップロード後のDB失敗、DB削除後のStorage失敗、プロセス停止、退出、削除とアップロードの競合、再試行を検証する。DBにないファイルと実体のない参照を検出できる。
- 既存データ：実装時にデータが存在する場合は制約違反候補と画像参照を調査し、補正・削除の判断をせずに制約を強行しない。

初期DB・Storage policyの実装と検証状況は第11節を参照。残る主な設計課題は編集排他の詳細、招待条件、StorageとDBの非原子性、発行済みURLの扱いである。

### 残る専用処理の実装前に判断する事項

- 閲覧用共有リンクの期限・失効・再発行・発行権限を確定し、日別・対象別の編集権とともに補助テーブル・取得関数へ反映する。
- 参照共有・順序制約、画像清掃の永続的再試行方式を決める。ユーザー参照FKはNO ACTIONを採用済み。
- 公開用取得、編集権、5枚上限、差し替えリセット、招待検証、期間短縮の一括処理をmigrationと権限テストで具体化する。

画面設計を含む確定事項は再承認待ちにしない。MVPは限定公開までとし、一般公開を先に有効化しない。閲覧リンクの残る仕様を独断でmigrationへ埋め込まない。

検証には、トークンなし・不正トークン・別旅行のトークン・招待トークンの閲覧への流用を拒否すること、非公開化後の既存リンク拒否、写真falseのDB・Storage両方での保護も含める。限定公開の成功応答を、無資格ユーザーへの共有キャッシュから取得できないことを確認する。

## 11. 初期migrationの実装状況（2026-09-28）

現在のDB設計を確定済みとして実装した。第4節のDDL・FK・indexを採用し、`trips.created_by` と `itinerary_photos.uploaded_by` のON DELETEはNO ACTIONで確定した。MVP全機能の完成を意味しない。実Supabaseへの適用と履歴確認は利用者が完了している。

実ファイルと実行手順は [supabase/README.md](../supabase/README.md) を参照する。

| migration | 実装内容 |
| --- | --- |
| [initial_schema](../supabase/migrations/20260927000100_initial_schema.sql) | 基礎5テーブル、制約、5本の補助index、RLSとGRANT、所属判定、監査・作成者参加トリガー、写真5枚・公開リセットの保護、旅行作成・公開範囲変更・S08取得RPC |
| [member_invitations](../supabase/migrations/20260927000200_member_invitations.sql) | private.trip_invitations、トークンハッシュ、24時間、作成者のみ発行、認証・初回プロフィール後の複数人参加と再送時の重複防止 |
| [private_storage](../supabase/migrations/20260927000300_private_storage.sql) | private bucket 3つ、メンバー向け読取・アバター等のINSERT policy、直接上書き・削除を防ぐ制限、初回アバター紐付けRPC |
| [shared_read_api](../supabase/migrations/20260928000100_shared_read_api.sql) | private.trip_share_links、限定公開の許可列取得、公開写真の配信対象パス検証。発行機能は未実装 |

### 実装した認可と未開放の操作

- プロフィールは本人のみSELECT / INSERT / 表示名UPDATE。画像パスは任意の列UPDATEを許可せず、アップロード済み・本人所有の確認を行うRPCで初回紐付ける。置換・削除には清掃処理が必要なため未開放。
- 旅行・参加行・旅程・写真はメンバー向けSELECT policy。旅行INSERT・UPDATE・DELETEには基礎policyを作成したが、一般ユーザーへの直接GRANTは付けていない。旅行作成と公開範囲変更は専用RPC、参加行INSERTはトリガーまたは招待RPCに限定。退出は本人かつ非作成者だけにDELETEを許可する。
- 旅程・写真のINSERT / UPDATE / DELETEは日別・対象別の編集権、サーバー日付検証、画像整合性・清掃と組み合わせる必要がある。今回この専用書き込み経路は未実装。所属確認だけのpolicyを代用せず、直接DMLも未開放。写真保護トリガーは整合性の補助であり、編集権付きの登録・差し替え機能が完成したことは意味しない。
- 旅行の基本情報編集・期間短縮・削除も専用処理が未実装。作成者DELETE policy自体は実装・検証したが、実際の削除APIとしてはまだ使えない。Storage清掃と編集中データの保護を迂回する直接DELETEは許可しない。
- `ryoko_reader` はNOLOGIN・NOBYPASSRLSの読取専用関数所有者。基礎表にこの内部ロールだけのSELECT policyを置き、再帰を避ける。APIロールに内部ロールを継承させず、関数は空のsearch_pathと固定SQLを使用する。通常のメンバー判定・公開取得の関数に書込権限を持たせない。
- 書込RPCと作成者参加トリガーはpostgres所有のSECURITY DEFINERで、引数でユーザーIDを指定させずauth.uid()を検証する。トリガー関数はクライアントへEXECUTEを許可しない。
- 共有リンク管理の期限・発行権限等は本文に明示的な残件があるため、アプリからの発行・変更・削除は未実装。共有リンク行は一般ユーザーから作成できず、本検証では一時的なfixtureだけを用いる。現時点の読取は保存済みハッシュと旅行状態を検証する範囲であり、期限・失効管理を実装済みとは扱わない。実リンクの発行を開始する前に管理仕様を確定して拡張する。
- 非参加者は基礎表のSELECT不可。共有RPCはメモ・ユーザー参照を除外し、写真falseを返さない。Storageのanon直接読取は不可で、許可パスを検証したサーバー配信・署名URL発行は別途必要。DB関数だけで画像本体を配信するものではない。

### 発見した問題と対応

1. 旧AGENTS.mdには非参加者閲覧・写真権限・期間短縮を未決定とする記述があった。最新仕様に追随させ、確定事項を再判断していない。
2. 第6節の認可matrixだけでは日付・競合・画像清掃を保証できない。policyとGRANTを分け、未実装の専用処理を直接DMLで代用しない。
3. 作成者参加のAFTER INSERTトリガーとINSERT RETURNINGのSELECT policy評価には順序上の注意がある。作成RPC内で旅行と参加行を同一トランザクションに作成し、作成直後のSELECTを検証した。
4. 同じStorageオブジェクトを複数写真行が共有する場合の公開ルールは残件。配信対象パスRPCは重複参照を検出するとエラーにし、勝手に「1行でも公開なら配信」を採用しない。これは未対応ケースであり、DBにstorage_pathのUNIQUEを追加したものではない。
5. 新規アイテムと写真の一括保存はDBとStorageをまたぐため、SQLトランザクションだけでは実現できない。親作成・アップロード・失敗補償の方式と永続的な清掃処理は未実装。
6. Storageに既存の緩いpolicyがある場合のOR結合を考慮し、対象3bucketにrestrictive policyを追加した。他bucketはこの制限の対象外とする。

### 検証結果と限界

PGlite 0.5.8で4本のmigrationを順番に適用し、制約・FK削除・SQLロールとauth.uid()に相当するclaimsによるRLS・招待・限定公開取得・Storageメタデータpolicyを検証した。テストはROLLBACKし、認証ユーザーのfixtureが残らないことを確認した。

実SupabaseのAuth / PostgREST / Storage HTTP・実ファイル・署名URL・複数接続での競合は未検証。初期実装時はDocker・Supabase CLI・psqlがローカルに見当たらずリモート未適用だったが、その後2026-09-28に利用者がCLIで4本のmigrationを適用し、Local / Remoteの履歴一致を確認した。今回のアプリ基盤実装ではリンク済み実DBからpublic schemaの型生成にも成功した。テストで管理者として写真データを投入したことを、一般ユーザー向け書き込み機能の検証と混同しない。

追加のリポジトリ検証：npm run lint・npm run build・git diff --checkは成功した。エディタのproblems取得はツールエラーで利用できなかった。

### 認証UIからのプロフィール操作

表示名の初回INSERTと本人UPDATEを実装した。ユーザーJWTと既存RLS・列GRANTを利用し、Service Roleや追加migrationは使用しない。画像・招待・旅行CRUDは今回追加していない。設定と確認は [認証UIガイド](./auth-ui.md) を参照。

### メンバー向け旅行読取

旅行一覧・旅行本体の詳細を取得するserver専用関数を追加した。既存のtrips_select_member policyとユーザーJWTを利用し、migration・書き込み処理は変更していない。取得列、エラー、ページ取得、未認証・非参加者・退出後の検証は [旅行読取ガイド](./trip-reads.md) を参照。