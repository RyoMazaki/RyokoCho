<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# AGENTS.md

旅行計画・共有・振り返りアプリ「旅行帳」の開発ルール。
本書はエージェントの作業方法と参照先を定める。プロダクト仕様・データ定義・機能別の実装契約は [docs/](./docs/) で管理し、本書へ重複して転記しない。

## 1. 常に守るルール

- 関連する仕様と既存コードを確認し、必要な最小限の変更を行う。無関係な変更やユーザーの作業の上書きを避ける。
- 未決定のプロダクト仕様を独断で確定しない。判断が必要な点を明示し、影響しない作業は進める。命名など軽微な技術判断は既存設計に合わせてよい。
- 要件にない機能・テーブル・抽象化・依存を先回りして追加しない。標準機能と既存dependencyを優先する。
- 既存の設計・命名・コードスタイルを尊重する。仕様と実装に矛盾があれば、黙って片方に合わせず明示する。
- 文書同士の矛盾を発見した場合は現行仕様を確認し、特定できなければ矛盾点をユーザーに確認するまで影響する実装を保留する。
- 実装・必要な検証・関連文書の更新・差分の自己レビューまで行い、未検証や失敗を完了扱いにしない。

## 2. 作業別の参照先

最初に対象作業の関連節と既存実装を読む。毎回すべての文書を全文読む必要はないが、関連節から参照される制約と変更の影響先まで確認する。検索結果の抜粋だけで判断せず、該当節の前提・例外も読む。

| 作業・確認事項 | 参照先と役割 |
| --- | --- |
| 目的・対象範囲・機能の追加や変更 | [product.md](./docs/product.md)：目的、[requirements.md](./docs/requirements.md)：挙動・MVP範囲 |
| 画面・遷移・保存操作 | [screens.md](./docs/screens.md)：画面構成・操作フロー |
| データの追加・変更・取得 | [data_model.md](./docs/data_model.md)：データの意味・関係、[db-implementation.md](./docs/db-implementation.md)：具体的な制約・認可 |
| DB・RLS・RPC・Storage | [db-implementation.md](./docs/db-implementation.md)と[supabase/](./supabase/)のmigration・テスト。構築と検証手順は[README](./supabase/README.md) |
| 接続・認証・プロフィール | [supabase-client.md](./docs/supabase-client.md)：接続・型生成、[auth-ui.md](./docs/auth-ui.md)：認証フロー・設定・確認手順 |
| 旅行・参加者の取得 | [trip-reads.md](./docs/trip-reads.md)：取得契約と制限。データ・認可の参照先も確認 |
| 旅程の取得 | [itinerary-reads.md](./docs/itinerary-reads.md)：取得契約と制限。データ・認可の参照先も確認 |
| 既存の設計を変更・再検討 | [decisions.md](./docs/decisions.md)：採用した判断と理由、および対象の仕様書 |

旅程の順序・日付・時間、参加者権限、公開範囲、写真、削除・期間短縮を扱う際は、要件・データ・DB設計の該当節を必ず確認する。本書から個別仕様を省略しても、既存の制約を解除するものではない。

## 3. 実装の基本

- 技術スタックはNext.js App Router・TypeScript・Tailwind CSS・Supabaseを基本とし、必要性なく変更しない。Next.jsの変更時は冒頭の指示に従い、同梱ガイドの関連箇所を確認する。
- Server Componentsを基本とする。状態管理・browser API・client hookなど必要な箇所だけClient Componentにする。
- 既存型・Supabase生成型を再利用し、`any`や不要な型キャストを避ける。生成型は手修正せず、所定の手順で再生成する。
- テーブル・列・制約・index・RLS・DB関数・triggerの変更は新しいmigrationで管理する。既存migrationは原則として書き換えない。
- 認可をClientだけで保証しない。対象操作のRLS・GRANT・RPC認可を確認し、新規テーブルではSELECT / INSERT / UPDATE / DELETEそれぞれの許可・拒否を確認する。
- Service Role Key・secret key・サーバー専用credentialをClientへ公開しない。
- StorageはDBと別管理である。画像操作では両方のアクセス制御と、削除・部分失敗時の整合性を確認する。具体的な処理はDB設計に従う。

## 4. 検証

- コード変更では原則として`npm run lint`、`npm run build`と関連テストを実行する。
- DB変更ではmigration、FK / CHECK / UNIQUE、RLS・Storage policy、既存データへの影響も確認する。
- 文書のみの変更では、記述の整合性・リンク先・差分を確認する。lint / buildは実行設定などへの影響がある場合に行う。
- 失敗は可能な範囲で修正し、未実施・未解決の項目は理由とともに報告する。ローカルの代替検証と実環境の検証を区別する。

## 5. ドキュメントの更新と分量

### 更新する内容

- プロダクト仕様、DB構造、権限、重要な設計判断、画面フローを変更した場合は、該当する文書を更新する。利用方法・取得契約・設定手順が変わる場合も既存ガイドを更新する。
- 既存仕様どおりの実装や内部リファクタリングだけなら、変更を説明するためだけの文書追加は不要。ただし、既存文書の未実装表記などが事実と異なる場合は修正する。
- 本書には作業ルール、仕様書には挙動と制約、設計判断には理由、実装ガイドには利用契約と手順を書く。コードの逐語的な説明を重ねない。

### 必要十分に保つ基準

- Codexが普遍的に理解している内容について冗長に記述しない。
- 同じ仕様の詳細な記載先は一箇所に定め、他の文書からはリンクする。論理モデルに詳細SQLを重ねるなど、文書の役割を越えた重複を避ける。
- 冒頭に対象範囲と重要な制約を短く示し、見出しから必要な節へ到達できる構成にする。長い文書は目次や関連節へのリンクで案内する。
- 現行仕様・未決定事項・技術案・実装状況を区別する。採用・実装が決まったら旧記述を整理し、追記だけで相反する説明を残さない。
- 認可条件、データ整合性、失敗時の扱い、重要な例外、未決定事項は省略しない。説明や例は判断に必要なものに絞り、同じ内容の本文・表・コード例を繰り返さない。
- テストの実行方法と検証範囲は残す。その回の成功件数・一時的なツールエラー・作業経過は原則として完了報告やPRに記載する。継続作業に影響する未検証事項は文書にも残す。
- 既存文書への反映を優先する。独立して繰り返し参照する用途がある場合は新規文書を作成してよい。ファイル数や一律の行数上限ではなく、必要な情報への到達しやすさと重複の少なさで判断する。
- 更新後は「次の作業者が前提・制約・未決定事項を探せるか」「同じ説明や古い記述が残っていないか」を確認する。今回と無関係な文書全体の再編は行わない。

## 6. ユーザーへの説明

- 結論を先に、簡潔な日本語で伝える。ユーザーの判断に必要な理由・影響・制限を優先する。
- 進捗は重要な発見・方針変更・障害を短く伝える。通常の読み取りや実行手順を逐一説明しない。
- 完了報告は変更点、主なファイルへのリンク、検証結果、残件があればその内容を短くまとめる。差分や大量のコード、全実行ログを貼らない。
- 詳細は依頼された場合、または判断に必要な場合に補足する。簡潔さのために失敗・未検証・仕様の矛盾を隠さない。
