# Dynamic SOQL Utilities for Flow

## 概要
本リポジトリは Salesforce Flow から利用できる 2 つの Invocable Apex ツールを提供します。

1. **GetIdsWithDynamicSOQL**  
   Flow から SOQL の `WHERE` 句と `ORDER BY` 句を動的に組み立て、条件に合致するレコードの Id 一覧を取得します。

2. **SemicolonToSoqlInList**  
   セミコロン区切りの文字列から、SOQL の `IN (...)` 句に利用可能なリテラルリストを生成します。複数選択リストやマルチセレクト入力を `WHERE` 句に組み込む際に便利です。

---

## GetIdsWithDynamicSOQL

### 主な機能
- **動的 WHERE 条件**  
  任意の条件式文字列を Flow から渡し、`WHERE` 句として適用します。
- **動的 ORDER BY**  
  フィールド名と並び順を指定できます。存在しないフィールドは無視され、既定は `CreatedDate DESC, Id DESC` です。
- **LIMIT 指定**  
  件数制限を設定できます（既定 200、最大 2000）。
- **実行 SOQL の返却**  
  実際に実行された SOQL を返すため、トラブルシュートに役立ちます。

### 利用方法（Flow 内）
1. フローに「アクション」要素を追加。
2. `GetIdsWithDynamicSOQL` を選択。
3. パラメータを設定:
   - **objectApiName**: 例 `'Account'`
   - **whereText**: 例 `"Name LIKE '%Acme%' AND AnnualRevenue >= 100000"`
   - **orderBy**: 例 `"CreatedDate DESC"`
   - **limitSize**: 例 `500`
4. 出力変数 `ids`（コレクション）や `count` を後続の処理で使用可能。

---

## SemicolonToSoqlInList

### 主な機能
- **セミコロン区切り文字列 → `IN (...)` 句**  
  例: `"A;B;C"` → `('A','B','C')`
- **型ヒントによるリテラル化**  
  `Id`, `Text`, `Number`, `Boolean`, `Date`, `DateTime` など。
- **文字列の小文字化**  
  `lowerize = true` で `Text`/`Id` 値を小文字に変換。
- **括弧の有無指定**  
  `wrapParen = false` で括弧なしのカンマ区切り文字列を返す。
- **重複・空白除去**  
  値の前後の空白をトリムし、重複を自動的に排除。

### 利用方法（Flow 内）
1. 複数選択リストやマルチセレクト入力の値（例: `'A;B; C'`）を変数として用意。
2. フローに「アクション」要素を追加。
3. `SemicolonToSoqlInList` を選択。
4. パラメータを設定:
   - **semicolonText**: セミコロン区切りの文字列
   - **typeHint**: 型ヒント（既定は `Text`）
   - **lowerize**: 小文字化する場合 `true`
   - **wrapParen**: 括弧を付けない場合 `false`
5. 出力変数 `soqlInList` を `GetIdsWithDynamicSOQL` の `whereText` に組み込み可能。

---

## 連携例
1. `SemicolonToSoqlInList` で `('A','B','C')` を生成。
2. その結果を利用して `GetIdsWithDynamicSOQL` の `whereText` に設定。  
   例: `"Name IN " & {soqlInList}`

こうすることで、Flow から動的に条件を組み立てた SOQL を実行し、必要なレコードを効率的に取得できます。
