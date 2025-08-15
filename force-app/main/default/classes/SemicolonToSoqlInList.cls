public without sharing class SemicolonToSoqlInList {
    public class Req {
        @InvocableVariable(required=true) public String semicolonText; // "a1...;a1...; a1..."
        @InvocableVariable public String typeHint;     // Id, Text, Number, Boolean, Date, DateTime（既定 Text）
        @InvocableVariable public Boolean lowerize;    // Text/Id を小文字化したい場合
        @InvocableVariable public Boolean wrapParen;   // 既定 true → "('A','B')"
    }
    public class Res {
        @InvocableVariable(label='CriteriaText') public String soqlInList;   // 例: "('a','b','c')" / "(1,2,3)"
    }
    
    @InvocableMethod(label='SOQL IN List Builder'
                    description='Semicolon-separated text -> IN (...) snippet. Handles quoting, typing, trimming, duplicates.')
    public static List<Res> buildInList(List<Req> reqs){
        List<Res> outs = new List<Res>();
        for (Req r : reqs) {
            Res res = new Res();
            String typeName = (r.typeHint == null) ? 'Text' : r.typeHint.trim();
            Boolean wrap = (r.wrapParen == null) ? true : r.wrapParen;

            Set<String> uniq = new Set<String>();
            if (r.semicolonText != null) {
                for (String piece : r.semicolonText.split('\\s*;\\s*')) {
                    if (String.isBlank(piece)) continue;
                    uniq.add(piece.trim());
                }
            }

            List<String> literals = new List<String>();
            for (String v : uniq) {
                literals.add(toLiteralByHint(typeName, v, r.lowerize == true));
            }

            String joined = String.join(literals, ',');
            res.soqlInList = wrap ? '(' + joined + ')' : joined;

            outs.add(res);
        }
        return outs;
    }


    // 型ヒントに応じたSOQLリテラル化
    private static String toLiteralByHint(String typeName, String raw, Boolean lowerize){
        if (raw == null) return 'NULL';
        String h = (typeName == null) ? 'text' : typeName.toLowerCase();

        if (h == 'number') {
            return String.valueOf(Decimal.valueOf(raw));
        }
        if (h == 'boolean') {
            return (raw.equalsIgnoreCase('true')) ? 'true' : 'false';
        }
        if (h == 'date') {
            Date d = Date.valueOf(raw); // 入力は "YYYY-MM-DD" 推奨
            return '\'' + d.year() + '-' + two(d.month()) + '-' + two(d.day()) + '\'';
        }
        if (h == 'datetime') {
            Datetime dt = Datetime.valueOf(raw); // "YYYY-MM-DD HH:MM:SS" 等
            return '\'' + dt.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'GMT') + '\'';
        }
        // 'id' / 'text' / その他 → クォート＋エスケープ
        String v = String.escapeSingleQuotes(raw);
        if (lowerize == true) v = v.toLowerCase();
        return '\'' + v + '\'';
    }

    // 0埋めヘルパ
    private static String two(Integer n){
        return (n < 10 ? '0' : '') + String.valueOf(n);
    }
}
