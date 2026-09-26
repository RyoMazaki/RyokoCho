# Supabase / PostgreSQL DB実装設計案

## 1. 位置付けと前提

本書は実装前の提案であり、確定済みのmigrationではない。DB、RLS、Storageへの適用は行わない。

参照資料：

- [product.md](./product.md)
- [requirements.md](./requirements.md)
- [data_model.md](./data_model.md)
- [AGENTS.md](../AGENTS.md)
- [decisions.md](./decisions.md)

既存コードはNext.jsの初期画面が中心で、Supabaseクライアント、DB定義、migrationはまだ存在しない。既存DBからの移行を前提にしない。

以下の3つを区別する。

- **既存仕様**：資料で明記されている型、関係、制約、権限。
- **技術提案**：既存仕様を実現するためのdefault、index、トランザクション、権限実装。
- **未決定事項**：プロダクト判断や資料間の整合が必要な内容。権限を推測して付与しない。

対象は `public.profiles`、`public.trips`、`public.trip_members`、`public.itinerary_items`、`public.itinerary_photos` の5テーブルとする。認証はSupabase管理の `auth.users` を利用する。`trip_days`、category別詳細テーブル、メンバーのroleは追加しない。

## 2. 確定した方針と将来の拡張

以下は [decisions.md](./decisions.md) に記録した確定事項であり、未決定の選択肢として扱わない。

| 論点 | 確定方針 | DB実装設計への反映 |
| --- | --- | --- |
| 非参加者の旅行閲覧 | 将来必須。メンバーは閲覧・編集可能、非参加者は編集不可で閲覧を許可できる設計 | メンバー判定と閲覧判定を分離。MVPでの提供範囲・ログイン要否・誰でも公開か共有リンク限定か・旅行単位の公開範囲の値は保留 |
| 写真の公開設定 | 写真単位の `is_public boolean NOT NULL DEFAULT false` | モデルとDDLに追加。`false` はメンバー限定、`true` は非参加者への閲覧許可の対象。認証・共有条件や非公開旅行の写真単独公開は保留 |
| 旅行期間外の旅程 | 原則として旅行期間内。MVPではアプリ検証 | 単純なDB CHECKにはしない。期間短縮時の既存範囲外アイテムの扱いは保留 |
| 時間の整合性 | `exact` は正確な時刻のみ必須、`period` は時間帯のみ必須、`none` は両方NULL | DB CHECKで保証する確定仕様としてDDLに反映 |
| category | `place` と `transportation` の2種類 | `place` に場所・その場所で行うこと・滞在中の行動を含め、`action` は追加しない |

写真の `is_public` は確定したモデル変更であり、旅行単位の公開状態を表すものではない。既存の型・参照先は維持する。ユーザー削除FKの暫定保護案は別途採否を確認する。

### 旅行の公開制御に必要となるデータモデル案（未採用）

現時点で旅行の公開用カラムは追加しない。ログイン要否・全体公開とリンク限定の選択・公開範囲の値が未決定であり、booleanだけを先に追加すると複数の公開方法を表現しきれない可能性があるためである。

- 旅行単位で公開範囲を切り替える場合：`trips` に公開範囲を表す属性を追加する候補。名称、型、値、既定値は公開仕様決定後に定義する。
- 共有リンクを採用する場合：リンクの検証情報を旅行または別の共有リンクエンティティに保持する候補。複数リンク、失効、有効期限の要否で構造を選ぶ。生の秘密トークンを閲覧可能な旅行行に保存しない。
- 追加時期の代替案：公開方式まで決めてからカラムを設計する方法と、先に非参加者閲覧を提供せずメンバー機能を実装し、後のmigrationで公開制御を追加する方法がある。後者でも閲覧権限を参加行や編集権限と結び付けない。

公開範囲や共有トークンの列を追加した場合、非参加者に内部の制御情報までSELECTさせない。旅行・旅程・プロフィール・写真で返してよい情報も個別に決める。現行モデルが永続化できるのは写真単位の公開可否までであり、旅行の公開方法はこれから設計する。

## 3. 型と共通の技術方針

| 用途 | PostgreSQL型・方針 |
| --- | --- |
| ID、ユーザー参照 | `uuid`。`profiles.id` は `auth.users.id` と同じ値。その他のPKは `DEFAULT gen_random_uuid()` |
| 名前・本文・パス | `text`。文字数・空文字の仕様が未決定のため独自の上限や空文字禁止を加えない |
| 旅行日・旅程日 | `date`。時刻やタイムゾーン変換を持ち込まない |
| 正確な時刻 | `time without time zone`。モデルの `time` を明示したもの。絶対時刻への変換、海外旅行のタイムゾーン、秒の入力可否は別途決定 |
| 作成・更新・参加日時 | `timestamptz NOT NULL DEFAULT now()`。DBで記録し、表示時に必要なタイムゾーンへ変換 |
| 順序・所要時間 | `integer`。小数や時刻順への置換は行わない |
| category・時間指定方法 | モデルどおり `text` + `CHECK`。PostgreSQL ENUMは導入しない |
| 写真の公開可否 | `boolean NOT NULL DEFAULT false`。NULLを許可せず、追加の値域CHECKは不要 |

`updated_at` のdefaultはINSERT時にしか働かない。`profiles`、`trips`、`itinerary_items` には `BEFORE UPDATE` トリガーで `NEW.updated_at = now()` とする技術案を採用する。`created_at`、`joined_at` は利用者による変更を許可せず、INSERT時もサーバー生成値とする。必要なトリガー・関数は将来migrationに含める。

`now()` はトランザクション開始時刻であり、厳密な変更回数や競合検知用のバージョンではない。子の旅程更新で親の `trips.updated_at` を更新するかは未決定で、自動伝播は追加しない。

## 4. CREATE TABLE案

以下は型、NULL許可、PK / FK / CHECK / UNIQUEをレビューするためのDDL例である。RLS、GRANT、トリガー、Storage設定まで含む実行用スクリプトではない。

**暫定提案**：`trips.created_by` と `itinerary_photos.uploaded_by` は、既存のNOT NULLを維持し `ON DELETE NO ACTION` とする。参照が残るユーザーの物理削除を失敗させ、旅行・写真の意図しない消失を防ぐ。これはアカウント削除仕様を確定するものではなく、migration作成前に採否を確認する。`SET NULL` の採用にはモデルのNullable変更が必要。

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
  created_by uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
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
  time_type text NOT NULL,
  exact_time time without time zone,
  time_period text,
  duration_minutes integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
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
- `time_period` の値リストは未決定。例示された「朝」「おやつ」などを確定値としてCHECKにしない。
- `display_name`、`name`、`title` の `NOT NULL` は空文字や空白のみを禁止しない。その追加制約は仕様決定後に検討する。
- 写真数上限、文字数上限、最大旅行日数、所要時間上限などを独自に追加しない。

### FK削除の一覧

| 子カラム → 親 | ON DELETE | 状態・効果 |
| --- | --- | --- |
| `profiles.id` → `auth.users.id` | `CASCADE` | 既存仕様。プロフィール行を削除 |
| `trips.created_by` → `auth.users.id` | `NO ACTION` | 暫定案。作成旅行があればユーザー削除を拒否 |
| `trip_members.trip_id` → `trips.id` | `CASCADE` | 既存仕様。旅行削除時に参加行を削除 |
| `trip_members.user_id` → `auth.users.id` | `CASCADE` | 既存仕様。ユーザー削除時に参加行を削除 |
| `itinerary_items.trip_id` → `trips.id` | `CASCADE` | 既存仕様。旅行削除時に旅程を削除 |
| `itinerary_photos.itinerary_item_id` → `itinerary_items.id` | `CASCADE` | 既存仕様。旅程削除時に写真メタデータを削除 |
| `itinerary_photos.uploaded_by` → `auth.users.id` | `NO ACTION` | 暫定案。アップロード履歴があればユーザー削除を拒否 |

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

非参加者向けSELECTは将来必須の拡張として設計する。`anon` / `authenticated` のどちらに許可するかと具体的な公開条件は未決定のため、実行可能な公開policyはまだ定義しない。メンバー向けpolicyだけの状態は、公開機能完成形ではなく未決定の経路を閉じた設計下限である。Supabaseの匿名サインインはDB上で `authenticated` になり得るため、その採用有無もログイン要件と合わせて決める。

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

以下の許可対象は `authenticated`。SELECT / DELETEは `USING`、INSERTは `WITH CHECK`、UPDATEは既存行の `USING` と更新後の `WITH CHECK` の両方に条件を設定する。「保留」はpolicyとGRANTを付けず、実装済み機能と扱わない。

| テーブル | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `profiles` | `id = auth.uid()`。他者プロフィールの閲覧範囲は保留 | `id = auth.uid()`。プロフィール作成経路の候補 | 旧・新とも `id = auth.uid()`。更新可能列を限定 | 直接削除は保留。Auth削除に伴うCASCADEのみ既存仕様 |
| `trips` | `is_trip_member(id)` | `created_by = auth.uid()` | 旧・新とも `is_trip_member(id)`。作成者等は変更不可 | `created_by = auth.uid()` |
| `trip_members` | `is_trip_member(trip_id)` | 一般ユーザーの直接追加は保留。作成者の初期行は専用トリガー経由 | 許可しない。参加行の付け替えを防止 | `user_id = auth.uid()` かつ `NOT is_trip_creator(trip_id)` |
| `itinerary_items` | `is_trip_member(trip_id)` | `is_trip_member(trip_id)` | 旧・新とも `is_trip_member(trip_id)`。親旅行は変更不可 | `is_trip_member(trip_id)` |
| `itinerary_photos` | メンバーは `is_item_member(itinerary_item_id)`。非参加者は6.7の公開条件を決定後に追加 | メンバーかつ `uploaded_by = auth.uid()`。公開設定者が未決定の間は `is_public = false` のみ。Storage整合チェックも必要 | `is_public` の更新経路は必要だが、設定可能な人が未決定のため保留。差し替え等も保留 | 単独写真の削除権限が未決定のため保留 |

このmatrixはメンバー向けの基礎となる。非参加者閲覧と写真公開設定の必要性・保存形式は確定しているが、公開条件と設定者の権限は未決定であり、決定後にpolicyを追加する。他者プロフィール表示と招待も別途決定が必要。

旅程更新policyの構文例（判定関数とGRANTは別途必要）：

```sql
CREATE POLICY itinerary_items_update_member
ON public.itinerary_items
FOR UPDATE TO authenticated
USING (private.is_trip_member(trip_id))
WITH CHECK (private.is_trip_member(trip_id));
```

PostgreSQLの通常のpolicyは複数あるとORで結合される。後から追加する閲覧policyが書き込みまで開放しないよう、安易に `FOR ALL` を使用しない。UPDATEに必要なSELECT policyも併せて検証する。

### 6.4 行の認可だけでは保護できない列

RLSは列の不変性を保証しない。メンバーが `trips.created_by` を自分へ変更すると旅行削除権限を奪えるため、次の更新可能列だけをGRANTする案とする。テーブル全体のUPDATE権限を残すと列制限を迂回できるためREVOKEする。

| テーブル | 通常ユーザーが更新可能な列 |
| --- | --- |
| `profiles` | `display_name`, `avatar_path` |
| `trips` | `name`, `start_date`, `end_date`, `thumbnail_path` |
| `itinerary_items` | `date`, `category`, `title`, `description`, `sort_order`, `time_type`, `exact_time`, `time_period`, `duration_minutes` |
| `trip_members` | なし |
| `itinerary_photos` | `is_public` が更新対象の候補。設定者の権限決定後にこの列のみ許可し、決定前は付与しない |

`DEFAULT false` だけではINSERT時に `true` を指定する操作を防げない。設定者の仕様決定まではINSERTのWITH CHECKに `is_public = false` を含め、UPDATEも許可しない技術案とする。これは公開設定機能の廃止や完成を意味しない。決定後はINSERT時の `true` 指定とUPDATEによる切り替えの両方を同じ設定権限で検証する。公開閲覧できることを設定変更権限に使わない。

全PK、`created_by`、`uploaded_by`、作成・参加日時、親への所属FKは変更不可とする技術案。旅行間・旅程間の付け替え機能は仕様にないため提供しない。`updated_at` はトリガー専用。INSERTも列権限またはトリガーで監査日時の持ち込みを防ぐ。

画像パス列の更新権限だけでは、他旅行の画像パスを貼り付ける操作を防げない。パス整合をDB側で検証するか、当該列への直接書き込みをREVOKEして認可済みの専用処理に限定する。Storage側のRLSだけでDBへの不正なパス登録まで防げると考えない。

### 6.5 旅行作成・参加・退出

旅行作成時に `trips` と作成者の `trip_members` を必ず同じトランザクションで作る。技術案は `AFTER INSERT ON trips` の専用トリガーで作成者の参加行を追加する方式とする。トリガーは認証済み本人を `created_by` として受け入れる経路からのみ実行され、参加行を作る処理に限定する。通常ユーザーにはトリガー関数の直接EXECUTEを許可しない。

これにより、作成直後のSELECTに必要な所属情報も同じトランザクション内に存在し、作成途中の失敗でメンバーのない旅行を残さない。モデルが検討を認めているトリガーによる保証の具体案であり、メンバー概念の変更ではない。実装時はINSERTの `RETURNING` とSELECT policyも含めて確認する。

作成者以外の参加経路は招待方式が未決定。`user_id = auth.uid()` だけで自由にINSERT可能にすると、旅行IDを知る利用者が勝手に参加して編集できるため採用しない。招待を採用する場合は有効期限・本人確認・再利用可否などを確認する専用処理が必要。

退出は自分の参加行だけを削除でき、作成者の退出・他者の強制退出は許可しない。退出で過去の `uploaded_by` は消さない。アップロード時のメンバー要件を、将来もメンバーであり続けるFK制約として実装しない。

### 6.6 CASCADEと写真削除の関係

旅行作成者は旅行を、メンバーは旅程を削除できるため、既存モデルのCASCADEによりその配下の写真メタデータも消える。子のDELETE policyを定義しなくても、FKのCASCADEは子のRLSによって同様には制限されない。

したがって「写真単体の削除権限が未決定」と「親の削除に伴う写真の削除」は区別する。アップロード者だけが写真を消せる仕様等を今後採用する場合、親削除も制限するのか、親削除は例外なのかを決める必要がある。

### 6.7 将来の非参加者閲覧と写真の公開判定

以下は条件の分離を示す論理式であり、未決定条件を含むためそのまま実行するSQLではない。

```text
旅行の閲覧 = 旅行メンバー OR 非参加者向け旅行公開条件を満たす
写真の閲覧 = 写真の旅行メンバー
             OR (is_public = true AND 非参加者向け写真公開条件を満たす)
```

非参加者向け写真公開条件には、今後決定する認証・共有条件と旅行の公開状態との関係を含める。旅行の閲覧が必須になるか、非公開旅行でも写真単独公開を認めるかは未決定。`is_public = true` のみのSELECT policyは作らない。逆に、旅行の公開policyを写真にそのまま適用して `false` の写真まで見せない。

メンバーSELECTとは別のSELECT専用policyを追加できる構造にし、INSERT / UPDATE / DELETEのメンバー・作成者判定を流用・拡張しない。非参加者には書き込みを許可せず、閲覧を可能にする目的で参加行を追加しない。旅程やメンバー一覧にどこまで公開を広げるかも公開仕様に合わせて決める。

写真単独公開を採用する場合、親旅程を経由するRLS付きJOINだけでは親の非公開policyで写真閲覧も拒否される可能性がある。親を公開して回避するのではなく、必要最小限の存在・公開条件だけを検証する判定関数等を検討する。Storageの認可にも同じ写真閲覧判定を使用し、非公開の親・参加者情報を漏らさない。

## 7. 複数行・複数テーブルの整合性

### 旅程の一括保存と並び替え

[requirements.md](./requirements.md) の更新ボタンに合わせ、複数アイテムの保存は1つのDBトランザクションで行うRPC等を提案する。ブラウザから複数の独立したUPDATEリクエストを送るだけでは途中失敗で部分保存される。

RPCでは各アイテムの所属旅行と呼び出しユーザーの権限を確認し、対象旅行の行ロック等で同じ旅行の並び替えを直列化する。すべての関連書き込みが同じロック規約に従う必要がある。RLSを活かす `SECURITY INVOKER` を基本とし、DEFINERが必要な場合も引数だけを信用しない。

順序の一意性をDBで保証する場合は `UNIQUE (trip_id, date, sort_order) DEFERRABLE INITIALLY IMMEDIATE` を候補とし、並び替えトランザクション内だけ遅延させる。一時的な重複は許してコミット時に検証できるが、deferrable UNIQUEは `ON CONFLICT` の競合判定対象として使えない。採否、保存後の重複、採番方式は未決定であり、現DDLには含めない。

ロックは同時処理を直列化するだけで、古い画面の保存による上書きを検出しない。競合時に拒否するか、上書きするか、再読込を求めるかは未決定。バージョン列等を先回りして追加しない。

### 旅行期間と旅程日

`itinerary_items.date` は原則として旅行期間内とし、MVPではアプリケーション側で検証する確定仕様とする。技術案としてサーバー側の保存処理で `start_date <= date <= end_date` を確認し、クライアントの入力チェックだけに依存しない。旅行期間短縮時には既存の範囲外アイテムを検出するが、その後の拒否・削除・移動等の挙動は未決定とする。

他テーブルを読む関数をCHECKに埋め込む方式は採用しない。親更新時の再検証を自動で保証できないためである。直接Data API書き込みを許す場合、このアプリ検証は迂回でき、RLSも日付整合性までは保証しない。

厳密なDB保証が必要になった場合は、直接変更権限を限定して全更新を共通のトランザクション処理へ集約するか、親子両側のトリガーとロックを検討する。これはモデルのMVP方針を強化する追加設計になるため、必要性を確認してから採用する。期間外データを削除・移動する仕様は独断で追加しない。

### プロフィールの作成

PK/FKは「ユーザー当たり最大1行」を保証するが、Authユーザー全員に必ずプロフィールがあることまでは保証しない。サインアップ時の表示名入力・作成タイミングは未決定。名前を勝手に生成したり、メールアドレスを表示名に流用したりしない。

表示名を受け取って本人の行を作成する処理、またはAuth作成トリガーが候補。後者は失敗するとサインアップ全体に影響するため、必須入力や再試行を決めてから実装する。

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

### 8.2 Storage policy案

`storage.objects` の各policyでは必ず `bucket_id` を限定する。パス中のUUIDは不正な値を安全に拒否し、パス文字列だけでなく実在する旅行・旅程・所属関係を確認する。ユーザーが任意のフォルダ名を作れることを前提にする。

| bucket | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `avatars` | 本人。他者に見せる範囲はプロフィール閲覧仕様待ち | 本人のuser_id配下 | 原則付与せず、新キーへのアップロードで置換 | 本人の画像の置換・後始末経路を候補とする。画像の削除UIは別途仕様化 |
| `trip-thumbnails` | 対象旅行のメンバー。非参加者向けは保留 | 対象旅行のメンバー | 原則付与せず、新キーで置換 | 旅行編集権限による置換・旅行削除時の後始末 |
| `itinerary-photos` | 対応する写真行が存在し、6.7の写真閲覧判定を満たす。現段階の具体的許可はメンバー向け、非参加者向けは公開条件決定後 | パスのtrip_idに所属し、item_idが実際に同じ旅行に属する | 写真差し替え仕様未決定のため付与しない | 写真単独削除は保留。親削除や失敗アップロードの後始末は認可済みサーバー処理 |

写真INSERTはまだ写真行がないアップロード段階のため、既存の写真行を必須にせず親旅程と所属を検証する。その後のメタデータ登録時は、実オブジェクトの存在、bucket、旅行・旅程とパスの一致、アップロード主体をサーバーまたはDB側で確認する。DBの `uploaded_by = auth.uid()` だけでは実際のアップロード者の証明にならない。

Storageの `owner_id` だけを旅行写真の閲覧権限に使用しない。アップロード者以外の旅行メンバーも閲覧できる必要がある。一方、失敗アップロードの後始末に必要なアップロード主体の確認には利用できる。写真単独の削除権限へ読み替えない。

### 8.3 非参加者公開とURL

private bucketを使用し、認可済みダウンロードまたは署名付きURLで配信する案とする。public bucketではURLを知る相手がオブジェクトを取得でき、メンバー限定の写真要件に対応できない。

署名付きURLは期限内であれば受け取った人が利用でき、退出や公開設定の変更だけで即失効するとは限らない。URL有効期間と、退出・非公開化時にどこまで即時遮断するかは未決定。DBのSELECT policy、StorageのSELECT policy、URL発行処理で同じ閲覧条件を適用する。`is_public` に基づく非参加者への配信を有効にする際は、6.7の写真閲覧判定をDB・Storage・URL発行で共通にし、片方だけ緩めない。`is_public` はbucketのpublic設定ではなくDBの写真単位の値であり、`true` でもprivate bucketを利用できる。

同じStorageオブジェクトを複数の写真行で参照し、`is_public` が混在すると、公開側から取得した画像本体を非公開側だけ秘匿することはできない。複数参照の可否と公開設定の整合ルールは、非参加者配信の有効化前に決定する。無条件にどれか1行が公開なら配信可能とするpolicyを追加しない。

### 8.4 アップロード・置換・削除の失敗処理

DBトランザクションとStorage APIをまとめて原子的にコミットすることはできない。

1. アップロード前に本人と対象旅行・旅程を認可する。
2. 新しいキーへアップロードし、DB登録時に権限とオブジェクト整合性を再確認する。
3. DB登録が失敗した場合は未参照オブジェクトを削除する。削除失敗は再試行可能に記録する。
4. アバター・サムネイル置換は、新画像の参照をDBで確定してから旧画像を削除する。旧画像が他レコードから参照されていないことを確認する。
5. 旅行・旅程・写真を削除する場合、CASCADEでパス情報が消える前に削除対象を確保する。DB削除後にStorage APIで消し、失敗しても再試行可能にする。

旅行を消すと参加行も消え、ユーザーJWTではStorage削除の所属判定を満たせなくなる。後始末は、削除前に認可・確定した対象だけを扱うサーバー処理が必要。ブラウザから渡された任意パスをService Roleで削除してはならない。

削除対象の永続化には既存のジョブ基盤またはDBと同時に記録するoutboxが候補だが、現状どちらもない。プロセス停止を含む再試行を保証する方式は実装前に決める必要がある。追加テーブルは本提案では作らない。メモリ上にパスを持つだけの処理を「確実な削除」と扱わない。

削除と並行するアップロード・置換で取りこぼさないよう、DB側の操作を直列化し、親が消えて登録できなかった画像は未参照画像の後始末へ回す。参照共有の可否が未決定なので、単一行の削除だけで同じキーを無条件に消す設計は採用しない。プロフィール画像もAuthユーザー削除時に別途後始末が必要となる。

## 9. 未決定事項

以下は本書で仕様を確定していない事項である。

| 分類 | 決定が必要な内容 | 実装への影響 |
| --- | --- | --- |
| 旅行の公開範囲 | MVPの提供範囲、非参加者のログイン要否、誰でも閲覧可能か共有リンク限定か、旅行単位の公開範囲の値、閲覧できる項目・メンバー一覧 | 閲覧機能は将来必須。非参加者向けSELECTと公開情報のデータモデルを具体化 |
| 写真の公開条件・設定権限 | 設定できる人（INSERT時も含む）、非参加者の認証・共有条件、非公開旅行の写真単独公開、サムネイルとの関係 | 写真単位・boolean・NOT NULL・default falseは確定済み。DB・Storageの公開policyと設定変更権限を具体化 |
| 他者プロフィール | 同じ旅行のメンバー、公開旅行の閲覧者、退出済み投稿者などをどこまで表示するか | profilesとavatarsのSELECT。メンバー表示を含むMVPの前提 |
| プロフィール作成 | 表示名をいつ入力し、いつ行を作るか。未作成ユーザーをどう扱うか | Auth連携、作成処理、欠落行の補完 |
| 参加・招待 | 誰が誰を招待できるか、承諾の要否、招待の有効期限・再利用、ユーザー検索 | 参加INSERTの認可。招待の保存先が必要かも決定 |
| 写真の編集・単独削除 | 編集・差し替えの有無、削除可能な人、親削除の例外関係 | 写真・StorageのUPDATE / DELETE |
| アカウント削除 | 物理／論理削除、作成旅行の扱い、履歴の保持・匿名化、削除権限の引継ぎ | `created_by` / `uploaded_by` のFK削除動作とNullable。暫定NO ACTIONの採否 |
| 旅行期間短縮 | 既存の範囲外アイテムをどう扱うか | 原則期間内・MVPのアプリ検証・単純CHECK不使用は確定。短縮時の挙動のみ要判断 |
| 時間 | `time_period` の許可値、自由入力可否、時刻の秒・24時表記、海外・日跨ぎ時の扱い | CHECK追加、UI入力、タイムゾーンを表すモデルの要否 |
| 順序と同時編集 | 保存後の順序重複可否、UNIQUE採否、採番、競合時の扱い | 一括保存RPC・ロック・競合検出方式 |
| テキスト | 表示名・旅行名・タイトルの空文字・空白のみの扱い、文字数上限 | 追加CHECKと入力バリデーション |
| 画像制限 | 形式・容量・枚数上限、圧縮・リサイズ、写真サムネイル生成 | bucket制限、サーバー検証、必要なら派生画像管理 |
| 画像参照 | 同一Storageオブジェクトの複数参照を許すか | パスUNIQUEの採否、削除時の参照確認 |
| 配信と削除 | URL有効期間、権限喪失時の即時遮断、削除失敗の再試行・永続記録方式 | Storage配信経路、ジョブ／outbox等の必要性 |
| 追加メタデータ | 撮影日時、写真順序、コメント・説明、EXIF、旅行の説明 | 現段階ではカラムを追加しない |
| 将来の参加管理 | 作成者移譲・管理者概念・強制退出、旅行別の表示名 | 現状のroleなし・作成者退出不可を維持。実現する場合は別途モデル見直し |
| 更新日時 | 旅程等の子更新を旅行の更新日時へ反映するか | トリガー追加の要否。現状は各行自身の更新のみ |

## 10. 実装前後の検証項目

本書作成時点ではDBやStorageへの適用・動作確認は行っていない。migration実装時には少なくとも以下を検証する。

- DDL：5テーブルの全カラム・必須性・FKがモデルと一致し、同日旅行は成功、終了日逆転・負の順序・所要時間0・不正category・時間指定の矛盾・重複参加は失敗する。
- NULL：任意項目はNULL可能、必須項目はNULL不可。CHECK単独ではNULL拒否にならない箇所をNOT NULLで補えている。写真の `is_public` 省略時はfalse、明示NULLは拒否される。
- 公開：メンバーは写真のtrue / false両方を閲覧できる。非参加者はfalseを閲覧できず、trueでも決定した認証・共有・親旅行条件を満たさなければ拒否される。閲覧許可で書き込みや公開設定変更が可能にならない。
- 公開設定：INSERTでのtrue持ち込みとUPDATEによる切り替えを同じ設定権限で制御する。非公開化後のDB・Storage・発行済みURLは採用した失効方針どおりとなる。
- RLS：未認証・非参加者・通常メンバー・作成者・退出済みユーザーで全表のSELECT / INSERT / UPDATE / DELETEを実際のJWTから検証する。管理者接続だけでテストしない。
- 権限：他者を作成者／投稿者に偽装できない。作成者・親FK・監査日時を書き換えられない。自己加入、他者退出、作成者退出、非作成者の旅行削除が拒否される。
- トランザクション：旅行作成失敗で片方の行だけ残らない。作成直後の返却・SELECTが成立する。一括保存失敗で部分更新されず、同時編集でも採用した順序制約を守る。
- 再帰：所属判定が無限再帰にならず、関数やview経由でRLSを迂回して情報を取得できない。viewを追加する場合も呼び出し元の権限を使う設計か確認する。
- 削除：旅行→参加・旅程→写真のCASCADE、ユーザー参照のNO ACTION、失敗時のロールバックを確認する。既存の写真単独削除policyが親CASCADEを止めると誤認しない。
- Storage：別旅行のパス、偽のitem_id、不正UUID、他者の画像登録、権限のないURL発行が拒否される。DBとStorageの閲覧条件が一致する。
- 障害：アップロード後のDB失敗、DB削除後のStorage失敗、プロセス停止、退出、削除とアップロードの競合、再試行を検証する。DBにないファイルと実体のない参照を検出できる。
- 既存データ：実装時にデータが存在する場合は制約違反候補と画像参照を調査し、補正・削除の判断をせずに制約を強行しない。

本提案の主要な未解消リスクは、未確定の旅行公開方法と写真の公開条件・設定権限、参加・写真削除権限、StorageとDBの非原子性、アプリ検証を迂回した期間不整合と保存競合である。写真の公開可否を保存するモデルは確定済みであり、公開機能の必要性や写真単位の管理を未決定へ戻さない。

### DB migration作成前に人間が判断する事項

- 初回migrationの実装範囲：非参加者閲覧を含めるか。含めない場合は、メンバー向けpolicyと `is_public` の保存だけを先行し、非参加者への許可と公開設定変更を保留する段階案を採るか。
- 非参加者閲覧を含める場合：ログイン要否、公開対象・共有リンク方式、旅行の公開範囲の値、非公開旅行の写真単独公開、返してよい情報、公開設定者、同一画像の複数参照を決める。
- アカウント削除を先送りする場合を含め、ユーザー参照FKの暫定 `NO ACTION` を採用するか。採用するならユーザー削除が拒否されることを許容するか。
- 初回で参加・プロフィール表示・写真削除を実装する範囲に応じ、招待、他者プロフィールの閲覧、写真単独削除と親CASCADEの関係を決める。
- 順序UNIQUE・参照共有の制約採否と、Storage削除の永続的な再試行方式を選ぶ。旅行期間短縮時の挙動は、その保存処理の実装までに決める。

確定した5項目は再承認待ちにしない。公開条件が未決定のまま、無条件公開のpolicyや公開範囲の値をmigrationに埋め込まない。
