## profiles

旅行帳上で使用するユーザーのプロフィール情報を管理する。

認証情報はSupabase Authの `auth.users` が管理し、`profiles` には旅行帳独自のユーザー情報のみを保持する。

`auth.users` と `profiles` は1対1の関係とする。認証後にS07で表示名・任意画像を初回入力し、保存時に本人のプロフィールを作成する。同じ画面で通常の更新も行う。初回入力前はプロフィール未作成状態を許容し、再開時にS07へ戻す。招待経由なら初回入力後に参加処理へ戻る。公開旅行の閲覧だけならプロフィール入力は不要。

### Columns

| Column         | Type        | Nullable | Description                   |
| -------------- | ----------- | -------: | ----------------------------- |
| `id`           | uuid        |       NO | PK。`auth.users.id` と同じ値を使用する  |
| `display_name` | text        |       NO | 旅行帳上で表示するユーザー名                |
| `avatar_path`  | text        |      YES | プロフィール画像のSupabase Storage上のパス |
| `created_at`   | timestamptz |       NO | 作成日時                          |
| `updated_at`   | timestamptz |       NO | 更新日時                          |

### Relations

* `id` → `auth.users.id`
* `auth.users` と `profiles` は1対1
* 旅行への参加情報は `trip_members.user_id` を通してユーザーと紐付ける

```text id="4w7r1d"
auth.users
    │
    │ 1:1
    ▼
 profiles

auth.users
    │
    │ 1:N
    ▼
trip_members
```

### Authentication

ログイン・メールアドレス・パスワードなどの認証に関する情報は `profiles` では管理しない。

以下の情報はSupabase Authの `auth.users` が管理する。

* ユーザーID
* メールアドレス
* パスワード認証
* 外部プロバイダーによる認証情報

`profiles.id` には対応する `auth.users.id` と同じUUIDを使用する。

### Display Name

`display_name` は旅行帳内で他のユーザーから見える名前として使用する。

主に以下の画面での利用を想定する。

* 旅行の参加メンバー一覧
* 写真をアップロードしたユーザーの表示
* その他、ユーザーを識別する必要がある画面

`display_name` は必須とする。

表示名はユーザーを一意に識別するためのIDとしては使用しない。

そのため、複数ユーザーが同じ `display_name` を使用することを許可する。

### Avatar

ユーザーは任意でプロフィール画像を設定できる。

画像ファイルそのものはDBには保存せず、Supabase Storageに保存する。

`avatar_path` にはSupabase Storage上の画像を特定するためのパスを保持する。

プロフィール画像の設定は任意とする。

### Constraints

* `id` は `auth.users.id` を参照する
* 1つの `auth.users` に対して1つの `profiles` のみ存在できる
* `display_name` は必須
* `display_name` の重複を許可する

### Access Control

ユーザーは自分自身のプロフィールを編集できる。

```text id="j46cnw"
profiles.id = auth.uid()
```

を満たす場合のみ、プロフィールの更新を許可する。

他のユーザーのプロフィールを編集することはできない。

旅行メンバーはS08で同じ旅行の参加者の表示名・任意のプロフィール画像を閲覧できる。非参加者には対象旅行の参加者一覧・表示名・画像を返さず、S05では人数のみを返す。公開写真の投稿者表示からも漏らさない。退出済み投稿者をメンバー向けにどう表示するかは未決定。具体的な取得経路はDB実装設計で扱う。

### Design Decisions

#### auth.usersとprofilesを分離する

認証に関する情報はSupabase Authに任せ、旅行帳独自のプロフィール情報のみ `profiles` で管理する。

アプリケーション独自のユーザー情報を `auth.users` に直接持たせない。

#### auth.users.idをprofilesのPKとして使用する

`profiles` 独自のユーザーIDは作成せず、`auth.users.id` と同じUUIDを `profiles.id` として使用する。

これにより、認証ユーザーとプロフィールを1対1で対応させる。

#### 表示名は一意にしない

ユーザーを識別するためにはUUIDを使用するため、`display_name` にUNIQUE制約は設定しない。

同じ表示名を複数のユーザーが使用することを許可する。

### 未決定事項

* `display_name` の文字数制限
* プロフィール画像のファイルサイズ・形式制限
* 退出済みの写真投稿者のプロフィールをメンバーへどう表示するか
* ユーザー検索はMVPに追加しない。将来の採否は別途検討
* 旅行ごとに表示名の使い分けを可能にするか


## trips

1つの旅行を表す。

旅行帳における旅程・参加メンバー・写真などの情報は、すべて旅行を基準として管理する。

### Columns

| Column       | Type        | Nullable | Description |
| ------------ | ----------- | -------: | ----------- |
| `id`         | uuid        |       NO | PK          |
| `name`       | text        |       NO | 旅行名         |
| `start_date` | date        |       NO | 旅行開始日       |
| `end_date`   | date        |       NO | 旅行終了日       |
| `thumbnail_path` | text | YES | 旅行のサムネイル画像のSupabase Storage上のパス |
| `created_by` | uuid        |       NO | 旅行を作成したユーザー |
| `created_at` | timestamptz |       NO | 作成日時        |
| `updated_at` | timestamptz |       NO | 更新日時        |

### Relations

* `created_by` → `auth.users.id`
* 1つの `trip` は複数の `trip_members` を持つ
* 1つの `trip` は複数の `itinerary_items` を持つ
* `itinerary_items.trip_id` → `trips.id`

想定される関係：

```text
auth.users
    │
    │ created_by
    ▼
  trips
    │
    ├── trip_members
    │
    └── itinerary_items
            │
            └── itinerary_photos
```

### Dates

旅行期間は `start_date` と `end_date` で管理する。

`trip_days` テーブルは作成しない。

各旅程アイテムが属する日付は `itinerary_items.date` で管理する。

例：

```text
trip

name       = 京都旅行
start_date = 2026-10-10
end_date   = 2026-10-12
```

```text
itinerary_items

date        sort_order  title
----------  ----------  ----------------
2026-10-10      1       東京駅
2026-10-10      2       新幹線
2026-10-10      3       京都駅
2026-10-11      1       清水寺
2026-10-11      2       昼食
2026-10-12      1       ホテルをチェックアウト
```

### Thumbnail

旅行には任意でサムネイル画像を設定できる。

サムネイル画像は旅程アイテムに紐づく写真とは別に扱い、
Supabase Storage上の画像パスを `thumbnail_path` に保持する。

サムネイル画像の設定は任意とする。

### Constraints

* `name` は必須
* `start_date` は必須
* `end_date` は必須
* `created_by` は必須
* `end_date` は `start_date` と同日、またはそれ以降とする

`itinerary_items.date` は原則として `start_date` 〜 `end_date` の範囲内とする。DBの単純なCHECKでは保証せず、MVPではアプリケーション側で検証する。旅行期間短縮時に既存の範囲外アイテムをどう扱うかは未決定とする。

### Access Control

- 旅行メンバーは旅行を閲覧できる
- 旅行メンバーは旅行情報を編集できる
- 旅行そのものを削除できるのは `created_by` に該当するユーザーのみ
- 非参加者に編集権限は与えない
- MVPでは非参加者もログイン不要で、メンバーと同じ旅行URLのS05・C01を閲覧できる。参加情報は人数のみとし、S08・メモ・非公開写真を取得させない

メンバーのアクセス権は所属する `trip` を基準にする。非参加者の閲覧判定はメンバーの編集判定と分離し、閲覧許可のために `trip_members` へ登録しない。写真には写真単位の `is_public` も適用する。

### Design Decisions

#### trip_days テーブルを作成しない

旅行の日付を独立したエンティティとして管理する要件が現時点では存在しないため、`trip_days` テーブルは作成しない。

旅行期間は `trips.start_date` と `trips.end_date` で管理する。

各旅程アイテムの日付は `itinerary_items.date` で直接管理する。

将来的に「1日単位のタイトル・メモ・その他の情報」を管理する必要が生じた場合は、`trip_days` に相当するテーブルの追加を再検討する。

#### 旅行をアクセス制御の基準とする

メンバーの閲覧・編集は旅行への所属を基準とする。非参加者にはログイン不要の閲覧のみを許可する。旅行単位の公開範囲の値・管理方法は未決定であり、公開制御の具体化はDB実装設計で扱う。

旅程写真は `itinerary_photos.is_public` で写真単位の公開可否を管理する。旅行の公開条件と写真の公開可否の組み合わせは別途決定し、旅行を閲覧できるだけで `is_public = false` の写真まで公開しない。

### 未決定事項

* 旅行URLの配布UI、旅行単位の公開制御の詳細（MVPの閲覧・ログイン不要・共通URLは確定）
* 旅行単位の公開範囲をどのような値・データで管理するか
* 将来の管理者概念。MVPでは追加せず、作成者は `created_by` で判定する
* 旅行期間短縮時に既存の範囲外アイテムをどう扱うか
* 旅行名以外の説明などを `trips` 自体に持たせるか

## trip_members

旅行に参加しているユーザーを管理する。

1つの旅行には複数のユーザーが参加でき、1人のユーザーも複数の旅行に参加できるため、`trips` と `auth.users` の中間テーブルとして使用する。

旅行メンバー間では通常の編集・閲覧権限を区別せず、`trip_members` への登録によってメンバー権限を判断する。非参加者への閲覧許可は、この参加情報とは別に扱う。

### Columns

| Column      | Type        | Nullable | Description |
| ----------- | ----------- | -------: | ----------- |
| `id`        | uuid        |       NO | PK          |
| `trip_id`   | uuid        |       NO | 参加している旅行    |
| `user_id`   | uuid        |       NO | 参加ユーザー      |
| `joined_at` | timestamptz |       NO | 旅行に参加した日時   |

### Relations

* `trip_id` → `trips.id`
* `user_id` → `auth.users.id`
* 1つの `trip` は複数の `trip_members` を持つ
* 1人のユーザーは複数の `trip_members` を持つ

### Constraints

* `trip_id` は必須
* `user_id` は必須
* 同じユーザーを同じ旅行に重複して登録しない

同一ユーザーの重複参加を防ぐため、以下の組み合わせにUNIQUE制約を設定する。

```text id="4f0n7u"
UNIQUE (trip_id, user_id)
```

### Access Control

メンバーとしての旅行閲覧・編集権限は、対象旅行の `trip_members` への登録で判断する。非参加者のMVP閲覧は参加登録とは別に許可し、ログインや参加行の追加を要求しない。非参加者に編集権限は与えない。

旅行メンバーは以下の操作を行うことができる。

* 旅行の閲覧
* 旅行情報の編集
* `itinerary_items` の作成・編集・削除
* 写真の追加

旅行作成者についても `trip_members` に登録する。

旅行作成者かどうかは `trip_members` ではなく `trips.created_by` によって判断する。

### 参加者表示と招待

S08はメンバーだけが参加者の表示名・任意画像を確認できるモーダルとする。非参加者向けには人数のみを返し、参加者行を取得させない。

MVPでは作成者のみがS08から招待でき、受け取った人は招待URLから参加する。参加時には認証ユーザーを識別し、検証済みの招待に基づき `trip_members` を追加する。旅行の閲覧URLだけで自己加入させない。

招待URLの検証情報は参加済みの状態とは別の責務であり、招待管理の永続化方法は期限・失効等の仕様と合わせて設計する。現時点で未確定の招待テーブル・カラムを追加しない。

### 旅行の削除

旅行そのものを削除できるのは、その旅行を作成したユーザーのみとする。

```text id="36odnl"
trips.created_by = auth.uid()
```

を満たすユーザーのみ旅行を削除できる。

通常の旅行メンバーは旅行を削除できない。

### 旅行からの退出

旅行作成者以外のメンバーは、自分自身の `trip_members` レコードを削除することで旅行から退出できる。

他のメンバーの `trip_members` レコードを削除することはできない。

旅行作成者は旅行から退出できない。

旅行への参加を終了したい場合、旅行作成者は旅行そのものを削除する必要がある。

### Design Decisions

#### roleを持たない

旅行メンバー間で編集・閲覧権限を区別しないため、`trip_members` に `role` カラムは持たせない。

旅行に参加しているすべてのユーザーは、同じ基本的な閲覧・編集権限を持つ。

旅行の削除とMVPの招待権限は例外として扱い、`trips.created_by` によって判断する。

#### 旅行作成者もtrip_membersとして管理する

旅行作成者も通常の旅行メンバーとして `trip_members` に登録する。

これにより、旅行データの閲覧・編集については作成者と他のメンバーで共通のアクセス判定を使用できる。

作成者だけに許可される操作についてのみ `trips.created_by` を確認する。

### 未決定事項

* 将来の他者強制退出。MVPでは追加しない
* 将来の作成者移譲。MVPでは追加しない
* 招待URLの有効期限・再利用・失効・転送可否、参加確認、管理データの具体的構造


## itinerary_items

旅行中の旅程を構成する1つのアイテムを表す。

場所・移動などを別々の旅程テーブルとして管理せず、すべて `itinerary_items` として管理する。

旅程は時刻ではなく、ユーザーが設定した順序を基準として管理する。

### Columns

| Column        | Type        | Nullable | Description       |
| ------------- | ----------- | -------: | ----------------- |
| `id`          | uuid        |       NO | PK                |
| `trip_id`     | uuid        | NO       | このアイテムが属する旅行 |
| `date`        | date        |       NO | このアイテムが属する旅行日 |
| `category`    | text        |       NO | アイテムの種類     |
| `title`       | text        |       NO | 旅程上に表示するタイトル |
| `description` | text        |      YES | 補足情報・メモ     |
| `sort_order`  | integer     |       NO | その日の旅程内での表示順 |
| `time_type`   | text        |       NO | 時間の指定方法     |
| `exact_time`  | time        |      YES | 正確な時刻を指定する場合に使用 |
| `time_period` | text        |      YES | 大まかな時間帯を指定する場合に使用 |
| `duration_minutes`| integer |      YES | 予定所要時間（分）。`place` では滞在時間、`transportation` では移動時間 |
| `created_at`  | timestamptz |       NO | 作成日時           |
| `updated_at`  | timestamptz |       NO | 更新日時           |

### Memo and Saving

`description` はアイテムごとに1つの任意の共有テキストメモとする。メモ用の別テーブルやコメント列は追加しない。C01で旅行メンバーが閲覧・追加・編集でき、非参加者には本文を返さない。公開用の旅程取得とメンバー向け取得を分離する。

既存メモと既存アイテムへの写真アップロードはC01内で即保存する。既存旅程の基本項目・順序等はS05の「更新」で保存し、即保存済みのメモを古い値で上書きしない。

新規アイテムは入力モーダルの「保存」で親アイテム・メモ・写真を合わせて登録し、キャンセルでは登録を確定しない。写真本体とDBの保存・失敗処理はDB実装設計で扱う。未保存の並び替え中の新規追加、同時編集、送信契機等は [screens.md](./screens.md) の未決定事項に従う。

### Category

`category` は旅程アイテムの種類を表す。

初期バージョンでは以下を使用する。

| Value            | Meaning          |
| ---------------- | ---------------- |
| `place`          | 訪れる場所、その場所で行うこと、滞在中の行動 |
| `transportation` | 場所から場所への移動       |

#### place

訪れる場所、その場所で行うこと、滞在中の行動を表す。独立した `action` categoryは追加しない。

例：

* 東京駅
* ホテルに荷物を預ける
* 昼食
* 清水寺を観光する
* カフェ

#### transportation

場所から場所への移動を表す。

例：

* 新幹線
* バス
* 徒歩

初期バージョンでは `place` と `transportation` を同じ `itinerary_items` テーブルで管理する。

category固有の情報が増えた場合は、将来的に以下のような詳細テーブルへの分離を検討する。

* `place_details`
* `transportation_details`

初期バージョンでは詳細テーブルを作成しない。

### time_type

旅行帳では旅程の順序と時刻を別の概念として扱う。

すべての旅程アイテムに時刻を設定する必要はない。

`time_type` は以下の値を持つ。

| Value    | Meaning    |
| -------- | ---------- |
| `none`   | 時間指定なし     |
| `exact`  | 正確な時刻を指定   |
| `period` | 大まかな時間帯を指定 |

#### exact

正確な時刻が重要な予定に使用する。

例：

* 09:00 東京駅集合
* 10:30 新幹線出発
* 18:30 レストラン予約

`time_type = exact` の場合、`exact_time` はNOT NULL、`time_period` はNULLとする。

#### period

正確な時刻を決める必要がない予定に使用する。

例：

* 朝
* 昼
* おやつ
* 夕方
* 夜

`time_type = period` の場合、`exact_time` はNULL、`time_period` はNOT NULLとする。

`time_period` の具体的な値は別途決定する。

#### none

時間を設定する必要がない予定に使用する。

`time_type = none` の場合、`exact_time` と `time_period` はともにNULLとする。

### duration_minutes

旅程アイテムにかかる予定所要時間を分単位で保持する。

* `category = place` の場合は滞在時間
* `category = transportation` の場合は移動時間

設定は任意とする。

### Ordering

旅程の正式な表示順には `sort_order` を使用する。

`sort_order` は同一の `trip_id` と `date` の組み合わせの中での順序を表す。

例：

京都旅行 10/10
1 東京駅
2 新幹線
3 京都駅

京都旅行 10/11
1 清水寺
2 昼食

ユーザーが旅程を並び替えた場合は `sort_order` を更新する。

### Relations

* `trip_id` → `trips.id`
* 1つの `trip` は複数の `itinerary_items` を持つ
* 1つの `itinerary_item` は複数の `itinerary_photos` を持つことができる
* `itinerary_photos.itinerary_item_id` → `itinerary_items.id`

### Constraints

* `title` は必須
* `category` は定義された値のみ許可する
* `time_type` は定義された値のみ許可する
* `sort_order` は負の値を許可しない
* `time_type = exact` の場合は `exact_time NOT NULL`、`time_period NULL`
* `time_type = period` の場合は `exact_time NULL`、`time_period NOT NULL`
* `time_type = none` の場合は両方NULL
* duration_minutes > 0

この時間の整合性はDBの `CHECK` 制約で保証する。具体的な式は後述のDatabase Constraintsに定義する。

## itinerary_photos

旅程アイテムに関連して撮影・アップロードした写真を管理する。

写真は `itinerary_items` に紐付けることで、「旅行中のどの場所・移動に関連する写真か」を表現する。

画像ファイルそのものはDBには保存せず、Supabase Storageに保存する。

`itinerary_photos` テーブルにはStorage上の画像を特定するための情報と、写真に関するメタデータを保持する。

旅行一覧などで使用する旅行のサムネイル画像は `itinerary_photos` では管理せず、`trips.thumbnail_path` で別途管理する。

### Columns

| Column              | Type        | Nullable | Description                 |
| ------------------- | ----------- | -------: | --------------------------- |
| `id`                | uuid        |       NO | PK                          |
| `itinerary_item_id` | uuid        |       NO | 写真が紐づく旅程アイテム                |
| `storage_path`      | text        |       NO | Supabase Storage上の画像ファイルのパス |
| `is_public`         | boolean     |       NO | 写真単位の非参加者への公開可否。defaultは `false` |
| `uploaded_by`       | uuid        |       NO | 写真をアップロードしたユーザー             |
| `created_at`        | timestamptz |       NO | レコード作成日時                    |

### Relations

* `itinerary_item_id` → `itinerary_items.id`
* `uploaded_by` → `auth.users.id`
* 1つの `itinerary_item` は複数の `itinerary_photos` を持つことができる
* 1人のユーザーは複数の `itinerary_photos` をアップロードできる

```text id="ddz7va"
itinerary_items
      │
      │ 1
      │
      │ N
      ▼
itinerary_photos
      ▲
      │ N
      │
      │ 1
 auth.users
```

例：

```text id="0p8y7f"
清水寺
├── photo_1
├── photo_2
└── photo_3
```

### Storage

画像ファイルそのものはSupabase Storageに保存する。

DBには画像データを直接保存せず、`storage_path` にStorage上のファイルを特定するためのパスを保持する。

Storageのbucket構成やファイルパスの命名規則については、実装時に決定する。

### Upload

写真をアップロードするユーザーは、その写真を紐付ける `itinerary_item` が属する旅行のメンバーである必要がある。

写真をアップロードしたユーザーは `uploaded_by` に記録する。

`uploaded_by` は写真の所有権ではなく、「誰がアップロードしたか」を記録するための情報として扱う。

### Delete

写真を削除する場合は、DB上の `itinerary_photos` レコードだけでなく、対応するSupabase Storage上の画像ファイルも削除する必要がある。

写真を削除できるユーザーの範囲については別途決定する。

### Access Control

写真へのメンバー権限は、その写真が紐付く `itinerary_item` の旅行を基準として判断する。非参加者への閲覧許可には写真単位の `is_public` と、今後決定する公開条件を用いる。

対象旅行の `trip_members` に登録されているユーザーは、写真を閲覧・追加できる。

```text id="kl8gqa"
itinerary_photos
       ↓
itinerary_items
       ↓
     trips
       ↓
 trip_members
```

という関係を辿って、現在のユーザーが旅行メンバーであるかを判定する。

`is_public boolean NOT NULL DEFAULT false` を採用する。

* `false`：旅行メンバーのみ閲覧可能。
* `true`：非参加者にも閲覧を許可できる写真。無条件のインターネット公開を意味しない。

旅行メンバーは値にかかわらず閲覧できる。非参加者はログイン不要で許可された写真のみ閲覧でき、編集不可。メモ・投稿者の表示名・画像は非参加者へ返さない。旅行単位の公開制御、非公開旅行の写真単独公開、公開設定を変更できる人は未決定。

SupabaseではDBのRLSとStorageのアクセス制御を組み合わせて実装する。

### Constraints

* `itinerary_item_id` は必須
* `storage_path` は必須
* `is_public` はbooleanかつ必須、defaultは `false`
* `uploaded_by` は必須
* `itinerary_item_id` は存在する `itinerary_items.id` を参照する
* `uploaded_by` は存在する `auth.users.id` を参照する

### Design Decisions

#### 写真はitinerary_itemsに紐付ける

写真は旅行全体ではなく、「旅行中に何をしていたときの写真か」を表現できるよう `itinerary_items` に紐付ける。

これにより、旅行を振り返る際に旅程と写真を関連付けて表示できる。

#### itinerary_photosという名称を使用する

このテーブルで管理する写真は、すべて `itinerary_items` に紐付く写真である。

旅行サムネイルなど他の用途の画像と区別するため、汎用的な `photos` ではなく `itinerary_photos` という名称を使用する。

#### 画像ファイルをDBに保存しない

画像ファイルはSupabase Storageに保存し、DBにはStorage上のパスのみ保持する。

DBは写真と旅程アイテムとの関係やメタデータの管理を担当する。

#### 旅行サムネイルとは分離する

旅行一覧などで使用する旅行のサムネイル画像は、旅程アイテムに紐付く写真とは異なる用途のデータとして扱う。

旅行サムネイルは `trips.thumbnail_path` で管理し、`itinerary_photos` には含めない。

写真ごとのコメント・説明欄はMVPに追加しない。C01のメモは親アイテムの `description` を使う。

### 未決定事項

* 写真を削除できるユーザーの範囲
* `is_public` を設定・変更できるユーザーの範囲（アップロード時を含む）
* 旅行単位の公開制御との関係、旅行自体が非公開の場合の写真単独公開（閲覧はログイン不要で確定）
* 1つの `itinerary_item` に登録できる写真枚数の上限
* アップロード可能な画像形式
* アップロード可能なファイルサイズ
* 画像の圧縮・リサイズ方法
* 写真表示用のサムネイル画像を別途生成するか
* 写真の撮影日時を保持するか
* 写真の表示順を管理するか
* EXIF情報を利用するか

## Foreign Key Delete Rules

外部キーで関連付けられたレコードを削除する場合の挙動を定義する。

基本方針として、親データが存在しなければ意味を持たない子データについては `ON DELETE CASCADE` を使用する。

一方、ユーザー削除などによって履歴情報まで自動的に失われることが望ましくない場合は、個別に削除方法を検討する。

### profiles → auth.users

```text
profiles.id
    → auth.users.id
```

`auth.users` が削除された場合、対応する `profiles` も削除する。

```text
ON DELETE CASCADE
```

理由：

`profiles` は `auth.users` に対応する旅行帳上のプロフィール情報であり、認証ユーザーが存在しなくなった場合に単独で保持する必要がないため。

---

### trips.created_by → auth.users

```text
trips.created_by
    → auth.users.id
```

ユーザー削除時の扱いは別途決定する。

旅行作成者は旅行の削除権限を持つため、`created_by` が存在しなくなる場合の扱いを明確にする必要がある。

現時点では `ON DELETE CASCADE` は使用しない。

ユーザー削除時に、そのユーザーが作成した旅行まで自動的に削除されることは避ける。

具体的な削除ルールはアカウント削除仕様と合わせて決定する。

---

### trip_members.trip_id → trips.id

```text
trip_members.trip_id
    → trips.id
```

旅行が削除された場合、その旅行に属する `trip_members` も削除する。

```text
ON DELETE CASCADE
```

理由：

削除済みの旅行に対する参加情報は意味を持たないため。

---

### trip_members.user_id → auth.users

```text
trip_members.user_id
    → auth.users.id
```

ユーザーが削除された場合、そのユーザーの `trip_members` レコードも削除する。

```text
ON DELETE CASCADE
```

理由：

存在しないユーザーの旅行参加情報を残す必要がないため。

---

### itinerary_items.trip_id → trips.id

```text
itinerary_items.trip_id
    → trips.id
```

旅行が削除された場合、その旅行に属する `itinerary_items` も削除する。

```text
ON DELETE CASCADE
```

理由：

旅程アイテムは必ず1つの旅行に属し、旅行が存在しなければ単独では意味を持たないため。

---

### itinerary_photos.itinerary_item_id → itinerary_items.id

```text
itinerary_photos.itinerary_item_id
    → itinerary_items.id
```

旅程アイテムが削除された場合、そのアイテムに紐付く `itinerary_photos` レコードも削除する。

```text
ON DELETE CASCADE
```

理由：

`itinerary_photos` は必ず特定の旅程アイテムに紐付くため、親となる `itinerary_item` が存在しなくなった場合はDB上の写真情報も不要となる。

ただし、Supabase Storage上の画像ファイルはDBの `ON DELETE CASCADE` では削除されない。

そのため、旅程アイテムまたは旅行を削除する際は、対応するStorage上の画像ファイルも別途削除する必要がある。

---

### itinerary_photos.uploaded_by → auth.users

```text
itinerary_photos.uploaded_by
    → auth.users.id
```

ユーザー削除時の扱いは別途決定する。

`uploaded_by` は写真の所有権ではなく、「誰がアップロードしたか」という履歴情報として使用する。

そのため、ユーザーが削除されたことを理由に写真そのものまで削除することは避ける。

現時点では `ON DELETE CASCADE` は使用しない。

以下の方式をアカウント削除仕様と合わせて検討する。

- `uploaded_by` をNullableにして `ON DELETE SET NULL` とする
- ユーザー削除前に匿名化または別の値へ変更する
- アカウントを物理削除せず、論理削除として扱う

---

## Cascade Flow

旅行を削除した場合、以下の関連データを連鎖的に削除する。

```text
trips
├── trip_members
└── itinerary_items
      └── itinerary_photos
```

DB上では以下の流れになる。

```text
DELETE trips
    ↓ CASCADE
trip_members を削除

DELETE trips
    ↓ CASCADE
itinerary_items を削除
    ↓ CASCADE
itinerary_photos を削除
```

ただし、`itinerary_photos` に対応するSupabase Storage上の画像ファイルは自動削除されない。

旅行削除処理では、DBレコードの削除とは別にStorage上のファイル削除処理を行う。

---

## Summary

| Foreign Key | Delete Rule | 理由 |
|---|---|---|
| `profiles.id` → `auth.users.id` | `CASCADE` | ユーザーが存在しなければプロフィールも不要 |
| `trips.created_by` → `auth.users.id` | 未決定 | 作成者削除で旅行まで削除するべきではない |
| `trip_members.trip_id` → `trips.id` | `CASCADE` | 旅行削除後の参加情報は不要 |
| `trip_members.user_id` → `auth.users.id` | `CASCADE` | ユーザー削除後の参加情報は不要 |
| `itinerary_items.trip_id` → `trips.id` | `CASCADE` | 旅行削除後の旅程は不要 |
| `itinerary_photos.itinerary_item_id` → `itinerary_items.id` | `CASCADE` | 旅程削除後の写真情報は不要 |
| `itinerary_photos.uploaded_by` → `auth.users.id` | 未決定 | 写真そのものは残したい可能性がある |

## Design Decisions

### 旅行削除時は関連データも削除する

旅行を削除した場合、その旅行に属するメンバー情報・旅程・写真情報をDB上に残さない。

そのため、旅行配下のデータについては基本的に `ON DELETE CASCADE` を使用する。

### Storage上の画像削除はDBとは別に行う

PostgreSQLの外部キー制約はSupabase Storage上のファイルには影響しない。

そのため、`trips`、`itinerary_items`、`itinerary_photos` の削除処理では、必要に応じてStorage上の画像ファイルも削除する。

### ユーザー削除は別途設計する

ユーザー削除は旅行データ・写真履歴など複数のデータに影響するため、単純な `ON DELETE CASCADE` だけでは扱わない。

アカウント削除仕様を決める際に以下を合わせて検討する。

- 作成した旅行をどう扱うか
- 参加している旅行から自動退出させるか
- アップロード済み写真を残すか
- `created_by` や `uploaded_by` の履歴をどう扱うか
- ユーザーを物理削除するか論理削除するか

## Database Constraints

各テーブルで保証するデータ整合性について定義する。

基本方針として、アプリケーション側のバリデーションだけに依存せず、DBで保証できるルールについては `NOT NULL`、`UNIQUE`、`CHECK`、外部キー制約などを使用して保証する。

---

## profiles

### NOT NULL

以下のカラムは必須とする。

```text
id
display_name
created_at
updated_at
```

### Primary Key

```text
PRIMARY KEY (id)
```

`id` は `auth.users.id` と同じUUIDを使用する。

### Foreign Key

```text
id → auth.users.id
```

削除時の挙動：

```text
ON DELETE CASCADE
```

### display_name

`display_name` は必須とする。

複数ユーザーが同じ表示名を使用することを許可するため、UNIQUE制約は設定しない。

空文字を許可するか、文字数制限を設けるかについては別途決定する。

---

## trips

### NOT NULL

以下のカラムは必須とする。

```text
id
name
start_date
end_date
created_by
created_at
updated_at
```

`thumbnail_path` は任意とする。

### Primary Key

```text
PRIMARY KEY (id)
```

### Foreign Key

```text
created_by → auth.users.id
```

ユーザー削除時の挙動はアカウント削除仕様と合わせて別途決定する。

### Date Range

旅行終了日は旅行開始日より前の日付を許可しない。

```sql
CHECK (end_date >= start_date)
```

同日開始・同日終了の旅行は許可する。

例：

```text
start_date = 2026-10-10
end_date   = 2026-10-10
```

は有効とする。

### name

`name` は必須とする。

空文字を許可するか、文字数制限を設けるかについては別途決定する。

---

## trip_members

### NOT NULL

以下のカラムは必須とする。

```text
id
trip_id
user_id
joined_at
```

### Primary Key

```text
PRIMARY KEY (id)
```

### Foreign Keys

```text
trip_id → trips.id
user_id → auth.users.id
```

削除時の挙動：

```text
trip_id:
ON DELETE CASCADE

user_id:
ON DELETE CASCADE
```

### Unique Membership

同じユーザーを同じ旅行に複数回登録することを禁止する。

```sql
UNIQUE (trip_id, user_id)
```

これにより、1ユーザーにつき1旅行1メンバー情報のみ保持する。

---

## itinerary_items

### NOT NULL

以下のカラムは必須とする。

```text
id
trip_id
date
category
title
sort_order
time_type
created_at
updated_at
```

以下のカラムは任意とする。

```text
description
exact_time
time_period
duration_minutes
```

### Primary Key

```text
PRIMARY KEY (id)
```

### Foreign Key

```text
trip_id → trips.id
```

削除時の挙動：

```text
ON DELETE CASCADE
```

---

### category

`category` は以下の値のみ許可する。

```text
place
transportation
```

DBでは以下のようなCHECK制約を設定する。

```sql
CHECK (
  category IN ('place', 'transportation')
)
```

categoryの追加が必要になった場合は、この制約も合わせて変更する。

---

### time_type

`time_type` は以下の値のみ許可する。

```text
none
exact
period
```

```sql
CHECK (
  time_type IN ('none', 'exact', 'period')
)
```

---

### Time Consistency

`time_type` と `exact_time` / `time_period` の状態が矛盾しないよう制約を設定する。

#### exact

```text
time_type = exact
```

の場合、

```text
exact_time   = 必須
time_period  = NULL
```

とする。

#### period

```text
time_type = period
```

の場合、

```text
exact_time   = NULL
time_period  = 必須
```

とする。

#### none

```text
time_type = none
```

の場合、

```text
exact_time   = NULL
time_period  = NULL
```

とする。

確定したCHECK制約：

```sql
CHECK (
  (
    time_type = 'exact'
    AND exact_time IS NOT NULL
    AND time_period IS NULL
  )
  OR
  (
    time_type = 'period'
    AND exact_time IS NULL
    AND time_period IS NOT NULL
  )
  OR
  (
    time_type = 'none'
    AND exact_time IS NULL
    AND time_period IS NULL
  )
)
```

---

### duration_minutes

`duration_minutes` は所要時間を分単位で保持する。

設定する場合は0より大きい整数とする。

```sql
CHECK (
  duration_minutes IS NULL
  OR duration_minutes > 0
)
```

`NULL` は所要時間未設定を意味する。

```text
NULL → 未設定
30   → 30分
90   → 1時間30分
```

---

### sort_order

`sort_order` は0以上の整数とする。

```sql
CHECK (sort_order >= 0)
```

`sort_order` は同一の `trip_id` と `date` の組み合わせの中での表示順を表す。

例：

```text
trip_id = A
date = 2026-10-10

sort_order = 0
sort_order = 1
sort_order = 2
```

別の日付では再び同じ `sort_order` を使用できる。

```text
trip_id = A
date = 2026-10-11

sort_order = 0
sort_order = 1
```

以下のUNIQUE制約を設定するかについては、並び替え処理の実装方法と合わせて決定する。

```sql
UNIQUE (trip_id, date, sort_order)
```

ドラッグ&ドロップによる並び替え時に一時的な重複が発生する可能性があるため、MVPでは必須としない。

---

### itinerary date

`itinerary_items.date` は、そのアイテムが属する旅行期間内の日付であることを基本ルールとする。

```text
trips.start_date
    <= itinerary_items.date
    <= trips.end_date
```

ただし、この制約は別テーブルである `trips` の値を参照する必要があるため、通常の単純な `CHECK` 制約では直接保証しない。

MVPではアプリケーション側でバリデーションする。

旅行期間短縮時に既存の範囲外アイテムをどう扱うかは未決定とする。自動削除・移動などの挙動を独断で追加しない。

必要になった場合は、DBトリガーなどによる保証を検討する。

---

### title

`title` は必須とする。

空文字を許可するか、文字数制限を設けるかについては別途決定する。

---

## itinerary_photos

### NOT NULL

以下のカラムは必須とする。

```text
id
itinerary_item_id
storage_path
is_public
uploaded_by
created_at
```

### Primary Key

```text
PRIMARY KEY (id)
```

### Foreign Keys

```text
itinerary_item_id → itinerary_items.id
uploaded_by       → auth.users.id
```

`itinerary_item_id` の削除時：

```text
ON DELETE CASCADE
```

`uploaded_by` のユーザー削除時の挙動については、アカウント削除仕様と合わせて別途決定する。

### storage_path

`storage_path` は必須とする。

同じStorageファイルを複数レコードから参照することを許可するかについては別途決定する。

必要であれば将来的に以下の制約を検討する。

```sql
UNIQUE (storage_path)
```

---

### is_public

```sql
is_public boolean NOT NULL DEFAULT false
```

写真単位で非参加者への閲覧許可の対象になれるかを記録する。`false` はメンバー限定、`true` は未決定の公開条件を満たした非参加者にも閲覧を許可できることを意味する。boolean型とNOT NULLで値を制約するため、値域の追加CHECKは不要。

defaultは省略時の値を決めるものであり、呼び出し元による `true` の指定を禁止しない。設定権限の保証はRLS・列権限等で行う。

## Cross-Table Rules

### 旅行作成者は旅行メンバーである

`trips.created_by` に設定されたユーザーは、その旅行の `trip_members` にも存在することをアプリケーション上のルールとする。

```text
trips.created_by
    ↓

trip_members
trip_id = trips.id
user_id = trips.created_by
```

旅行作成時に、

1. `trips` を作成する
2. 作成ユーザーを `trip_members` に追加する

という処理を行う。

このルールをDBトリガーで保証するかについては、実装時に検討する。

### 写真アップロードユーザーは旅行メンバーである

`itinerary_photos.uploaded_by` に設定するユーザーは、その写真が紐付く `itinerary_item` の旅行メンバーである必要がある。

```text
itinerary_photos
    ↓
itinerary_items.trip_id
    ↓
trip_members
```

このルールはRLSおよびアプリケーション側の処理によって保証する。

---

## Constraint Summary

| Table | Constraint | Rule |
|---|---|---|
| `profiles` | PK | `id` |
| `profiles` | FK | `id → auth.users.id` |
| `trips` | PK | `id` |
| `trips` | CHECK | `end_date >= start_date` |
| `trips` | FK | `created_by → auth.users.id` |
| `trip_members` | PK | `id` |
| `trip_members` | UNIQUE | `(trip_id, user_id)` |
| `trip_members` | FK | `trip_id → trips.id` |
| `trip_members` | FK | `user_id → auth.users.id` |
| `itinerary_items` | PK | `id` |
| `itinerary_items` | FK | `trip_id → trips.id` |
| `itinerary_items` | CHECK | `category IN ('place', 'transportation')` |
| `itinerary_items` | CHECK | `time_type IN ('none', 'exact', 'period')` |
| `itinerary_items` | CHECK | `time_type` と時間カラムの整合性 |
| `itinerary_items` | CHECK | `sort_order >= 0` |
| `itinerary_items` | CHECK | `duration_minutes IS NULL OR duration_minutes > 0` |
| `itinerary_photos` | PK | `id` |
| `itinerary_photos` | 型 / NOT NULL / DEFAULT | `is_public boolean NOT NULL DEFAULT false` |
| `itinerary_photos` | FK | `itinerary_item_id → itinerary_items.id` |
| `itinerary_photos` | FK | `uploaded_by → auth.users.id` |

## Design Decisions

### DBで保証できる整合性はDBで保証する

`category` や `time_type` の取り得る値、日付の前後関係、所要時間など、単一レコード内で完結するルールについてはDBの制約を使用する。

アプリケーション側でも入力チェックは行うが、DBを最終的なデータ整合性の保証地点とする。

### 複数テーブルを跨ぐルールは無理にCHECK制約にしない

以下のような複数テーブルにまたがるルールは、単純なCHECK制約では扱わない。

- `itinerary_items.date` が旅行期間内である
- 旅行作成者が `trip_members` に存在する
- 写真アップロード者が旅行メンバーである

これらはアプリケーション処理、RLS、必要に応じてDBトリガーなどによって保証する。

初期バージョンでは、必要以上に複雑なDBトリガーを導入しない。
