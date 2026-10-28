# プリセットのiCloud同期

## 実装と保存の仕様

CloudKitのPrivate DatabaseとCKSyncEngineを使う。コンテナは全OS共通の `iCloud.app.merodoa.PiTempo`、カスタムゾーンは `TempoPresets`。本体の設定JSONは既存の `PresetConfiguration` のまま。メイン画面の現在設定（AppSettings）、再生状態、画面スリープ設定、マイクの解析結果は同期しない。保存したプリセットに含まれるBPMや音色は同期する。

- `PresetStore`：既存のUserDefaults `metronomePresets.v1` を読む。移行後も旧キーを削除・上書きしない。
- `PresetRepository`：UI操作とクラウド受信の唯一の書き込み経路。操作単位で最新状態へ変更を加える。通知がUIに届く前の受信データも保持する。
- `PresetSyncMetadataStore`：Application Support内の `app.merodoa.PiTempo/PresetSync/state.json` に、全プリセット、削除記録、論理時計、送信待ち、CKRecordのシステム情報、CKSyncEngine状態をまとめて原子的に置換する。直前のファイルも `state.json.previous` に保存する。macOSの署名済みアプリではApp Sandbox内に保存される。
- `CloudPresetSyncService`：専用actorで通信・送受信イベントを処理する。音声エンジンは呼ばない。受信時は一覧だけをMainActorへ通知する。適用済みの内容が他端末で変わった場合、現在の設定は維持して「変更あり」と表示する。

保存失敗時は公開状態を変更しない。本体と送信待ちは同時に保存されるため、クラッシュ後にも再送できる。読めない状態ファイルや将来のスキーマは上書きしない。旧JSONから復元できる場合は一覧を表示してエラーを通知する。この場合、書き込みはエラーとして扱う。

## 初回取得・競合・削除・順序

最初に旧JSONをローカル状態ファイルへコピーする。その後、クラウドの初回取得が正常に終わるまで、レコード送信を許可しない。受信レコードとローカルレコードをUUID単位でマージして保存した後、ローカルにだけ存在する変更を送信する。空の配列をクラウドの削除命令には変換しない。

初回取得完了フラグは受信の完了だけを意味する。全送信の確認まで済んだ時点で最終同期日時を保存する。途中終了時は保存済みのカーソルと未送信変更から再開する。受信データの保存に失敗した場合はエンジンを停止し、未保存の変更より先のカーソルを永続化しない。

競合の優先順位：

1. 同じUUIDの削除記録を通常編集より常に優先する。削除記録は自動消去しない。作り直す場合は新しいUUIDを発行する。
2. 通常編集同士、削除同士、表示順同士は、観測済みの最大論理リビジョンに1を加えた値で比較する。同じ値なら永続化された書き込み元IDの辞書順で決める。端末時計は競合の判定に使わない。
3. `serverRecordChanged` ではサーバのレコードと比較し、サーバのシステム情報（changeTagなど）を保存して、ローカルが優先される場合だけ再送する。

表示順は独立レコード。採用された順序に含まれない有効なUUIDはUUID順で末尾へ補完するため、同時追加したプリセットを失わない。同時並べ替えは上記の規則で一方の順序を採用する。

サーバ側でプリセットが物理削除された場合もローカルに削除記録を作る。ゾーン全体の削除は、全プリセットを削除する命令とは扱わず、ローカルを保持してサーバ状態を再取得する。通常のアプリ操作ではCloudKitの物理削除APIを使わない。

## アカウントとオフライン

コンテナ・Development/Production環境・CloudKitのユーザーレコードIDごとに状態を分離する。最初のログイン時だけ、未所属のローカルプリセットをそのアカウントへ引き継ぐ。以後、別アカウントへは前のプリセットや送信待ちをコピーしない。

- 通信断や一時的な利用不可：現在のローカル一覧と編集内容を保持する。CKSyncEngineの再試行、ネットワーク復帰の監視、およびアプリ復帰時・「今すぐ同期」で再開する。アカウント確認前の一時的エラーは待ち時間を増やして再試行し、サーバのRetry-Afterも尊重する。
- サインアウトが確認された場合：旧アカウント領域をファイル内のバックアップとして保持し、独立したローカル領域を表示する。この領域の作業は、その後の別アカウントへ自動送信しない。
- 同じアカウントへ再ログイン：そのアカウントの一覧と送信待ちを復元する。
- アプリ終了中のアカウント切り替え：起動時にユーザーIDを確認してから該当領域とCKSyncEngine状態を選ぶ。旧エンジンの遅延応答は拒否する。

同期時刻は送信待ちが空で、取得と送信に失敗がない場合だけ更新する。過去の「最終同期」は現在の接続成功を意味しない。SimulatorとCloudKit権限のないmacOSビルドでは通信を開始せず「iCloud利用不可」と表示する。ローカル管理は利用できる。

## CloudKit Consoleのレコード定義

以下は実装が使用するスキーマ。**コンテナの作成・紐付け、Consoleでの作成とProductionデプロイはこのコード変更だけでは完了しない。**

`TempoPreset`（レコード名はプリセットUUID文字列）

| フィールド | CloudKit型 | 内容 |
| --- | --- | --- |
| schemaVersion | Int64 | 1 |
| uuid | String | レコード名と同じUUID |
| presetJSON | Bytes | MetronomePresetのCodable JSON。削除記録では省略可 |
| revision | Int64 | 論理リビジョン |
| writerID | String | 変更を作成した端末の永続ID |
| isDeleted | Int64 | 0または1 |
| deletedAt | Date/Time | 削除時刻。表示・診断用 |

`TempoPresetOrder`（レコード名は `preset-order`）

| フィールド | CloudKit型 | 内容 |
| --- | --- | --- |
| schemaVersion | Int64 | 1 |
| orderedIDs | List of String | UUIDの順序 |
| revision | Int64 | 論理リビジョン |
| writerID | String | 書き込み元ID |

Private Databaseのゾーン変更取得を使うため、独自のQuery用インデックスは不要。CKSyncEngineがPrivate Databaseの変更購読を管理する。パブリックDBや別ユーザーへの共有権限は使わない。

## Apple Developer / Xcodeの設定手順

1. 対象チームの権限で、Apple DeveloperのIdentifiersにあるApp ID `app.merodoa.PiTempo` へiCloud（CloudKit）とPush Notificationsを有効化する。
2. 新規コンテナ `iCloud.app.merodoa.PiTempo` を作成し、このApp IDへ紐付ける。XcodeのTempoLabターゲット → Signing & Capabilitiesでも同じチーム・コンテナを選択する。既存コンテナと名前が衝突した場合は識別子を確認し、コードの `PresetCloudRecord.containerIdentifier` と両方のentitlementsを同時に変更する。
3. iPhone/iPadとmacOSの開発用・配布用プロビジョニングプロファイルを更新する。自動署名を使う場合も、新しい権限が反映されたことを確認する。リポジトリからPortalを自動変更する処理は行わない。
4. iOS/iPadOSは `TempoLab-iOS.entitlements`、macOSは `TempoLab.entitlements` を使う。iOSのBackground Modesは既存のaudioにremote-notificationを追加している。macOSには既存のマイク権限とApp Sandboxに加えて外向き通信の権限を設定している。
5. Debugは `CLOUDKIT_ENVIRONMENT=Development` / `APS_ENVIRONMENT=development`、Releaseは `Production` / `production`。別構成で開発署名を使う場合は、ビルド設定の値を署名プロファイルに合わせる。`PresetCloudKitEnvironment` はiOSの `Info.plist` とmacOSの `Info-macOS.plist` で同じビルド設定を展開する。生成済みアプリの値も自動テストで確認する。署名なしReleaseビルドでもProduction値が展開されることを確認した。異なる環境の同期メタデータを共有しない。
6. 署名済み成果物を `codesign -d --entitlements :- <PiTempo.appのパス>` で確認し、コンテナID、iCloud環境、CloudKit、プラットフォームに応じたAPNs環境が署名・プロファイルと一致することを確認する。配布時はXcodeのExport後の成果物も確認する。
7. 同じApple Accountの実機とMacでDevelopment環境の往復同期を検証する。CloudKit Console → CloudKit Database → 対象コンテナのDevelopmentで、上表の型とフィールドが作成されることを確認する。実機の初回保存で開発スキーマを作成するか、Consoleで同じ型を定義する。
8. 検証後、Consoleの **Deploy Schema Changes** で変更を確認してProductionへDeployする。スキーマのデプロイはレコード本体をコピーしない。Production用に署名したアプリでも別途検証する。Productionへ出した型・フィールドは削除できないため、破壊的な型変更を行わない。

参照： [Apple公式CKSyncEngineサンプル](https://github.com/apple/sample-cloudkit-sync-engine)、[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)、[Productionスキーマへのデプロイ](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)、[iOS APNs entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)、[macOS APNs entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment)。

## 実機の受け入れ確認（未実施）

同じApple AccountのiPhoneとMac、可能ならiPadで、次を往復検証する。Simulatorの成功だけでPush通知を含む同期を合格にしない。

- 既存プリセットがある各端末の初回同期で双方を保持する。
- 保存、名前変更、設定上書き、削除、並べ替えを双方へ反映する。
- 機内モード中の編集、終了・再起動、復帰後の再送を確認する。
- 同時名前変更、削除対編集、同時並べ替えで同じ結果に収束する。
- サインアウト・別アカウント・元アカウントへの復帰で旧データを別アカウントへ送信しない。
- バックグラウンドと終了中の変更を、Push通知と次回起動・復帰時の取得で反映する。通知はOSの判断で遅延するため、即時性を保証しない。
- 再生中の受信・ローカル保存で、設定の自動適用や意図しない停止がなく、聴感上のクリック欠落や二重発音がない。

このリポジトリの自動テストは、クラウド非接続のFakeによるデータ統合と送信待ちの検証、および音声・ViewModelの回帰検証である。署名、CloudKitサーバ、APNs、実機間の同期成功を証明するものではない。

## 今回の検証結果（2026-10-28）

| 段階・環境 | 結果 |
| --- | --- |
| C1 / macOS | ビルド成功、全145テスト成功 |
| C2 / macOS | 全153テスト成功。最終調整後の同期関連19テストも成功 |
| C3 最終コード / macOS | DebugとReleaseのビルド成功、全160テスト成功（生成Info.plistの環境検証と既存の音声出力検証7件を含む） |
| C3 / iPhone Simulator | 最終コードのアプリ・テストバンドルのビルド成功。起動60秒タイムアウト、および別検証先でのテスト開始待ちのため実行は未完了 |
| C3 / iPad Simulator | 最終コードのbuild-for-testing成功。iPadOS 27.0と18.4の両方でテスト開始待ちとなり中断。テスト成功とは扱わない |
| macOS画面操作 | 同期状態のレイアウト、既存プリセットの表示、再生中の画面開閉・同期操作後も再生状態を維持することを確認。通信は権限なしビルドのため利用不可 |
| 実機のCloudKit・APNs・配布署名 | 未実施。コンテナ作成・紐付けとプロファイル更新、Productionへのデプロイが必要 |

macOS 27.0.1 / Xcode 27.1、Simulatorの検証先はiOS/iPadOS 27.0、および追加でiPadOS 18.4。署名なしのローカル検証には `CODE_SIGNING_ALLOWED=NO` を使用した。Simulatorでの未完了はテスト開始前の問題であり、アプリのテストケースの合格を意味しない。ほかの作業が使用するシミュレータやCoreSimulatorサービスは再起動していない。

再検証の例（実機での同期確認は上の受け入れ手順を別途実施する）：

```sh
xcodebuild test -project TempoLab.xcodeproj -scheme TempoLab \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing -project TempoLab.xcodeproj -scheme TempoLab \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```
