@IsTest
private class SemicolonToSoqlInListTest {

    // ---------- 小さなユーティリティ ----------
    // 出力 "(...)" または "a,b,c" をカンマで分割して Set<string> に
    private static Set<String> toTokenSet(String soqlInList) {
        String s = soqlInList == null ? '' : soqlInList.trim();
        if (s.startsWith('(') && s.endsWith(')')) {
            s = s.substring(1, s.length() - 1);
        }
        Set<String> out = new Set<String>();
        if (String.isBlank(s)) return out;
        for (String piece : s.split(',')) {
            out.add(piece.trim());
        }
        return out;
    }

    // SOQL 文字列リテラルから外側のシングルクォートを外し、エスケープ（'' → '）を戻す
    private static String unquoteSoqlString(String token) {
        String t = token;
        if (t != null && t.length() >= 2 && t.startsWith('\'') && t.endsWith('\'')) {
            t = t.substring(1, t.length() - 1);
        }
        // Apexの escapeSingleQuotes は ' を '' にするため、戻すときは '' → '
        t = t.replace('\'\'', '\'');
        return t;
    }

    // ---------- テスト本体 ----------
    @IsTest
    static void test_Text_Defaults_trim_dedup() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = ' A ;B;A ;  C  ;  '; // スペース混在 & 重複
        // typeHint / wrapParen / lowerize は既定（Text, wrap=true, lowerize=null）
        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });

        Assert.areEqual(1, res.size(), '単一要求 → 単一結果');
        String out = res[0].soqlInList;

        Assert.isTrue(out.startsWith('(') && out.endsWith(')'), '既定で括弧でラップされる');

        // 順序は Set の性質で不定なので集合として比較
        Set<String> tokens = toTokenSet(out);
        Assert.areEqual(3, tokens.size(), '重複は排除される');
        // 文字列リテラル（クォート付き）で入っていること
        Assert.isTrue(tokens.contains('\'A\''));
        Assert.isTrue(tokens.contains('\'B\''));
        Assert.isTrue(tokens.contains('\'C\''));
    }

    @IsTest
    static void test_Text_escape_single_quote() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = 'O\'Hara; D\'Angelo';
        List<SemicolonToSoqlInList.Res> res =
            SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });

        Set<String> tokens = toTokenSet(res[0].soqlInList);

        // 実装（String.escapeSingleQuotes）と同じ方法で期待値を作る
        String e1 = '\'' + String.escapeSingleQuotes('O\'Hara')   + '\'';
        String e2 = '\'' + String.escapeSingleQuotes('D\'Angelo') + '\'';

        Assert.isTrue(tokens.contains(e1), 'シングルクォートを含む値1が正しくエスケープされる');
        Assert.isTrue(tokens.contains(e2), 'シングルクォートを含む値2が正しくエスケープされる');
    }


    @IsTest
    static void test_Id_lowerize_true() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = '001ABC; 001def ';
        r.typeHint = 'Id';
        r.lowerize = true;
        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });

        Set<String> tokens = toTokenSet(res[0].soqlInList);
        Assert.isTrue(tokens.contains('\'001abc\''), 'Id が小文字化される①');
        Assert.isTrue(tokens.contains('\'001def\''), 'Id が小文字化される②');
    }

    @IsTest
    static void test_wrapParen_false_outputs_joined_only() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = 'A;B';
        r.wrapParen = false;

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });
        String out = res[0].soqlInList;

        Assert.isFalse(out.startsWith('(') || out.endsWith(')'), 'wrapParen=false では括弧なし');
        // トークンとしては 'A' と 'B' が含まれていること
        Set<String> tokens = toTokenSet(out);
        Assert.isTrue(tokens.contains('\'A\'') && tokens.contains('\'B\''));
    }

    @IsTest
    static void test_Number_hint_coercion_and_dedup() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = '01; 2; 2; 3';
        r.typeHint = 'Number';

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });
        Set<String> tokens = toTokenSet(res[0].soqlInList);

        // Decimal.valueOf により 01 → 1 になる。重複 2 は 1 つに。
        Assert.areEqual(new Set<String>{ '1', '2', '3' }, tokens);
    }

    @IsTest
    static void test_Boolean_hint_true_false_mapping() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = 'true; TRUE; nope; false';
        r.typeHint = 'Boolean';

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });
        Set<String> tokens = toTokenSet(res[0].soqlInList);

        // equalsIgnoreCase('true') のときのみ 'true'、それ以外は 'false'
        // 重複除去により {true,false} の二値のみ
        Assert.areEqual(new Set<String>{ 'true', 'false' }, tokens);
    }

    @IsTest
    static void test_Date_hint_iso_format_padding() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = '2025-07-03; 2025-12-31';
        r.typeHint = 'Date';

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });
        Set<String> tokens = toTokenSet(res[0].soqlInList);

        // 'YYYY-MM-DD' 形式でクォートされる（ゼロ埋め確認）
        Assert.isTrue(tokens.contains('\'2025-07-03\''));
        Assert.isTrue(tokens.contains('\'2025-12-31\''));
    }

    @IsTest
    static void test_Datetime_hint_utc_Z_format() {
        SemicolonToSoqlInList.Req r = new SemicolonToSoqlInList.Req();
        r.semicolonText = '2025-08-01 12:34:56';
        r.typeHint = 'DateTime';

        List<SemicolonToSoqlInList.Res> res =
            SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r });
        Set<String> tokens = toTokenSet(res[0].soqlInList);

        // 実装と同じ手順（valueOf → GMTで format → 'Z'）で期待値を算出し、TZ依存を排除
        Datetime dt = Datetime.valueOf('2025-08-01 12:34:56');
        String expected = '\'' + dt.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'GMT') + '\'';

        Assert.isTrue(tokens.contains(expected),
            'DateTime は GMT で Z 付き ISO 形式に整形される（期待: ' + expected + '）');

        // 追加の健全性（末尾Z）
        for (String t : tokens) {
            Assert.isTrue(t.endsWith('Z\''), 'UTC(Z) で出力されることを確認');
        }
    }


    @IsTest
    static void test_null_and_blank_inputs() {
        // 1) null → 空集合 → 既定 wrap=true なので "()"
        SemicolonToSoqlInList.Req r1 = new SemicolonToSoqlInList.Req();
        r1.semicolonText = null;

        // 2) 空白やセミコロンのみ → 同様に空集合
        SemicolonToSoqlInList.Req r2 = new SemicolonToSoqlInList.Req();
        r2.semicolonText = ' ;  ;   ';

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ r1, r2 });

        Assert.areEqual(2, res.size());
        Assert.areEqual('()', res[0].soqlInList, 'null 入力は空の括弧');
        Assert.areEqual('()', res[1].soqlInList, '空白のみも空の括弧');
    }

    @IsTest
    static void test_multiple_reqs_batched() {
        SemicolonToSoqlInList.Req a = new SemicolonToSoqlInList.Req();
        a.semicolonText = 'A;B';

        SemicolonToSoqlInList.Req b = new SemicolonToSoqlInList.Req();
        b.semicolonText = '1;2';
        b.typeHint = 'Number';

        List<SemicolonToSoqlInList.Res> res = SemicolonToSoqlInList.buildInList(new List<SemicolonToSoqlInList.Req>{ a, b });

        Assert.areEqual(2, res.size(), '要求が 2 件なら結果も 2 件');

        Set<String> t0 = toTokenSet(res[0].soqlInList);
        Assert.areEqual(new Set<String>{'\'A\'','\'B\''}, t0);

        Set<String> t1 = toTokenSet(res[1].soqlInList);
        Assert.areEqual(new Set<String>{'1','2'}, t1);
    }
}
