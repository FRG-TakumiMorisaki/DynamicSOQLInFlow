public without sharing class GetIdsWithDynamicSOQL {
    public class Input {
        @InvocableVariable(required=true) public String objectApiName; // 例: 'Account'
        @InvocableVariable public String whereText;                    // 例: "Name LIKE '%acme%' AND AnnualRevenue >= 100000"
        @InvocableVariable public String orderBy;                      // 例: "CreatedDate DESC, Id DESC"（そのまま適用）
        @InvocableVariable public Integer limitSize;                   // 例: 200
    }

    public class Output {
        @InvocableVariable(label='Ids')   public List<Id> ids;   // フローで「コレクション」として参照可
        @InvocableVariable(label='Count') public Integer count;  // おまけ: 件数
        @InvocableVariable(label='SOQL')  public String soql;    // おまけ: 実行SOQL文字列（トラブルシュート用）
    }

    @InvocableMethod(label='Get IDs with Dynamic SOQL (generic)'
                     description='Executes dynamic SOQL built in Flow. Returns List<Output> where Output.ids is List<Id>.')
    public static List<Output> run(List<Input> batches){
        List<Output> outs = new List<Output>();
        for (Input inParam : batches) {
            // SOQL 構築と実行
            String soql = buildSoql(inParam);
            List<SObject> recs = Database.query(soql);

            List<Id> ids = new List<Id>();
            for (SObject r : recs) ids.add((Id) r.get('Id'));

            Output o = new Output();
            o.ids   = ids;
            o.count = ids.size();
            o.soql  = soql;
            outs.add(o);
        }
        return outs; // ★ List<Output>（フラット）を返す
    }

    // ===== Helper =====
    private static String buildSoql(Input inParam){
        if (String.isBlank(inParam.objectApiName)) {
            throw new AuraHandledException('objectApiName is required.');
        }
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(inParam.objectApiName);
        if (sType == null) throw new AuraHandledException('Invalid object: ' + inParam.objectApiName);

        Schema.DescribeSObjectResult sDesc = sType.getDescribe();
        if (!sDesc.isAccessible()) throw new AuraHandledException('No read access to object: ' + inParam.objectApiName);

        Map<String, Schema.SObjectField> fMap = sDesc.fields.getMap();

        // WHERE（フリーテキスト）
        String whereSql = '';
        if (!String.isBlank(inParam.whereText)) {
            String w = inParam.whereText.trim();
            w = w.replaceAll('^(?i)AND\\s+', '');
            w = w.replaceAll('^(?i)OR\\s+', '');
            whereSql = ' WHERE ' + w;
        }

        // ORDER BY（存在するフィールド名のみ採用）
        String orderBySql = '';
        if (!String.isBlank(inParam.orderBy)) {
            List<String> parts = new List<String>();
            for (String token : inParam.orderBy.split(',')) {
                String t = token.trim();
                if (t == '') continue;
                List<String> seg = t.split('\\s+');
                String f = seg[0];
                String dir = (seg.size()>1) ? seg[1].toUpperCase() : 'ASC';
                if (!fMap.containsKey(f)) continue; // 存在しないフィールドは無視
                if (dir != 'ASC' && dir != 'DESC') dir = 'ASC';
                parts.add(f + ' ' + dir);
            }
            if (!parts.isEmpty()) orderBySql = ' ORDER BY ' + String.join(parts, ', ');
        }
        if (orderBySql == '') orderBySql = ' ORDER BY CreatedDate DESC, Id DESC';

        // LIMIT（デフォルト＋キャップ）
        Integer lim = (inParam.limitSize==null || inParam.limitSize<=0) ? 200 : inParam.limitSize;
        Integer LIMIT_CAP = 2000;
        if (lim > LIMIT_CAP) lim = LIMIT_CAP;

        return 'SELECT Id FROM ' + inParam.objectApiName + whereSql + orderBySql + ' LIMIT ' + String.valueOf(lim);
    }
}
