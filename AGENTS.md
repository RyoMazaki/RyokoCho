<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# AGENTS.md

このリポジトリは、旅行計画・共有・振り返りを行うアプリケーション「旅行帳」の開発リポジトリである。

AIエージェントは、既存仕様と既存コードを確認したうえで、設計・実装・検証・必要なドキュメント更新まで行うこと。

---

## 1. 基本ルール

- 実装前に、タスクに関連する `docs/` と既存コードを確認する
- 未決定のプロダクト仕様を勝手に確定しない
- 現在のタスクに必要な最小限の変更を行う
- 要件にない機能を追加しない
- 将来使うかもしれないという理由だけで過剰設計しない
- 既存の設計・命名・コードスタイルを尊重する
- 仕様またはデータ構造を変更した場合は、関連ドキュメントも更新する
- 実装後は必要な検証を行い、失敗があれば可能な範囲で修正する

プロダクト判断が必要な未決定事項がある場合は、勝手に決めず明示すること。

一方、命名や単純な実装方法など、プロダクト仕様に影響しない軽微な技術判断については、既存設計に沿った合理的な方法を選択してよい。

---

## 2. 参照ドキュメント

必要に応じて以下を参照する。

```text
docs/product.md
docs/requirements.md
docs/screens.md
docs/data_model.md
docs/db-implementation.md
docs/decisions.md
```

役割：

```text
product.md
→ プロダクトの目的・思想

requirements.md
→ ユーザー向け機能・挙動・MVP範囲

screens.md
→ 画面構成・画面遷移

data_model.md
→ 論理データモデル・データの意味・関係

db-implementation.md
→ Supabase / PostgreSQL上での具体的なDB実装

decisions.md
→ 重要な設計判断とその理由
```

ドキュメントとコードに矛盾を発見した場合は、黙って片方に合わせず、作業結果で明示すること。

---

## 3. 技術スタック

原則として以下を使用する。

- Next.js
- App Router
- TypeScript
- Tailwind CSS
- Supabase
  - PostgreSQL
  - Auth
  - Storage
  - Row Level Security

既存の技術スタックを、明確な必要性なく変更しないこと。

---

## 4. Next.js / TypeScript

### Server Components

Server Componentsを基本とする。

以下のような場合のみClient Componentを使用する。

- クライアント側の状態管理が必要
- browser APIを使用する
- Reactのclient-side hookを使用する
- ドラッグ&ドロップなどのインタラクションが必要

不要な `"use client"` を追加しないこと。

### TypeScript

- `any` は原則使用しない
- 既存の型がある場合は再利用する
- Supabase生成型を利用できる場合は利用する
- 不要な型キャストを避ける

---

## 5. Supabase / Database

### Data Model

DB変更前に `docs/data_model.md` を確認すること。

データの意味やテーブルの責務を、実装上の都合だけで変更しない。

### DB Implementation

PostgreSQL / Supabase固有の実装詳細は `docs/db-implementation.md` を基準とする。

対象：

- column type
- PK / FK
- CHECK
- UNIQUE
- ON DELETE
- index
- RLS
- Storage policy

DB実装を変更した場合は、必要に応じて `docs/db-implementation.md` も更新する。

### Migration

DB変更はmigrationで管理する。

以下をmigrationなしで変更しないこと。

- table
- column
- constraint
- index
- RLS policy
- database function / trigger

既存migrationは原則として書き換えず、新しいmigrationを追加する。

### RLS

アクセス制御が必要なテーブルではRLSを前提とする。

新しいテーブルや操作を追加する場合は、最低限以下を確認する。

```text
SELECT
INSERT
UPDATE
DELETE
```

RLSを考慮せずにDB実装を完了扱いにしない。

### Secrets

以下をClientへ公開しない。

- Supabase Service Role Key
- secret key
- サーバー専用credential

認可をClient側だけで保証しないこと。

---

## 6. 旅行帳固有の設計ルール

### 旅程の順序

旅程の正式な順序は `sort_order` を基準とする。

時刻は補助情報であり、以下を旅程の正式な並び順として使用しない。

```text
exact_time
time_period
計算された推定時刻
```

旅行帳は「時刻順のカレンダー」ではなく、「ユーザーが決めた旅程順」を基本とする。

### itinerary_items

場所と移動は `itinerary_items` で共通管理する。

初期category：

```text
place
transportation
```

明確な必要性がない限り、

```text
places
transportations
place_details
transportation_details
```

などの追加テーブルを先回りして作らない。

`place` には場所、その場所で行うこと、滞在中の行動を含める。独立した `action` categoryは追加しない。

`itinerary_items.date` は原則として旅行期間内とし、MVPではアプリケーション側で検証する。単純なDB CHECKにはしない。期間短縮時の範囲外アイテムの扱いは未決定とする。

時間の整合性はDB CHECKで保証する。`exact` は `exact_time` のみNOT NULL、`period` は `time_period` のみNOT NULL、`none` は両方NULLとする。

### trip_days

`trip_days` テーブルは使用しない。

旅程アイテムは、

```text
itinerary_items.trip_id
itinerary_items.date
```

によって旅行と日付を管理する。

明確な要件変更がない限り `trip_days` を追加しない。

### trip_members

旅行への参加状態は `trip_members` で管理する。

メンバー間で通常の閲覧・編集権限を分けるroleは持たない。

旅行メンバーは基本的に旅行データを閲覧・編集できる。

非参加者の旅行閲覧は将来必須とし、メンバーの編集権限と分離して閲覧を許可できる設計とする。非参加者には編集権限を与えない。ログイン要否、誰でも閲覧可能か共有リンク限定か、旅行単位の公開範囲の値、MVPでの提供範囲は独断で決めない。

旅行そのものを削除できるのは、

```text
trips.created_by
```

に該当する旅行作成者のみとする。

旅行作成者以外のメンバーは、自分自身が旅行から退出できる。

### Photos

旅程に紐づく写真は、

```text
itinerary_photos
```

で管理する。

画像本体はSupabase Storageに保存し、DBにはStorage上のパスを保存する。

写真単位の公開可否は `itinerary_photos.is_public boolean NOT NULL DEFAULT false` で管理する。`false` はメンバー限定、`true` は非参加者にも閲覧を許可できることを意味する。`true` だけで無条件公開にしない。非参加者の認証・共有条件、非公開旅行の写真単独公開、公開設定を変更できる人は未決定として扱う。

旅行一覧などで使用する旅行サムネイルは、

```text
trips.thumbnail_path
```

で別管理する。

---

## 7. Supabase Storage

画像ファイル本体をPostgreSQLへ保存しない。

Storage上のファイルとDBレコードは別管理であることに注意する。

DBレコードを削除してもStorageファイルは自動削除されないため、写真や旅行を削除する処理では必要に応じて両方を処理する。

Storageへのアクセスにも適切なpolicyを設定する。

---

## 8. ライブラリ追加

新しいnpmパッケージを追加する前に、以下を確認する。

- 標準機能で実現できないか
- 既存dependencyで実現できないか
- 本当に今回のタスクで必要か

不要なdependencyを追加しない。

大きなライブラリやアーキテクチャに影響するライブラリを追加する場合は、理由を作業結果に記載する。

---

## 9. 実装時の進め方

基本的に以下の順序で進める。

```text
1. 関連docsを確認
2. 関連する既存コードを確認
3. 必要な変更範囲を判断
4. 実装
5. lint / build / test
6. 必要ならdocs更新
7. 変更内容を自己レビュー
```

小さな変更について、毎回長い設計文書を作る必要はない。

DB構造、権限、主要な画面フローなどに影響する変更では、必要に応じて設計を先に整理する。

---

## 10. 検証

実装後は変更内容に応じて必要な検証を行う。

原則として実行する。

```bash
npm run lint
npm run build
```

テストが存在する場合は関連テストも実行する。

DB変更の場合は以下も確認する。

- migrationの整合性
- FK / CHECK / UNIQUE
- RLS
- Storage policy
- 既存データへの影響

検証できなかったものがある場合は、完了報告で明示する。

---

## 11. ドキュメント更新

以下に該当する変更では、関連ドキュメントも更新する。

- プロダクト仕様の変更
- DB構造の変更
- 権限ルールの変更
- 重要な設計判断の変更
- 画面フローの変更

実装とドキュメントの内容を意図的に乖離させない。

ただし、コード内部だけの小さなリファクタリングで不要なdocs更新は行わない。

---

## 12. 完了報告

タスク完了時は簡潔に以下を報告する。

- 実施した変更
- 主な変更ファイル
- 実行した検証
- 未解決事項や懸念点

大量のコードをそのまま貼り付ける必要はない。

---

## 13. やってはいけないこと

以下を避ける。

- 未決定仕様を勝手に確定する
- 要件にない機能を追加する
- 無関係なコードを大量に変更する
- 不要な抽象化を追加する
- 必要性なく新しいテーブルを増やす
- 必要性なく新しいdependencyを追加する
- RLSを無視する
- secretをClientへ公開する
- DB変更をmigrationなしで済ませる
- `sort_order` ではなく時刻で旅程を自動的に並び替える
- 明確な要件変更なしに `trip_days` を追加する
- lint / buildの失敗を無視して完了扱いにする