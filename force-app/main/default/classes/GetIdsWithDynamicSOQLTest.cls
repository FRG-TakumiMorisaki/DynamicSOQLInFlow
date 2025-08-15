@IsTest
private class GetIdsWithDynamicSOQLTest {

    // ---------------------------
    // 標準項目のみを使って Account のテストデータを用意
    // ---------------------------
    @TestSetup
    static void setup() {
        List<Account> accs = new List<Account>{
            new Account(Name = 'Acme Alpha',  AnnualRevenue = 100000),
            new Account(Name = 'Acme Beta',   AnnualRevenue = 250000),
            new Account(Name = 'Acme Gamma',  AnnualRevenue = 50),
            new Account(Name = 'Beta Corp',   AnnualRevenue = 300000),
            new Account(Name = 'Zeta Holdings', AnnualRevenue = 1000000)
        };
        insert accs;
    }

    // 基本系：WHERE + ORDER BY + LIMIT（標準項目のみ）
    @IsTest
    static void test_basic_where_orderby_limit() {
        GetIdsWithDynamicSOQL.Input inp = new GetIdsWithDynamicSOQL.Input();
        inp.objectApiName = 'Account';
        // AND/>=/LIKE などの素直な条件（Acme かつ年商10万以上 → Alpha/Beta の2件）
        inp.whereText    = 'Name LIKE \'Acme%\' AND AnnualRevenue >= 100000';
        inp.orderBy      = 'Name ASC';  // 標準項目のみ
        inp.limitSize    = 10;

        List<GetIdsWithDynamicSOQL.Output> outs =
            GetIdsWithDynamicSOQL.run(new List<GetIdsWithDynamicSOQL.Input>{ inp });

        Assert.areEqual(1, outs.size(), '出力は1バッチ1要素');
        GetIdsWithDynamicSOQL.Output o = outs[0];

        Assert.isNotNull(o.ids, 'ids が返る');
        Assert.areEqual(2, o.count, 'ヒット件数が2件');

        // 返却された Id で検証（標準項目のみ参照）
        Map<Id, Account> byId = new Map<Id, Account>(
            [SELECT Id, Name, AnnualRevenue FROM Account WHERE Id IN :o.ids]
        );
        Assert.areEqual(2, byId.size(), 'Id→Account の突合は2件');

        Set<String> names = new Set<String>();
        for (Id i : o.ids) names.add(byId.get(i).Name);
        Assert.isTrue(names.contains('Acme Alpha'));
        Assert.isTrue(names.contains('Acme Beta'));

        // 生成 SOQL の断片確認（トラブルシュート用おまけの確認）
        Assert.isTrue(o.soql.contains('FROM Account'), '対象オブジェクト Account');
        Assert.isTrue(o.soql.contains('WHERE Name LIKE \'Acme%\' AND AnnualRevenue >= 100000'),
                      'WHERE 条件が反映される');
        Assert.isTrue(o.soql.contains('ORDER BY Name ASC'), 'ORDER BY が反映される');
        Assert.isTrue(o.soql.endsWith('LIMIT 10'), 'LIMIT が反映される');
    }

    // ORDER BY に無効フィールドのみ → 既定の並び（CreatedDate DESC, Id DESC）へフォールバック
    @IsTest
    static void test_orderby_fallback_to_default_and_default_limit_in_soql_text() {
        GetIdsWithDynamicSOQL.Input inp = new GetIdsWithDynamicSOQL.Input();
        inp.objectApiName = 'Account';
        inp.whereText     = null;
        inp.orderBy       = 'NoSuchField__c DESC, AlsoBad__c ASC'; // すべて無効 → 無視される
        inp.limitSize     = null; // 既定 200 の想定

        List<GetIdsWithDynamicSOQL.Output> outs =
            GetIdsWithDynamicSOQL.run(new List<GetIdsWithDynamicSOQL.Input>{ inp });

        Assert.areEqual(1, outs.size());
        GetIdsWithDynamicSOQL.Output o = outs[0];

        // SOQL テキストに既定 ORDER/LIMIT が入っていることのみ検証（件数の厳密順序は問わない）
        Assert.isTrue(o.soql.contains('FROM Account'));
        Assert.isTrue(o.soql.contains('ORDER BY CreatedDate DESC, Id DESC'),
                      'ORDER BY 既定へフォールバック');
        Assert.isTrue(o.soql.endsWith('LIMIT 200'), 'LIMIT 既定 200');
    }

    // ORDER BY の方向指定が不正な場合は ASC に丸められる
    @IsTest
    static void test_orderby_direction_sanitized_to_ASC() {
        GetIdsWithDynamicSOQL.Input inp = new GetIdsWithDynamicSOQL.Input();
        inp.objectApiName = 'Account';
        inp.whereText     = 'Name LIKE \'Acme%\'';
        inp.orderBy       = 'Name Downwards, AnnualRevenue up'; // 不正トークン → ASC
        inp.limitSize     = 5;

        List<GetIdsWithDynamicSOQL.Output> outs =
            GetIdsWithDynamicSOQL.run(new List<GetIdsWithDynamicSOQL.Input>{ inp });

        Assert.areEqual(1, outs.size());
        GetIdsWithDynamicSOQL.Output o = outs[0];

        Assert.isTrue(o.soql.contains('ORDER BY Name ASC, AnnualRevenue ASC'),
                      '不正な方向指定は ASC へ矯正される');
    }

    // LIMIT の上限キャップ（2000）を SOQL テキストで確認
    @IsTest
    static void test_limit_cap_applied_in_soql_text() {
        GetIdsWithDynamicSOQL.Input inp = new GetIdsWithDynamicSOQL.Input();
        inp.objectApiName = 'Account';
        inp.whereText     = '';              // 空 → WHERE なし
        inp.orderBy       = 'Id DESC';       // 標準項目
        inp.limitSize     = 999999;          // キャップ対象

        List<GetIdsWithDynamicSOQL.Output> outs =
            GetIdsWithDynamicSOQL.run(new List<GetIdsWithDynamicSOQL.Input>{ inp });

        Assert.areEqual(1, outs.size());
        GetIdsWithDynamicSOQL.Output o = outs[0];

        Assert.isTrue(o.soql.endsWith('LIMIT 2000'), 'LIMIT は 2000 にキャップ');
    }

    // 先頭 AND/OR の除去確認（仕様どおり WHERE 先頭の論理演算子が落ちる）
    @IsTest
    static void test_whereText_leading_AND_OR_trimmed() {
        GetIdsWithDynamicSOQL.Input inp1 = new GetIdsWithDynamicSOQL.Input();
        inp1.objectApiName = 'Account';
        inp1.whereText     = 'AND Name LIKE \'Acme%\'';
        inp1.orderBy       = 'Name ASC';
        inp1.limitSize     = 50;

        GetIdsWithDynamicSOQL.Input inp2 = new GetIdsWithDynamicSOQL.Input();
        inp2.objectApiName = 'Account';
        inp2.whereText     = 'OR AnnualRevenue >= 300000';
        inp2.orderBy       = 'AnnualRevenue DESC';
        inp2.limitSize     = 50;

        List<GetIdsWithDynamicSOQL.Output> outs =
            GetIdsWithDynamicSOQL.run(new List<GetIdsWithDynamicSOQL.Input>{ inp1, inp2 });

        Assert.areEqual(2, outs.size(), 'バッチ入力はフラットに2出力');

        // inp1: "Acme%" → 3件（Alpha/Beta/Gamma）
        GetIdsWithDynamicSOQL.Output o1 = outs[0];
        Assert.isTrue(o1.soql.contains('WHERE Name LIKE \'Acme%\''), '先頭 AND が除去される');
        Set<String> n1 = new Set<String>();
        for (Account a : [SELECT Name FROM Account WHERE Id IN :o1.ids]) n1.add(a.Name);
        Assert.isTrue(n1.contains('Acme Alpha'));
        Assert.isTrue(n1.contains('Acme Beta'));
        Assert.isTrue(n1.contains('Acme Gamma'));

        // inp2: AnnualRevenue >= 300000 → 2件（Beta Corp, Zeta Holdings）
        GetIdsWithDynamicSOQL.Output o2 = outs[1];
        Assert.isTrue(o2.soql.contains('WHERE AnnualRevenue >= 300000'), '先頭 OR が除去される');
        Set<String> n2 = new Set<String>();
        for (Account a : [SELECT Name FROM Account WHERE Id IN :o2.ids]) n2.add(a.Name);
        Assert.isTrue(n2.contains('Beta Corp'));
        Assert.isTrue(n2.contains('Zeta Holdings'));
    }
}
