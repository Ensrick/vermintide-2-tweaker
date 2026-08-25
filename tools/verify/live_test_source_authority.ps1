# Authoritative deployed-build inputs for CURRENT LIVE TEST cards.
#
# Every authority record is tied to one canonical inventory row, one release
# manifest row, and Lua source read from the exact recorded Git object. The
# scanner intentionally recognizes a small Lua subset and fails closed when a
# callable or finite-output proof is ambiguous. Steam ManifestID authority is
# deliberately out of scope here; this module preserves only card-local pair
# consistency through the lifecycle policy.

if (-not ('VtLiveCardLuaLexerV2' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

public sealed class VtLiveCardLuaTokenV2 {
    public string Kind { get; set; }
    public string Text { get; set; }
    public string Value { get; set; }
    public int Start { get; set; }
    public int Length { get; set; }
    public int Line { get; set; }
    public int Column { get; set; }
}

public sealed class VtLiveCardLuaRouteV2 {
    public string RouteKind { get; set; }
    public string Signature { get; set; }
    public string Marker { get; set; }
    public string Callable { get; set; }
    public string Command { get; set; }
    public string Tag { get; set; }
    public int Line { get; set; }
    public int TokenIndex { get; set; }
}

public sealed class VtLiveCardLuaSpanV2 {
    public string Kind { get; set; }
    public int Start { get; set; }
    public int End { get; set; }
    public string Command { get; set; }
    public int CommandTokenIndex { get; set; }
}

public static class VtLiveCardLuaLexerV2 {
    private sealed class Block { public string Kind; public int Start; public bool HasDo; }
    private static bool IsNameStart(char c) { return c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
    private static bool IsNamePart(char c) { return IsNameStart(c) || (c >= '0' && c <= '9'); }
    private static int LongOpen(string s, int at, out int eq) {
        eq = 0;
        if (at >= s.Length || s[at] != '[') return 0;
        int i = at + 1;
        while (i < s.Length && s[i] == '=') { eq++; i++; }
        return i < s.Length && s[i] == '[' ? i - at + 1 : 0;
    }
    private static void Move(string s, ref int i, int end, ref int line, ref int col) {
        while (i < end) {
            if (s[i] == '\r') {
                if (i + 1 < end && s[i + 1] == '\n') i++;
                i++; line++; col = 1;
            } else if (s[i] == '\n') {
                i++; line++; col = 1;
            } else { i++; col++; }
        }
    }
    private static void Add(List<VtLiveCardLuaTokenV2> a, string kind, string text, string value, int start, int line, int col) {
        a.Add(new VtLiveCardLuaTokenV2 { Kind=kind, Text=text, Value=value, Start=start, Length=text.Length, Line=line, Column=col });
    }
    private static bool T(VtLiveCardLuaTokenV2[] a, int i, string text, string kind=null) {
        return i>=0 && i<a.Length && (kind==null || String.Equals(a[i].Kind,kind,StringComparison.Ordinal)) &&
            (text==null || String.Equals(a[i].Text,text,StringComparison.Ordinal));
    }
    private static bool Standalone(VtLiveCardLuaTokenV2[] a, int i) {
        return T(a,i,"printf","Identifier") && !T(a,i-1,".") && !T(a,i-1,":");
    }
    private static int MatchClose(VtLiveCardLuaTokenV2[] a, int open) {
        if(open<0 || open>=a.Length)return -1;
        var expected=new Stack<string>();
        for(int i=open;i<a.Length;i++) {
            string s=a[i].Text;
            if(s=="(")expected.Push(")");else if(s=="{")expected.Push("}");else if(s=="[")expected.Push("]");
            else if(s==")"||s=="}"||s=="]") {
                if(expected.Count==0 || !String.Equals(expected.Peek(),s,StringComparison.Ordinal))return -1;
                expected.Pop();if(expected.Count==0)return i;
            }
        }
        return -1;
    }
    public static bool RawPrintfUnshadowed(VtLiveCardLuaTokenV2[] a) {
        if(a==null)return true;
        for(int i=0;i<a.Length;i++) {
            if(!Standalone(a,i))continue;
            if(T(a,i-1,"local","Identifier")||T(a,i-1,"function","Identifier")||T(a,i+1,"="))return false;
        }
        for(int i=0;i<a.Length;i++) {
            if(T(a,i,"_G","Identifier")&&T(a,i+1,".")&&T(a,i+2,"printf","Identifier")&&T(a,i+3,"="))return false;
            if(T(a,i,"_G","Identifier")&&T(a,i+1,"[")&&T(a,i+2,null,"String")&&
                String.Equals(a[i+2].Value,"printf",StringComparison.Ordinal)&&T(a,i+3,"]")&&T(a,i+4,"="))return false;
            if(T(a,i,"rawset","Identifier")&&T(a,i+1,"(")&&T(a,i+2,"_G","Identifier")&&T(a,i+3,",")&&
                T(a,i+4,null,"String")&&String.Equals(a[i+4].Value,"printf",StringComparison.Ordinal))return false;
        }
        // Reject printf anywhere in a plain multiple-assignment LHS.
        for(int i=0;i<a.Length;i++) {
            if(!T(a,i,null,"Identifier"))continue;
            bool contains=Standalone(a,i);int j=i;
            while(j+2<a.Length&&T(a,j+1,",")&&T(a,j+2,null,"Identifier")){j+=2;contains=contains||Standalone(a,j);}
            if(contains&&T(a,j+1,"="))return false;
        }
        // Generic/numeric for variables shadow globals throughout the body.
        for(int i=0;i<a.Length;i++) {
            if(!T(a,i,"for","Identifier"))continue;
            bool contains=false;int j=i+1;
            while(j<a.Length&&T(a,j,null,"Identifier")) {
                contains=contains||Standalone(a,j);
                if(j+1<a.Length&&T(a,j+1,",")){j+=2;continue;}
                break;
            }
            if(contains&&(T(a,j+1,"in","Identifier")||T(a,j+1,"=")))return false;
        }
        for(int i=0;i+1<a.Length;i++) {
            if(!T(a,i,"function","Identifier"))continue;
            int open=-1;
            for(int j=i+1;j<Math.Min(a.Length,i+8);j++){if(T(a,j,"(")){open=j;break;}}
            if(open<0)continue;
            int close=MatchClose(a,open);if(close<0)return false;
            for(int j=open+1;j<close;j++){if(T(a,j,"printf","Identifier"))return false;}
        }
        return true;
    }
    private static string MarkerOf(string signature) {
        if(String.IsNullOrEmpty(signature)||signature[0]!='[')return null;
        int close=signature.IndexOf(']');if(close<=1)return null;
        string marker=signature.Substring(0,close+1);
        int colon=marker.IndexOf(':');if(colon<2)return null;
        for(int i=1;i<marker.Length-1;i++) {
            char c=marker[i];
            if(!(Char.IsLetterOrDigit(c)||c=='_'||c=='-'||c=='.'||c==':'))return null;
        }
        return marker;
    }
    private static string LiteralConcat(VtLiveCardLuaTokenV2[] a, int literal) {
        if(!T(a,literal,null,"String"))return null;
        var value=new StringBuilder(a[literal].Value);int i=literal+1;
        while(i+1<a.Length&&T(a,i,"..")&&T(a,i+1,null,"String")){value.Append(a[i+1].Value);i+=2;}
        return value.ToString();
    }
    private static void AddReceipt(List<VtLiveCardLuaRouteV2> routes, VtLiveCardLuaTokenV2[] a, int at, int literal, string callable) {
        string signature=LiteralConcat(a,literal);string marker=MarkerOf(signature);if(marker==null)return;
        routes.Add(new VtLiveCardLuaRouteV2 { RouteKind=marker.EndsWith(":LOAD]",StringComparison.OrdinalIgnoreCase)?"load":"receipt",
            Signature=signature,Marker=marker,Callable=callable,Line=a[at].Line,TokenIndex=at });
    }
    private static string BannerTag(string signature) {
        if(String.IsNullOrEmpty(signature)||signature[0]!='[')return null;
        int close=signature.IndexOf(']');if(close<2)return null;
        string tag=signature.Substring(0,close+1);
        string suffix=signature.Substring(close+1).TrimStart();
        return suffix.StartsWith("v%s loaded",StringComparison.Ordinal)?tag:null;
    }
    public static VtLiveCardLuaRouteV2[] ScanDirect(VtLiveCardLuaTokenV2[] a) {
        var routes=new List<VtLiveCardLuaRouteV2>();if(a==null)return routes.ToArray();
        bool raw=RawPrintfUnshadowed(a);
        for(int i=0;i<a.Length;i++) {
            if(i+4<a.Length&&T(a,i,"mod","Identifier")&&T(a,i+1,":")&&T(a,i+2,"command","Identifier")&&T(a,i+3,"(")&&T(a,i+4,null,"String")) {
                string name=a[i+4].Value;bool valid=!String.IsNullOrEmpty(name)&&Char.IsLetter(name[0])&&Char.IsLower(name[0]);
                for(int j=1;valid&&j<name.Length;j++){char c=name[j];valid=(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c==':'||c=='-';}
                if(valid)routes.Add(new VtLiveCardLuaRouteV2 { RouteKind="command",Command="/"+name,Line=a[i].Line,TokenIndex=i });
            }
            if(raw&&i+2<a.Length&&Standalone(a,i)&&T(a,i+1,"(")&&T(a,i+2,null,"String"))AddReceipt(routes,a,i,i+2,"printf");
            else if(raw&&i+4<a.Length&&T(a,i,"pcall","Identifier")&&T(a,i+1,"(")&&T(a,i+2,"printf","Identifier")&&T(a,i+3,",")&&T(a,i+4,null,"String"))AddReceipt(routes,a,i,i+4,"pcall-printf");

            if(i+4<a.Length&&T(a,i,"mod","Identifier")&&T(a,i+1,":")&&
                (T(a,i+2,"info","Identifier")||T(a,i+2,"echo","Identifier")||T(a,i+2,"warning","Identifier")||T(a,i+2,"error","Identifier"))&&
                T(a,i+3,"(")&&T(a,i+4,null,"String")) {
                string signature=LiteralConcat(a,i+4);string marker=MarkerOf(signature);
                if(marker!=null&&marker.EndsWith(":LOAD]",StringComparison.OrdinalIgnoreCase))routes.Add(new VtLiveCardLuaRouteV2 { RouteKind="load",Signature=signature,Marker=marker,Callable="mod-log",Line=a[i].Line,TokenIndex=i });
                string tag=BannerTag(signature);if(tag!=null)routes.Add(new VtLiveCardLuaRouteV2 { RouteKind="banner",Signature=signature,Tag=tag,Line=a[i].Line,TokenIndex=i });
            }
            if(i+8<a.Length&&T(a,i,"mod","Identifier")&&T(a,i+1,":")&&(T(a,i+2,"info","Identifier")||T(a,i+2,"echo","Identifier"))&&
                T(a,i+3,"(")&&T(a,i+4,"string","Identifier")&&T(a,i+5,".")&&T(a,i+6,"format","Identifier")&&T(a,i+7,"(")&&T(a,i+8,null,"String")) {
                string signature=LiteralConcat(a,i+8);string tag=BannerTag(signature);if(tag!=null)routes.Add(new VtLiveCardLuaRouteV2 { RouteKind="banner",Signature=signature,Tag=tag,Line=a[i].Line,TokenIndex=i });
            }
        }
        return routes.ToArray();
    }
    public static VtLiveCardLuaRouteV2[] ScanDocumentLoads(VtLiveCardLuaTokenV2[] a) {
        var routes=new List<VtLiveCardLuaRouteV2>();if(a==null)return routes.ToArray();
        for(int i=0;i<a.Length;i++) {
            int literal=-1;
            if(i+4<a.Length&&T(a,i,"mod","Identifier")&&T(a,i+1,":")&&T(a,i+2,"dofile","Identifier")&&T(a,i+3,"(")&&T(a,i+4,null,"String"))literal=i+4;
            else if(i+6<a.Length&&T(a,i,"mod","Identifier")&&T(a,i+1,".")&&T(a,i+2,"dofile","Identifier")&&T(a,i+3,"(")&&T(a,i+4,"mod","Identifier")&&T(a,i+5,",")&&T(a,i+6,null,"String"))literal=i+6;
            else if(i+8<a.Length&&T(a,i,"pcall","Identifier")&&T(a,i+1,"(")&&T(a,i+2,"mod","Identifier")&&T(a,i+3,".")&&T(a,i+4,"dofile","Identifier")&&T(a,i+5,",")&&T(a,i+6,"mod","Identifier")&&T(a,i+7,",")&&T(a,i+8,null,"String"))literal=i+8;
            else if(i+2<a.Length&&T(a,i,"require","Identifier")&&T(a,i+1,"(")&&T(a,i+2,null,"String"))literal=i+2;
            if(literal>=0)routes.Add(new VtLiveCardLuaRouteV2 { RouteKind="document-load",Signature=a[literal].Value,Line=a[i].Line,TokenIndex=i });
        }
        return routes.ToArray();
    }
    public static bool ContainsAnchor(VtLiveCardLuaTokenV2[] a, string[] specs) {
        if(a==null||specs==null||specs.Length==0||specs.Length>a.Length)return false;
        for(int i=0;i<=a.Length-specs.Length;i++) {
            bool matches=true;
            for(int j=0;j<specs.Length;j++) {
                string spec=specs[j]??"";VtLiveCardLuaTokenV2 token=a[i+j];bool ok;
                if(String.Equals(spec,"$IDENT",StringComparison.Ordinal))ok=String.Equals(token.Kind,"Identifier",StringComparison.Ordinal);
                else if(String.Equals(spec,"$STRING",StringComparison.Ordinal))ok=String.Equals(token.Kind,"String",StringComparison.Ordinal);
                else if(spec.StartsWith("String:",StringComparison.Ordinal))ok=String.Equals(token.Kind,"String",StringComparison.Ordinal)&&String.Equals(token.Value,spec.Substring(7),StringComparison.Ordinal);
                else ok=String.Equals(token.Text,spec,StringComparison.Ordinal);
                if(!ok){matches=false;break;}
            }
            if(matches)return true;
        }
        return false;
    }
    private static VtLiveCardLuaSpanV2[] ScanBlockSpans(VtLiveCardLuaTokenV2[] a, bool functions) {
        var stack=new List<Block>();var spans=new List<VtLiveCardLuaSpanV2>();if(a==null)return spans.ToArray();
        for(int i=0;i<a.Length;i++) {
            string text=a[i].Text;
            if(text=="function"||text=="if"||text=="for"||text=="while"||text=="repeat") {
                stack.Add(new Block { Kind=text,Start=i,HasDo=false });continue;
            }
            if(text=="do") {
                if(stack.Count>0&&(stack[stack.Count-1].Kind=="for"||stack[stack.Count-1].Kind=="while")&&!stack[stack.Count-1].HasDo)stack[stack.Count-1].HasDo=true;
                else stack.Add(new Block { Kind="do",Start=i,HasDo=true });
                continue;
            }
            if(text=="until") {
                for(int j=stack.Count-1;j>=0;j--)if(stack[j].Kind=="repeat") {
                    Block entry=stack[j];stack.RemoveAt(j);
                    if(!functions)spans.Add(new VtLiveCardLuaSpanV2 { Kind="repeat",Start=entry.Start,End=i });
                    break;
                }
                continue;
            }
            if(text=="end") {
                for(int j=stack.Count-1;j>=0;j--)if(stack[j].Kind!="repeat") {
                    Block entry=stack[j];stack.RemoveAt(j);
                    if(functions&&entry.Kind=="function")spans.Add(new VtLiveCardLuaSpanV2 { Kind="function",Start=entry.Start,End=i });
                    else if(!functions&&(entry.Kind=="for"||entry.Kind=="while"))spans.Add(new VtLiveCardLuaSpanV2 { Kind=entry.Kind,Start=entry.Start,End=i });
                    break;
                }
            }
        }
        return spans.ToArray();
    }
    public static VtLiveCardLuaSpanV2[] ScanFunctionSpans(VtLiveCardLuaTokenV2[] a) { return ScanBlockSpans(a,true); }
    public static VtLiveCardLuaSpanV2[] ScanLoopSpans(VtLiveCardLuaTokenV2[] a) { return ScanBlockSpans(a,false); }
    public static VtLiveCardLuaSpanV2[] ScanCommandCallbacks(VtLiveCardLuaTokenV2[] a, VtLiveCardLuaSpanV2[] functions) {
        var spans=new List<VtLiveCardLuaSpanV2>();if(a==null||functions==null)return spans.ToArray();
        for(int i=0;i+4<a.Length;i++) {
            if(!(T(a,i,"mod","Identifier")&&T(a,i+1,":")&&T(a,i+2,"command","Identifier")&&T(a,i+3,"(")&&T(a,i+4,null,"String")))continue;
            int close=MatchClose(a,i+3);if(close<0)continue;
            int depth=0,lastStart=i+4;
            for(int j=i+4;j<close;j++) {
                string text=a[j].Text;
                if(text=="("||text=="{"||text=="[")depth++;
                else if(text==")"||text=="}"||text=="]")depth--;
                else if(text==","&&depth==0)lastStart=j+1;
            }
            for(int j=0;j<functions.Length;j++)if(functions[j].Start==lastStart&&functions[j].End==close-1) {
                spans.Add(new VtLiveCardLuaSpanV2 { Kind="command",Start=functions[j].Start,End=functions[j].End,Command="/"+a[i+4].Value,CommandTokenIndex=i });break;
            }
            i=close;
        }
        return spans.ToArray();
    }
    public static bool ContainsIdentifier(VtLiveCardLuaTokenV2[] a, int start, int end, string name) {
        if(a==null||String.IsNullOrEmpty(name))return false;start=Math.Max(0,start);end=Math.Min(a.Length-1,end);
        for(int i=start;i<=end;i++)if(String.Equals(a[i].Kind,"Identifier",StringComparison.Ordinal)&&String.Equals(a[i].Text,name,StringComparison.Ordinal))return true;
        return false;
    }
    public static VtLiveCardLuaTokenV2[] Tokenize(string s) {
        if (String.IsNullOrEmpty(s)) return new VtLiveCardLuaTokenV2[0];
        var a = new List<VtLiveCardLuaTokenV2>();
        int i=0, line=1, col=1;
        while (i < s.Length) {
            char ch=s[i];
            if (ch=='\r') { if(i+1<s.Length && s[i+1]=='\n')i++; i++;line++;col=1;continue; }
            if (ch=='\n') { i++;line++;col=1;continue; }
            if (Char.IsWhiteSpace(ch)) { i++;col++;continue; }
            if (ch=='-' && i+1<s.Length && s[i+1]=='-') {
                i+=2;col+=2; int eq; int open=LongOpen(s,i,out eq);
                if(open>0) {
                    i+=open;col+=open; string close="]"+new string('=',eq)+"]";
                    int closeAt=s.IndexOf(close,i,StringComparison.Ordinal);
                    int end=closeAt<0?s.Length:closeAt+close.Length; Move(s,ref i,end,ref line,ref col);
                } else { while(i<s.Length && s[i]!='\r' && s[i]!='\n'){i++;col++;} }
                continue;
            }
            int start=i, tokenLine=line, tokenCol=col;
            if(ch=='\'' || ch=='\"') {
                char quote=ch; i++;col++; var value=new StringBuilder(); bool closed=false;
                while(i<s.Length) {
                    char c=s[i];
                    if(c==quote){i++;col++;closed=true;break;}
                    if(c=='\\' && i+1<s.Length) {
                        char n=s[i+1];
                        switch(n){case 'n':value.Append('\n');break;case 'r':value.Append('\r');break;case 't':value.Append('\t');break;case 'a':value.Append((char)7);break;case 'b':value.Append((char)8);break;case 'f':value.Append((char)12);break;case 'v':value.Append((char)11);break;default:value.Append(n);break;}
                        i+=2;col+=2;continue;
                    }
                    if(c=='\r'||c=='\n')break;
                    value.Append(c);i++;col++;
                }
                string text=s.Substring(start,i-start);Add(a,closed?"String":"InvalidString",text,value.ToString(),start,tokenLine,tokenCol);continue;
            }
            if(ch=='[') {
                int eq; int open=LongOpen(s,i,out eq);
                if(open>0) {
                    int body=start+open; string close="]"+new string('=',eq)+"]";
                    int closeAt=s.IndexOf(close,body,StringComparison.Ordinal); bool closed=closeAt>=0;
                    int end=closed?closeAt+close.Length:s.Length; string value=s.Substring(body,(closed?closeAt:s.Length)-body);
                    if(value.StartsWith("\r\n",StringComparison.Ordinal))value=value.Substring(2);else if(value.StartsWith("\r",StringComparison.Ordinal)||value.StartsWith("\n",StringComparison.Ordinal))value=value.Substring(1);
                    Move(s,ref i,end,ref line,ref col);string text=s.Substring(start,end-start);Add(a,closed?"String":"InvalidString",text,value,start,tokenLine,tokenCol);continue;
                }
            }
            if(IsNameStart(ch)) { i++;col++;while(i<s.Length&&IsNamePart(s[i])){i++;col++;}string text=s.Substring(start,i-start);Add(a,"Identifier",text,text,start,tokenLine,tokenCol);continue; }
            if(ch>='0'&&ch<='9') { i++;col++;while(i<s.Length&&(Char.IsLetterOrDigit(s[i])||s[i]=='_'||s[i]=='.')){i++;col++;}string text=s.Substring(start,i-start);Add(a,"Number",text,text,start,tokenLine,tokenCol);continue; }
            string op=null; string[] ops={"...","..","==","~=","<=",">=","::","//","<<",">>"};
            foreach(string candidate in ops){if(i+candidate.Length<=s.Length&&String.CompareOrdinal(s,i,candidate,0,candidate.Length)==0){op=candidate;break;}}
            if(op==null)op=ch.ToString();i+=op.Length;col+=op.Length;Add(a,"Punctuation",op,op,start,tokenLine,tokenCol);
        }
        return a.ToArray();
    }
}
'@
}

function New-VtLuaToken {
    param(
        [string]$Kind,
        [string]$Text,
        [string]$Value,
        [int]$Start,
        [int]$Length,
        [int]$Line,
        [int]$Column
    )
    return [pscustomobject][ordered]@{
        Kind = $Kind
        Text = $Text
        Value = $Value
        Start = $Start
        Length = $Length
        Line = $Line
        Column = $Column
    }
}

function Get-VtLuaLongBracketOpen {
    param([string]$Content, [int]$Start)
    if ($Start -ge $Content.Length -or $Content[$Start] -ne '[') { return $null }
    $i = $Start + 1
    while ($i -lt $Content.Length -and $Content[$i] -eq '=') { $i++ }
    if ($i -ge $Content.Length -or $Content[$i] -ne '[') { return $null }
    return [pscustomobject]@{ Equals = $i - $Start - 1; Length = $i - $Start + 1 }
}

function Get-VtLuaTokens {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    if ('VtLiveCardLuaLexerV2' -as [type]) {
        return @([VtLiveCardLuaLexerV2]::Tokenize([string]$Content))
    }
    $tokens = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($Content)) { return @() }
    $i = 0
    $line = 1
    $column = 1
    while ($i -lt $Content.Length) {
        $ch = $Content[$i]
        if ($ch -eq "`r") {
            if ($i + 1 -lt $Content.Length -and $Content[$i + 1] -eq "`n") { $i++ }
            $i++; $line++; $column = 1; continue
        }
        if ($ch -eq "`n") { $i++; $line++; $column = 1; continue }
        if ([char]::IsWhiteSpace($ch)) { $i++; $column++; continue }

        # Lua line and long comments. Their contents are never tokenized.
        if ($ch -eq '-' -and $i + 1 -lt $Content.Length -and $Content[$i + 1] -eq '-') {
            $commentStart = $i
            $i += 2; $column += 2
            $long = Get-VtLuaLongBracketOpen -Content $Content -Start $i
            if ($long) {
                $close = ']' + ('=' * [int]$long.Equals) + ']'
                $i += [int]$long.Length; $column += [int]$long.Length
                $closeAt = $Content.IndexOf($close, $i, [StringComparison]::Ordinal)
                $end = if ($closeAt -lt 0) { $Content.Length } else { $closeAt + $close.Length }
                while ($i -lt $end) {
                    if ($Content[$i] -eq "`r" -or $Content[$i] -eq "`n") {
                        if ($Content[$i] -eq "`r" -and $i + 1 -lt $end -and $Content[$i + 1] -eq "`n") { $i++ }
                        $i++; $line++; $column = 1
                    }
                    else { $i++; $column++ }
                }
            }
            else {
                while ($i -lt $Content.Length -and $Content[$i] -ne "`r" -and $Content[$i] -ne "`n") { $i++; $column++ }
            }
            continue
        }

        $tokenLine = $line
        $tokenColumn = $column
        $tokenStart = $i

        # Short quoted strings. Decode only literal escapes needed by command,
        # banner, and receipt signatures; unknown escapes retain their payload.
        if ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            $builder = New-Object Text.StringBuilder
            $i++; $column++
            $closed = $false
            while ($i -lt $Content.Length) {
                $current = $Content[$i]
                if ($current -eq $quote) { $i++; $column++; $closed = $true; break }
                if ($current -eq '\\' -and $i + 1 -lt $Content.Length) {
                    $next = $Content[$i + 1]
                    switch ($next) {
                        'n' { [void]$builder.Append("`n") }
                        'r' { [void]$builder.Append("`r") }
                        't' { [void]$builder.Append("`t") }
                        'a' { [void]$builder.Append([char]7) }
                        'b' { [void]$builder.Append([char]8) }
                        'f' { [void]$builder.Append([char]12) }
                        'v' { [void]$builder.Append([char]11) }
                        default { [void]$builder.Append($next) }
                    }
                    $i += 2; $column += 2; continue
                }
                if ($current -eq "`r" -or $current -eq "`n") {
                    # A raw newline is invalid in a short Lua string. Preserve a
                    # token so the surrounding source cannot be misinterpreted.
                    break
                }
                [void]$builder.Append($current)
                $i++; $column++
            }
            $text = $Content.Substring($tokenStart, $i - $tokenStart)
            $kind = if ($closed) { 'String' } else { 'InvalidString' }
            $tokens.Add((New-VtLuaToken $kind $text $builder.ToString() $tokenStart ($i - $tokenStart) $tokenLine $tokenColumn))
            continue
        }

        # Long bracket strings are one literal String token. Their value may be
        # used when the token is a recognized call argument, but is never
        # recursively scanned for command/printf-looking text.
        if ($ch -eq '[') {
            $long = Get-VtLuaLongBracketOpen -Content $Content -Start $i
            if ($long) {
                $openLength = [int]$long.Length
                $close = ']' + ('=' * [int]$long.Equals) + ']'
                $bodyStart = $i + $openLength
                $closeAt = $Content.IndexOf($close, $bodyStart, [StringComparison]::Ordinal)
                $closed = $closeAt -ge 0
                $end = if ($closed) { $closeAt + $close.Length } else { $Content.Length }
                $valueEnd = if ($closed) { $closeAt } else { $Content.Length }
                $value = $Content.Substring($bodyStart, $valueEnd - $bodyStart)
                # Lua discards one initial newline in long-bracket literals.
                if ($value.StartsWith("`r`n")) { $value = $value.Substring(2) }
                elseif ($value.StartsWith("`n") -or $value.StartsWith("`r")) { $value = $value.Substring(1) }
                $i = $end
                $text = $Content.Substring($tokenStart, $end - $tokenStart)
                foreach ($c in $text.ToCharArray()) {
                    if ($c -eq "`n") { $line++; $column = 1 } else { $column++ }
                }
                $kind = if ($closed) { 'String' } else { 'InvalidString' }
                $tokens.Add((New-VtLuaToken $kind $text $value $tokenStart ($end - $tokenStart) $tokenLine $tokenColumn))
                continue
            }
        }

        if (($ch -ge 'A' -and $ch -le 'Z') -or ($ch -ge 'a' -and $ch -le 'z') -or $ch -eq '_') {
            $i++; $column++
            while ($i -lt $Content.Length) {
                $c = $Content[$i]
                if (-not (($c -ge 'A' -and $c -le 'Z') -or ($c -ge 'a' -and $c -le 'z') -or ($c -ge '0' -and $c -le '9') -or $c -eq '_')) { break }
                $i++; $column++
            }
            $text = $Content.Substring($tokenStart, $i - $tokenStart)
            $tokens.Add((New-VtLuaToken 'Identifier' $text $text $tokenStart ($i - $tokenStart) $tokenLine $tokenColumn))
            continue
        }

        if ($ch -ge '0' -and $ch -le '9') {
            $i++; $column++
            while ($i -lt $Content.Length -and $Content[$i] -match '[A-Za-z0-9_.]') { $i++; $column++ }
            $text = $Content.Substring($tokenStart, $i - $tokenStart)
            $tokens.Add((New-VtLuaToken 'Number' $text $text $tokenStart ($i - $tokenStart) $tokenLine $tokenColumn))
            continue
        }

        $operator = $null
        foreach ($candidate in @('...','..','==','~=','<=','>=','::','//','<<','>>')) {
            if ($i + $candidate.Length -le $Content.Length -and $Content.Substring($i, $candidate.Length) -ceq $candidate) {
                $operator = $candidate; break
            }
        }
        if (-not $operator) { $operator = [string]$ch }
        $i += $operator.Length; $column += $operator.Length
        $tokens.Add((New-VtLuaToken 'Punctuation' $operator $operator $tokenStart $operator.Length $tokenLine $tokenColumn))
    }
    return @($tokens.ToArray())
}

function Test-VtLuaToken {
    param($Token, [string]$Text, [string]$Kind)
    if ($null -eq $Token) { return $false }
    if ($Kind -and [string]$Token.Kind -cne $Kind) { return $false }
    if ($Text -and [string]$Token.Text -cne $Text) { return $false }
    return $true
}

function Get-VtLuaMatchingTokenIndex {
    param($Tokens, [int]$OpenIndex)
    if ($OpenIndex -lt 0 -or $OpenIndex -ge @($Tokens).Count) { return -1 }
    $pairs = @{ '('=')'; '{'='}'; '['=']' }
    $open = [string]$Tokens[$OpenIndex].Text
    if (-not $pairs.ContainsKey($open)) { return -1 }
    $stack = New-Object System.Collections.Generic.Stack[string]
    for ($i = $OpenIndex; $i -lt @($Tokens).Count; $i++) {
        $text = [string]$Tokens[$i].Text
        if ($pairs.ContainsKey($text)) { $stack.Push([string]$pairs[$text]); continue }
        if ($text -in @(')', '}', ']')) {
            if ($stack.Count -eq 0 -or $stack.Peek() -cne $text) { return -1 }
            $null = $stack.Pop()
            if ($stack.Count -eq 0) { return $i }
        }
    }
    return -1
}

function Split-VtLuaArguments {
    param($Tokens, [int]$OpenIndex, [int]$CloseIndex)
    $ranges = New-Object System.Collections.Generic.List[object]
    $start = $OpenIndex + 1
    $stack = New-Object System.Collections.Generic.Stack[string]
    $pairs = @{ '('=')'; '{'='}'; '['=']' }
    for ($i = $OpenIndex + 1; $i -lt $CloseIndex; $i++) {
        $text = [string]$Tokens[$i].Text
        if ($pairs.ContainsKey($text)) { $stack.Push([string]$pairs[$text]); continue }
        if ($text -in @(')', '}', ']')) {
            if ($stack.Count -eq 0 -or $stack.Peek() -cne $text) { return @() }
            $null = $stack.Pop(); continue
        }
        if ($text -eq ',' -and $stack.Count -eq 0) {
            $ranges.Add([pscustomobject]@{ Start=$start; End=$i - 1 })
            $start = $i + 1
        }
    }
    if ($stack.Count -ne 0) { return @() }
    if ($start -le $CloseIndex - 1) { $ranges.Add([pscustomobject]@{ Start=$start; End=$CloseIndex - 1 }) }
    elseif ($CloseIndex -eq $OpenIndex + 1) { return @() }
    return @($ranges.ToArray())
}

function Get-VtGitScalar {
    param([string]$RepoRoot, [string[]]$Arguments, [string]$Description)
    $output = & git -C $RepoRoot @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$Description failed: $($output.Trim())" }
    return $output.Trim()
}

function Invoke-VtContractDeployedBlobPrefetch {
    param(
        [string]$RepoRoot,
        [object[]]$DeployedTrees
    )

    # In a blob:none partial clone (the dedicated lifecycle CI checkout and
    # the qa.yml checkout), every deployed-tree blob absent from the local
    # object store costs a promisor network fetch inside the per-mod archive
    # transaction. The 2026-08-13/15 scheduled guard runs exceeded their
    # five-minute ceiling exactly there: 841 deployed blobs were missing under
    # the old qa+tools sparse cone (#750). Enumerate the missing blobs across
    # every deployed source tree first and hydrate them in a few batched
    # fetches, mirroring git's own internal lazy-fetch invocation. Best-effort
    # by design: on any failure the per-object lazy path remains the
    # correctness fallback, only slower, so this warns instead of failing.
    $promisorOutput = @(& git -C $RepoRoot config --get remote.origin.promisor 2>&1)
    if ($LASTEXITCODE -ne 0 -or ([string]$promisorOutput[0]).Trim() -cne 'true') { return }

    $missing = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($target in @($DeployedTrees)) {
        $treeOutput = @(& git -C $RepoRoot rev-parse "$($target.Commit):$($target.Root)" 2>&1)
        # A missing path or commit is reported authoritatively by the main
        # authority pass; the prefetch silently skips it.
        if ($LASTEXITCODE -ne 0 -or $treeOutput.Count -lt 1) { continue }
        $treeId = ([string]$treeOutput[0]).Trim()
        if ($treeId -notmatch '^[0-9a-f]{40,64}$') { continue }
        # --missing=print lists absent objects as ?<oid> without lazy-fetching.
        $objectLines = @(& git -C $RepoRoot rev-list --objects --missing=print $treeId 2>&1)
        if ($LASTEXITCODE -ne 0) { continue }
        foreach ($line in $objectLines) {
            if ([string]$line -match '^\?([0-9a-f]{40,64})$' -and $seen.Add($matches[1])) {
                $missing.Add($matches[1])
            }
        }
    }
    if ($missing.Count -eq 0) { return }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $batches = 0
    for ($offset = 0; $offset -lt $missing.Count; $offset += 200) {
        $last = [Math]::Min($offset + 199, $missing.Count - 1)
        $batch = @($missing[$offset..$last])
        $fetchOutput = @(& git -C $RepoRoot -c fetch.negotiationAlgorithm=noop fetch origin --quiet `
            --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none @batch 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Deployed-blob prefetch batch failed (exit $LASTEXITCODE); falling back to per-blob lazy fetches: $($fetchOutput -join ' ')"
            return
        }
        $batches++
    }
    $stopwatch.Stop()
    Write-Host "[live-test-contract] prefetched $($missing.Count) missing deployed-source blob(s) in $batches batched fetch(es), $([int]$stopwatch.Elapsed.TotalMilliseconds)ms"
}

function Get-VtDeployedLuaDocuments {
    param(
        [string]$RepoRoot,
        [string]$Treeish,
        [string]$RelativeRoot,
        [string[]]$RequiredRelativePaths = @()
    )
    # One archive transaction is materially faster than launching `git show`
    # once per file, while still reading only immutable bytes from Treeish.
    # Archive the deployed subtree itself rather than the commit with a
    # pathspec: `git archive <commit> -- <path>` hydrates every blob in the
    # commit before applying the pathspec, which in a blob:none clone drags
    # the whole bundle tree over the network (#750). `--prefix` keeps the
    # extracted entry paths identical to the pathspec form.
    $archiveTreeish = "$Treeish`:$RelativeRoot"
    $archivePrefix = ($RelativeRoot -replace '\\','/').TrimEnd('/') + '/'
    $temporaryRoot=Join-Path ([IO.Path]::GetTempPath()) ('vt-card-source-'+[guid]::NewGuid().ToString('N'))
    $archivePath=Join-Path $temporaryRoot 'source.tar'
    $extractRoot=Join-Path $temporaryRoot 'tree'
    $documents = New-Object System.Collections.Generic.List[object]
    try{
        New-Item -ItemType Directory -Force -Path $extractRoot|Out-Null
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$archiveOutput=& git -C $RepoRoot archive --format=tar --prefix=$archivePrefix --output=$archivePath $archiveTreeish 2>&1|ForEach-Object{$_.ToString()}|Out-String;$archiveCode=$LASTEXITCODE}
        finally{$ErrorActionPreference=$previous}
        if($archiveCode -ne 0){throw "Cannot archive deployed source '$Treeish`:$RelativeRoot': $($archiveOutput.Trim())"}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$tarOutput=& tar -xf $archivePath -C $extractRoot 2>&1|ForEach-Object{$_.ToString()}|Out-String;$tarCode=$LASTEXITCODE}
        finally{$ErrorActionPreference=$previous}
        if($tarCode -ne 0){throw "Cannot extract deployed source '$Treeish`:$RelativeRoot': $($tarOutput.Trim())"}
        $sourceRoot=Join-Path $extractRoot ($RelativeRoot -replace '/', [IO.Path]::DirectorySeparatorChar)
        $requiredSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($requiredPath in @($RequiredRelativePaths)){$null=$requiredSet.Add(([string]$requiredPath -replace '\\','/'))}
        foreach($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.lua')){
            $path=$file.FullName.Substring($extractRoot.Length).TrimStart([char[]]'\/') -replace '\\','/'
            $content=[IO.File]::ReadAllText($file.FullName)
            # Tokenize every potential contract surface plus every exact source
            # named by an immutable override. Files with no version, logger,
            # command, injected binding, menu/localization surface, or pinned
            # anchor cannot contribute an authority route. This keeps the live
            # all-mod census bounded without trusting the working tree.
            $candidate=$requiredSet.Contains($path) -or
                $path -match '(?i)_(?:data|localization)\.lua$' -or
                $content -match '(?i)MOD_VERSION|printf|\bmod\s*:|deps\.|dofile|v%s\s+loaded|\b(?:getfenv|setfenv|rawset)\b'
            if(-not$candidate){continue}
            $documents.Add([pscustomobject][ordered]@{
                RelativePath=$path;Content=$content;Tokens=@(Get-VtLuaTokens -Content $content)
            })
        }
        return @($documents.ToArray())
    }finally{
        $resolvedBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
        $resolvedTarget=[IO.Path]::GetFullPath($temporaryRoot)
        if($resolvedTarget.StartsWith($resolvedBase+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-and
           [IO.Path]::GetFileName($resolvedTarget) -like 'vt-card-source-*' -and
           [IO.Directory]::Exists($resolvedTarget)){
            foreach($file in [IO.Directory]::EnumerateFiles($resolvedTarget,'*',[IO.SearchOption]::AllDirectories)){
                [IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($resolvedTarget,$true)
        }
    }
}

function Get-VtMarkerFromSignature {
    param([string]$Signature)
    $match = [regex]::Match([string]$Signature, '^\[[A-Za-z][A-Za-z0-9_-]*:[A-Za-z0-9_.:-]+\]')
    if ($match.Success) { return $match.Value }
    return $null
}

function Test-VtLiteralReceiptSignature {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and
        $Value -match '^\[[A-Za-z][A-Za-z0-9_-]*:[A-Za-z0-9_.:-]+\]'
}

function Test-VtRawPrintfIsUnshadowed {
    param($Tokens)
    return [VtLiveCardLuaLexerV2]::RawPrintfUnshadowed([VtLiveCardLuaTokenV2[]]@($Tokens))
}

function Get-VtLuaStaticallyDeadSpans {
    param($Tokens)
    # Only constant-false branches are classified. Unknown conditions remain
    # eligible for an immutable route audit; source text inside a branch that
    # can never execute must never manufacture a command, LOAD line, banner,
    # or receipt route.
    $stack=New-Object System.Collections.Generic.List[object]
    $spans=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt @($Tokens).Count;$i++){
        $text=[string]$Tokens[$i].Text
        if($text -eq 'if'){
            $deadStart=$null
            if($i+2 -lt @($Tokens).Count -and
               (Test-VtLuaToken $Tokens[$i+1] 'false' 'Identifier') -and
               (Test-VtLuaToken $Tokens[$i+2] 'then' 'Identifier')){
                $deadStart=$i+3
            }
            $stack.Add([pscustomobject]@{Kind='if';Start=$i;HasDo=$false;DeadStart=$deadStart;DeadEnd=$null})
            continue
        }
        if($text -in @('function','for','while','repeat')){
            $stack.Add([pscustomobject]@{Kind=$text;Start=$i;HasDo=$false;DeadStart=$null;DeadEnd=$null})
            continue
        }
        if($text -eq 'do'){
            if($stack.Count -gt 0 -and [string]$stack[$stack.Count-1].Kind -in @('for','while') -and -not[bool]$stack[$stack.Count-1].HasDo){
                $stack[$stack.Count-1].HasDo=$true
            }else{
                $stack.Add([pscustomobject]@{Kind='do';Start=$i;HasDo=$true;DeadStart=$null;DeadEnd=$null})
            }
            continue
        }
        if($text -in @('else','elseif')){
            if($stack.Count -gt 0 -and [string]$stack[$stack.Count-1].Kind -eq 'if' -and
               $null -ne $stack[$stack.Count-1].DeadStart -and $null -eq $stack[$stack.Count-1].DeadEnd){
                $stack[$stack.Count-1].DeadEnd=$i-1
            }
            continue
        }
        if($text -eq 'until'){
            for($j=$stack.Count-1;$j -ge 0;$j--){
                if([string]$stack[$j].Kind -eq 'repeat'){$stack.RemoveAt($j);break}
            }
            continue
        }
        if($text -eq 'end'){
            for($j=$stack.Count-1;$j -ge 0;$j--){
                if([string]$stack[$j].Kind -eq 'repeat'){continue}
                $entry=$stack[$j];$stack.RemoveAt($j)
                if([string]$entry.Kind -eq 'if' -and $null -ne $entry.DeadStart){
                    $deadEnd=if($null -ne $entry.DeadEnd){[int]$entry.DeadEnd}else{$i-1}
                    if([int]$entry.DeadStart -le $deadEnd){
                        $spans.Add([pscustomobject]@{Start=[int]$entry.DeadStart;End=$deadEnd;Reason='literal-false-branch'})
                    }
                }
                break
            }
        }
    }
    # Invalid/unbalanced Lua is rejected by the parse gate, but authority also
    # fails closed if it sees an unterminated literal-false branch on its own.
    foreach($entry in $stack){
        if([string]$entry.Kind -eq 'if' -and $null -ne $entry.DeadStart){
            $deadEnd=if($null -ne $entry.DeadEnd){[int]$entry.DeadEnd}else{@($Tokens).Count-1}
            if([int]$entry.DeadStart -le $deadEnd){
                $spans.Add([pscustomobject]@{Start=[int]$entry.DeadStart;End=$deadEnd;Reason='literal-false-branch'})
            }
        }
    }
    return @($spans.ToArray())
}

function Test-VtLuaTokenIsStaticallyReachable {
    param([int]$TokenIndex,$DeadSpans)
    foreach($span in @($DeadSpans)){
        if($null -eq $span){continue}
        if([int]$span.Start -le $TokenIndex -and [int]$span.End -ge $TokenIndex){return $false}
    }
    return $true
}

function Test-VtLuaMutatesGlobalPrintf {
    param($Tokens)
    $tokensArray=@($Tokens)
    for($i=0;$i -lt $tokensArray.Count;$i++){
        $name=[string]$tokensArray[$i].Text
        if($name -cne '_G' -and $name -cne '_ENV' -and $name -cne 'rawset' -and
           $name -cne 'setfenv' -and $name -cne 'getfenv'){continue}
        # Direct writes to the global/environment logger.
        if(([string]$tokensArray[$i].Text -in @('_G','_ENV')) -and
           (Test-VtLuaToken $tokensArray[$i+1] '.') -and
           (Test-VtLuaToken $tokensArray[$i+2] 'printf' 'Identifier') -and
           (Test-VtLuaToken $tokensArray[$i+3] '=')){return $true}
        if(([string]$tokensArray[$i].Text -in @('_G','_ENV')) -and
           (Test-VtLuaToken $tokensArray[$i+1] '[') -and
           [string]$tokensArray[$i+2].Kind -eq 'String' -and [string]$tokensArray[$i+2].Value -ceq 'printf' -and
           (Test-VtLuaToken $tokensArray[$i+3] ']') -and (Test-VtLuaToken $tokensArray[$i+4] '=')){return $true}

        # rawset(_G, "printf", ...) and rawset(getfenv(...), "printf", ...)
        # bypass ordinary assignment spelling, so inspect exact call arguments.
        if((Test-VtLuaToken $tokensArray[$i] 'rawset' 'Identifier') -and (Test-VtLuaToken $tokensArray[$i+1] '(')){
            $close=Get-VtLuaMatchingTokenIndex -Tokens $tokensArray -OpenIndex ($i+1)
            if($close -gt $i+1){
                $args=@(Split-VtLuaArguments -Tokens $tokensArray -OpenIndex ($i+1) -CloseIndex $close)
                if($args.Count -ge 2 -and [int]$args[1].Start -eq [int]$args[1].End -and
                   [string]$tokensArray[[int]$args[1].Start].Kind -eq 'String' -and
                   [string]$tokensArray[[int]$args[1].Start].Value -ceq 'printf'){
                    $firstStart=[int]$args[0].Start;$firstEnd=[int]$args[0].End
                    if($firstStart -eq $firstEnd -and [string]$tokensArray[$firstStart].Text -in @('_G','_ENV')){return $true}
                    if((Test-VtLuaToken $tokensArray[$firstStart] 'getfenv' 'Identifier') -and
                       (Test-VtLuaToken $tokensArray[$firstStart+1] '(') -and
                       (Get-VtLuaMatchingTokenIndex -Tokens $tokensArray -OpenIndex ($firstStart+1)) -eq $firstEnd){return $true}
                }
            }
        }

        # setfenv/debug.setfenv/pcall(setfenv, ...) can replace the environment
        # containing printf. The authority does not attempt whole-program
        # alias analysis for such mutations, so their reachable use fails the
        # complete deployed record closed.
        if((Test-VtLuaToken $tokensArray[$i] 'setfenv' 'Identifier') -and
           ((Test-VtLuaToken $tokensArray[$i+1] '(') -or
            ($i -ge 2 -and (Test-VtLuaToken $tokensArray[$i-1] '(') -and (Test-VtLuaToken $tokensArray[$i-2] 'pcall' 'Identifier')))){return $true}

        if((Test-VtLuaToken $tokensArray[$i] 'getfenv' 'Identifier') -and (Test-VtLuaToken $tokensArray[$i+1] '(')){
            $close=Get-VtLuaMatchingTokenIndex -Tokens $tokensArray -OpenIndex ($i+1)
            if($close -lt 0){return $true}
            # getfenv() and getfenv(0) expose the ambient environment table;
            # even an alias write in a different source file would invalidate
            # raw printf trust, so these forms are rejected conservatively.
            if($close -eq $i+2 -or ($close -eq $i+3 -and (Test-VtLuaToken $tokensArray[$i+2] '0'))){return $true}
            if((Test-VtLuaToken $tokensArray[$close+1] '.') -and
               (Test-VtLuaToken $tokensArray[$close+2] 'printf' 'Identifier') -and
               (Test-VtLuaToken $tokensArray[$close+3] '=')){return $true}
            if((Test-VtLuaToken $tokensArray[$close+1] '[') -and
               [string]$tokensArray[$close+2].Kind -eq 'String' -and [string]$tokensArray[$close+2].Value -ceq 'printf' -and
               (Test-VtLuaToken $tokensArray[$close+3] ']') -and (Test-VtLuaToken $tokensArray[$close+4] '=')){return $true}
        }
    }
    return $false
}

function Get-VtDirectLuaCallRoutes {
    param($Document)
    $commands = New-Object System.Collections.Generic.List[object]
    $receipts = New-Object System.Collections.Generic.List[object]
    $loads = New-Object System.Collections.Generic.List[object]
    $banners = New-Object System.Collections.Generic.List[object]
    $deadSpans=if([string]$Document.Content -match '(?i)\bif\s+false\s+then\b'){
        @(Get-VtLuaStaticallyDeadSpans -Tokens @($Document.Tokens))
    }else{@()}
    foreach($candidate in @([VtLiveCardLuaLexerV2]::ScanDirect([VtLiveCardLuaTokenV2[]]@($Document.Tokens)))) {
        if(-not(Test-VtLuaTokenIsStaticallyReachable -TokenIndex ([int]$candidate.TokenIndex) -DeadSpans $deadSpans)){continue}
        switch([string]$candidate.RouteKind) {
            'command' {$commands.Add([pscustomobject]@{Command=[string]$candidate.Command;Source=[string]$Document.RelativePath;Line=[int]$candidate.Line;TokenIndex=[int]$candidate.TokenIndex})}
            'receipt' {$receipts.Add([pscustomobject][ordered]@{Marker=[string]$candidate.Marker;Signature=[string]$candidate.Signature;Source=[string]$Document.RelativePath;Line=[int]$candidate.Line;TokenIndex=[int]$candidate.TokenIndex;Callable=[string]$candidate.Callable;Bound=$false;BoundProof=$null;ActionCommands=@()})}
            'load' {$loads.Add([pscustomobject]@{Marker=[string]$candidate.Marker;Signature=[string]$candidate.Signature;Source=[string]$Document.RelativePath;Line=[int]$candidate.Line;TokenIndex=[int]$candidate.TokenIndex;Callable=[string]$candidate.Callable})}
            'banner' {$banners.Add([pscustomobject]@{Tag=[string]$candidate.Tag;Signature=[string]$candidate.Signature;Source=[string]$Document.RelativePath;Line=[int]$candidate.Line;TokenIndex=[int]$candidate.TokenIndex})}
        }
    }
    return [pscustomobject]@{
        CommandRoutes=@($commands.ToArray()); ReceiptRoutes=@($receipts.ToArray())
        LoadRoutes=@($loads.ToArray()); ExactBannerRoutes=@($banners.ToArray())
    }
}

function Get-VtLuaInjectedAliasDeclarations {
    param($Document)
    $tokens = @($Document.Tokens)
    $declarations = New-Object System.Collections.Generic.List[object]
    for ($i=0; $i + 8 -lt $tokens.Count; $i++) {
        if ((Test-VtLuaToken $tokens[$i] 'local' 'Identifier') -and
            [string]$tokens[$i+1].Kind -eq 'Identifier' -and
            (Test-VtLuaToken $tokens[$i+2] '=') -and
            (Test-VtLuaToken $tokens[$i+3] 'assert' 'Identifier') -and
            (Test-VtLuaToken $tokens[$i+4] '(') -and
            (Test-VtLuaToken $tokens[$i+5] 'deps' 'Identifier') -and
            (Test-VtLuaToken $tokens[$i+6] '.') -and
            [string]$tokens[$i+7].Kind -eq 'Identifier' -and
            [string]$tokens[$i+8].Text -in @(',',')')) {
            $declarations.Add([pscustomobject]@{
                Alias=[string]$tokens[$i+1].Text; Field=[string]$tokens[$i+7].Text
                TokenIndex=$i+1; Source=[string]$Document.RelativePath; Line=[int]$tokens[$i].Line
            })
        }
    }
    return @($declarations.ToArray())
}

function Get-VtLuaModulePath {
    param([string]$ModDir, [string]$RelativePath)
    $prefix = ($ModDir.TrimEnd([char[]]'\/') -replace '\\','/') + '/'
    $normal = $RelativePath -replace '\\','/'
    if (-not $normal.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return ($normal.Substring($prefix.Length) -replace '(?i)\.lua$','')
}

function Get-VtInstallPrintfBindings {
    param($Documents, [string]$ModulePath)
    $bindings = New-Object System.Collections.Generic.List[object]
    foreach ($document in @($Documents)) {
        if([string]$document.Content -notmatch '(?i)\bmod\s*:\s*dofile\b'){continue}
        $tokens = @($document.Tokens)
        $deadSpans=if([string]$document.Content -match '(?i)\bif\s+false\s+then\b'){
            @(Get-VtLuaStaticallyDeadSpans -Tokens $tokens)
        }else{@()}
        $documentRawPrintfTrusted=Test-VtRawPrintfIsUnshadowed -Tokens $tokens
        for ($i=0; $i + 10 -lt $tokens.Count; $i++) {
            if (-not ((Test-VtLuaToken $tokens[$i] 'mod' 'Identifier') -and
                (Test-VtLuaToken $tokens[$i+1] ':') -and
                (Test-VtLuaToken $tokens[$i+2] 'dofile' 'Identifier') -and
                (Test-VtLuaToken $tokens[$i+3] '(') -and
                [string]$tokens[$i+4].Kind -eq 'String' -and
                (Test-VtLuaToken $tokens[$i+5] ')') -and
                (Test-VtLuaToken $tokens[$i+6] '.') -and
                (Test-VtLuaToken $tokens[$i+7] 'install' 'Identifier') -and
                (Test-VtLuaToken $tokens[$i+8] '('))) { continue }
            if(-not(Test-VtLuaTokenIsStaticallyReachable -TokenIndex $i -DeadSpans $deadSpans)){continue}
            $boundModulePath=[string]$tokens[$i+4].Value
            if($ModulePath -and $boundModulePath -cne $ModulePath){continue}
            $close = Get-VtLuaMatchingTokenIndex -Tokens $tokens -OpenIndex ($i+8)
            if ($close -lt 0) { continue }
            $args = @(Split-VtLuaArguments -Tokens $tokens -OpenIndex ($i+8) -CloseIndex $close)
            if ($args.Count -ne 2) { continue }
            $tableStart = [int]$args[1].Start
            $tableEnd = [int]$args[1].End
            if ($tableStart -gt $tableEnd -or -not (Test-VtLuaToken $tokens[$tableStart] '{') -or
                (Get-VtLuaMatchingTokenIndex -Tokens $tokens -OpenIndex $tableStart) -ne $tableEnd) { continue }
            $depth = 0
            for ($j=$tableStart+1; $j -lt $tableEnd; $j++) {
                $text=[string]$tokens[$j].Text
                if ($text -in @('(','{','[')) { $depth++; continue }
                if ($text -in @(')','}',']')) { $depth--; continue }
                if ($depth -eq 0 -and [string]$tokens[$j].Kind -eq 'Identifier' -and
                    $j+2 -lt $tableEnd -and (Test-VtLuaToken $tokens[$j+1] '=')) {
                    $rhs = $tokens[$j+2]
                    $rhsEnd = $j+2
                    while ($rhsEnd+1 -lt $tableEnd -and [string]$tokens[$rhsEnd+1].Text -ne ',') { $rhsEnd++ }
                    $bindings.Add([pscustomobject]@{
                        ModulePath=$boundModulePath
                        Field=[string]$tokens[$j].Text
                        IsRawPrintf=($rhsEnd -eq $j+2 -and (Test-VtLuaToken $rhs 'printf' 'Identifier') -and $documentRawPrintfTrusted)
                        Source=[string]$document.RelativePath; Line=[int]$tokens[$j].Line
                    })
                }
            }
        }
    }
    return @($bindings.ToArray())
}

function Test-VtInjectedAliasIsUnambiguous {
    param($Document, $Declaration)
    $tokens = @($Document.Tokens)
    $alias = [string]$Declaration.Alias
    $declarationIndex = [int]$Declaration.TokenIndex
    for ($i=0; $i -lt $tokens.Count; $i++) {
        if ([string]$tokens[$i].Kind -ne 'Identifier' -or [string]$tokens[$i].Text -cne $alias) { continue }
        if ($i -eq $declarationIndex) { continue }
        if ($i -lt $declarationIndex) { return $false }
        # The only permitted uses are direct calls: alias(<literal>, ...).
        # Any assignment, second local, parameter shadow, member access, return,
        # or helper forwarding makes the proof ambiguous and fails closed.
        if ($i+1 -ge $tokens.Count -or -not (Test-VtLuaToken $tokens[$i+1] '(')) { return $false }
    }
    return $true
}

function Get-VtInjectedReceiptRoutes {
    param([string]$ModDir, $Documents)
    $routes = New-Object System.Collections.Generic.List[object]
    # Index every literal install table once. Re-scanning the whole mod for
    # every dependency declaration made large deployed builds quadratic.
    $allBindings=@(Get-VtInstallPrintfBindings -Documents $Documents)
    foreach ($document in @($Documents)) {
        if([string]$document.Content -notmatch '(?i)deps\.'){continue}
        $deadSpans=if([string]$document.Content -match '(?i)\bif\s+false\s+then\b'){
            @(Get-VtLuaStaticallyDeadSpans -Tokens @($document.Tokens))
        }else{@()}
        $declarations = @(Get-VtLuaInjectedAliasDeclarations -Document $document)
        foreach ($declaration in $declarations) {
            if(-not(Test-VtLuaTokenIsStaticallyReachable -TokenIndex ([int]$declaration.TokenIndex) -DeadSpans $deadSpans)){continue}
            if (@($declarations | Where-Object { [string]$_.Alias -ceq [string]$declaration.Alias }).Count -ne 1) { continue }
            if (-not (Test-VtInjectedAliasIsUnambiguous -Document $document -Declaration $declaration)) { continue }
            $modulePath = Get-VtLuaModulePath -ModDir $ModDir -RelativePath ([string]$document.RelativePath)
            if (-not $modulePath) { continue }
            $bindings = @($allBindings | Where-Object {
                [string]$_.ModulePath -ceq $modulePath -and [string]$_.Field -ceq [string]$declaration.Field
            })
            if ($bindings.Count -ne 1 -or -not [bool]$bindings[0].IsRawPrintf) { continue }
            $tokens = @($document.Tokens)
            for ($i=0; $i+2 -lt $tokens.Count; $i++) {
                if ((Test-VtLuaToken $tokens[$i] ([string]$declaration.Alias) 'Identifier') -and
                    (Test-VtLuaToken $tokens[$i+1] '(') -and
                    [string]$tokens[$i+2].Kind -eq 'String') {
                    if(-not(Test-VtLuaTokenIsStaticallyReachable -TokenIndex $i -DeadSpans $deadSpans)){continue}
                    $signature=[string]$tokens[$i+2].Value
                    if (Test-VtLiteralReceiptSignature $signature) {
                        $marker=Get-VtMarkerFromSignature $signature
                        if ($marker -notmatch '(?i):LOAD\]$') {
                            $routes.Add([pscustomobject][ordered]@{
                                Marker=$marker; Signature=$signature; Source=[string]$document.RelativePath
                                Line=[int]$tokens[$i].Line; TokenIndex=$i; Callable=('injected:' + [string]$declaration.Field)
                                Bound=$false; BoundProof=$null; ActionCommands=@()
                            })
                        }
                    }
                }
            }
        }
    }
    return @($routes.ToArray())
}

function Get-VtMenuSurfaces {
    param($Documents)
    # Menu discovery is deliberately token-based. Literal values are examined
    # only as values of recognized setting/text and localization/en fields.
    $widgetKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $localizations = @{}
    foreach ($document in @($Documents)) {
        $tokens=@($document.Tokens)
        if ([string]$document.RelativePath -match '(?i)_data\.lua$') {
            for($i=0;$i+2 -lt $tokens.Count;$i++) {
                if ([string]$tokens[$i].Text -in @('setting_id','text') -and
                    (Test-VtLuaToken $tokens[$i+1] '=') -and [string]$tokens[$i+2].Kind -eq 'String') {
                    $null=$widgetKeys.Add([string]$tokens[$i+2].Value)
                }
            }
        }
        if ([string]$document.RelativePath -match '(?i)_localization\.lua$') {
            for($i=0;$i+5 -lt $tokens.Count;$i++) {
                if ([string]$tokens[$i].Kind -eq 'Identifier' -and (Test-VtLuaToken $tokens[$i+1] '=') -and
                    (Test-VtLuaToken $tokens[$i+2] '{') -and (Test-VtLuaToken $tokens[$i+3] 'en' 'Identifier') -and
                    (Test-VtLuaToken $tokens[$i+4] '=') -and [string]$tokens[$i+5].Kind -eq 'String') {
                    $localizations[[string]$tokens[$i].Text]=[string]$tokens[$i+5].Value
                }
            }
        }
    }
    $surfaces=New-Object System.Collections.Generic.List[string]
    foreach($key in $widgetKeys) {
        $surface=if($localizations.ContainsKey($key)){[string]$localizations[$key]}else{[string]$key}
        $surface=($surface -replace '\s+',' ').Trim()
        if($surface -match '(?i)\b(?:Diagnostic|Diagnostics|Probe|Audit|Regression Test)\b'){$surfaces.Add($surface)}
    }
    return @($surfaces.ToArray() | Sort-Object -Unique)
}

function Get-VtLoadTimeReachableLuaPaths {
    param([string]$ModDir,$Documents)
    $byPath=@{}
    foreach($document in @($Documents)){$byPath[[string]$document.RelativePath]=$document}
    $reachable=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $queue=New-Object System.Collections.Generic.Queue[string]
    $prefix=($ModDir.TrimEnd([char[]]'\/').Replace('\','/'))+'/scripts/mods/'

    # VMF evaluates the main, data, and localization entry documents. Every
    # other Lua document must be reached through a literal same-mod
    # dofile/require edge in a reachable document. Merely existing in the
    # deployed tree is not executable proof.
    foreach($path in @($byPath.Keys)){
        $normal=[string]$path
        if(-not$normal.StartsWith($prefix,[StringComparison]::Ordinal)){continue}
        $rest=$normal.Substring($prefix.Length)
        $parts=@($rest -split '/')
        if($parts.Count -ne 2){continue}
        $module=[string]$parts[0];$file=[IO.Path]::GetFileNameWithoutExtension([string]$parts[1])
        if($file -ceq $module -or $file -ceq ($module+'_data') -or $file -ceq ($module+'_localization')){
            if($reachable.Add($normal)){$queue.Enqueue($normal)}
        }
    }
    while($queue.Count -gt 0){
        $path=$queue.Dequeue();$document=$byPath[$path];$tokens=@($document.Tokens)
        if([string]$document.Content -notmatch '(?i)\b(?:dofile|require)\b'){continue}
        $dead=if([string]$document.Content -match '(?i)\bif\s+false\s+then\b'){
            @(Get-VtLuaStaticallyDeadSpans -Tokens $tokens)
        }else{@()}
        foreach($load in @([VtLiveCardLuaLexerV2]::ScanDocumentLoads([VtLiveCardLuaTokenV2[]]$tokens))){
            if(-not(Test-VtLuaTokenIsStaticallyReachable -TokenIndex ([int]$load.TokenIndex) -DeadSpans $dead)){continue}
            $modulePath=([string]$load.Signature).Replace('\','/').TrimStart('/')
            if(-not$modulePath.StartsWith('scripts/mods/',[StringComparison]::Ordinal)){continue}
            $target=($ModDir.TrimEnd([char[]]'\/').Replace('\','/'))+'/'+$modulePath
            if(-not$target.EndsWith('.lua',[StringComparison]::OrdinalIgnoreCase)){$target+='.lua'}
            if($byPath.ContainsKey($target)-and$reachable.Add($target)){$queue.Enqueue($target)}
        }
    }
    return ,$reachable
}

function Get-VtLuaFunctionSpans {
    param($Tokens)
    return @([VtLiveCardLuaLexerV2]::ScanFunctionSpans([VtLiveCardLuaTokenV2[]]@($Tokens)))
}

function Get-VtLuaLoopSpans {
    param($Tokens)
    return @([VtLiveCardLuaLexerV2]::ScanLoopSpans([VtLiveCardLuaTokenV2[]]@($Tokens)))
}

function Get-VtLuaCommandCallbackSpans {
    param($Tokens,$FunctionSpans)
    return @([VtLiveCardLuaLexerV2]::ScanCommandCallbacks(
        [VtLiveCardLuaTokenV2[]]@($Tokens),[VtLiveCardLuaSpanV2[]]@($FunctionSpans)))
}

function Test-VtTokenWindowContains {
    param($Tokens,[int]$Start,[int]$End,[string[]]$Sequence)
    if($Sequence.Count -eq 0){return $false}
    $last=[Math]::Min($End,@($Tokens).Count-1)-$Sequence.Count+1
    for($i=[Math]::Max(0,$Start);$i -le $last;$i++){
        $ok=$true
        for($j=0;$j -lt $Sequence.Count;$j++){
            if([string]$Tokens[$i+$j].Text -cne [string]$Sequence[$j]){$ok=$false;break}
        }
        if($ok){return $true}
    }
    return $false
}

function Get-VtStructuralReceiptBound {
    param($Document,$Route,$FunctionSpans,$CallbackSpans,$LoopSpans)
    $tokens=@($Document.Tokens);$at=[int]$Route.TokenIndex
    if(@($LoopSpans|Where-Object{$_.Start -lt $at -and $_.End -gt $at}).Count -gt 0){return $null}
    $functions=@($FunctionSpans)
    $owner=@($functions|Where-Object{$_.Start -lt $at -and $_.End -gt $at}|Sort-Object{[int]$_.End-[int]$_.Start}|Select-Object -First 1)
    if($owner.Count -eq 0){
        # Lua goto can express a loop without any while/for/repeat token. Do
        # not certify a framework-main emitter when the same document carries
        # an unanalyzed control-transfer edge.
        if([VtLiveCardLuaLexerV2]::ContainsIdentifier([VtLiveCardLuaTokenV2[]]$tokens,0,$tokens.Count-1,'goto')){return $null}
        # Only the framework-owned main module has a one-evaluation contract.
        # A helper's top-level code can be reached by a repeatable mod:dofile
        # call, so it needs an immutable route override like any other emitter.
        $normal=([string]$Document.RelativePath -replace '\\','/')
        $segments=@($normal -split '/')
        $file=[IO.Path]::GetFileNameWithoutExtension($normal)
        $parent=if($segments.Count -ge 2){[string]$segments[$segments.Count-2]}else{''}
        if($file -ceq $parent){return 'framework-main-module-evaluation'}
        return $null
    }
    $ownerStart=[int]$owner[0].Start;$ownerEnd=[int]$owner[0].End
    if([VtLiveCardLuaLexerV2]::ContainsIdentifier([VtLiveCardLuaTokenV2[]]$tokens,$ownerStart,$ownerEnd,'goto')){return $null}
    $callbacks=@($CallbackSpans)
    if(@($callbacks|Where-Object{$_.Start -eq $owner[0].Start -and $_.End -eq $owner[0].End}).Count -gt 0){
        return 'explicit-command-callback'
    }
    $start=[int]$owner[0].Start;$end=[int]$owner[0].End

    # Cross-statement counter/latch proofs are intentionally not inferred.
    # Complex control flow is admitted only through an immutable-tree,
    # exact-token override; a guard elsewhere in the same function must never
    # authorize an unrelated emitter.
    return $null
}

function Get-VtExceptionSourcePaths {
    param($Exceptions,[string]$ModId)
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $groups=@()
    foreach($override in @($Exceptions.ReceiptRouteOverrides)){
        if([string]$override.ModId -ceq $ModId){$groups += [pscustomobject]@{Override=$override;Default=[string]$override.Source}}
    }
    foreach($override in @($Exceptions.ReceiptDiscoveryOverrides)){
        if([string]$override.ModId -ceq $ModId){$groups += [pscustomobject]@{Override=$override;Default=[string]$override.Source}}
    }
    foreach($override in @($Exceptions.ReceiptFamilyOverrides)){
        $modIds=if($override.ModIds){@($override.ModIds)}else{@($override.ModId)}
        if($modIds -ccontains $ModId){
            $default=if($override.SourcesByMod -and $override.SourcesByMod.ContainsKey($ModId)){[string]$override.SourcesByMod[$ModId]}else{[string]$override.Source}
            $groups += [pscustomobject]@{Override=$override;Default=$default}
        }
    }
    foreach($group in $groups){
        $default=([string]$group.Default -replace '\\','/').Trim()
        if($default){$null=$paths.Add($default)}
        foreach($anchor in @($group.Override.EmitterAnchors)+@($group.Override.GuardAnchors)){
            $source=Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource $default
            if($source){$null=$paths.Add($source)}
        }
    }
    return @($paths)
}

function Set-VtStructuralReceiptBounds {
    param($Documents,$Routes)
    $byPath=@{};foreach($document in @($Documents)){$byPath[[string]$document.RelativePath]=$document}
    foreach($path in @($Routes.Source|Sort-Object -Unique)){
        if(-not$byPath.ContainsKey([string]$path)){continue}
        $document=$byPath[[string]$path];$tokens=@($document.Tokens)
        $functions=@(Get-VtLuaFunctionSpans -Tokens $tokens)
        $callbacks=@(Get-VtLuaCommandCallbackSpans -Tokens $tokens -FunctionSpans $functions)
        $loops=@(Get-VtLuaLoopSpans -Tokens $tokens)
        $proofByOwner=@{}
        $commandsByOwner=@{}
        foreach($route in @($Routes|Where-Object{[string]$_.Source -ceq [string]$path})){
            $at=[int]$route.TokenIndex
            $owner=@($functions|Where-Object{$_.Start -lt $at -and $_.End -gt $at}|Sort-Object{[int]$_.End-[int]$_.Start}|Select-Object -First 1)
            $ownerKey=if($owner.Count -eq 0){'top'}else{"$([int]$owner[0].Start):$([int]$owner[0].End)"}
            if(-not$proofByOwner.ContainsKey($ownerKey)){
                $calculated=Get-VtStructuralReceiptBound -Document $document -Route $route -FunctionSpans $functions -CallbackSpans $callbacks -LoopSpans $loops
                $proofByOwner[$ownerKey]=if($calculated){$calculated}else{''}
                $ownerCallbacks=if($owner.Count -eq 1){@($callbacks|Where-Object{
                    [int]$_.Start -eq [int]$owner[0].Start -and [int]$_.End -eq [int]$owner[0].End
                })}else{@()}
                $commandsByOwner[$ownerKey]=@($ownerCallbacks.Command|Where-Object{$_}|Sort-Object -Unique)
            }
            $proof=$proofByOwner[$ownerKey]
            if(@($commandsByOwner[$ownerKey]).Count -gt 0){
                $route|Add-Member -NotePropertyName ActionCommands -NotePropertyValue @($commandsByOwner[$ownerKey]) -Force
            }
            if($proof){
                $route.Bound=$true;$route.BoundProof=$proof
            }
        }
    }
}

function Get-VtReceiptAnchorTokens {
    param($Anchor)
    if($Anchor -is [Collections.IDictionary]){return @($Anchor['Tokens'])}
    if($Anchor -is [string]){
        return @(Get-VtLuaTokens -Content ([string]$Anchor) | ForEach-Object {
            if([string]$_.Kind -ceq 'String'){'String:'+ [string]$_.Value}else{[string]$_.Text}
        })
    }
    if($Anchor -is [Array]){return @($Anchor)}
    return @()
}

function Get-VtReceiptAnchorSource {
    param($Anchor,[string]$DefaultSource)
    if($Anchor -is [Collections.IDictionary] -and $Anchor.Contains('Source')){
        $source=([string]$Anchor['Source'] -replace '\\','/').Trim()
        if($source){return $source}
    }
    return ([string]$DefaultSource -replace '\\','/').Trim()
}

function Test-VtTokenAnchor {
    param($Tokens,$Anchor)
    $specs=@(Get-VtReceiptAnchorTokens -Anchor $Anchor)
    if($specs.Count -eq 0){return $false}
    return [VtLiveCardLuaLexerV2]::ContainsAnchor(
        [VtLiveCardLuaTokenV2[]]@($Tokens),[string[]]$specs)
}

function Get-VtReceiptOverrideActionCommands {
    param($Override,$CommandRoutes,[string]$Context)
    $actions=if($Override.ContainsKey('ActionCommands')){@($Override.ActionCommands)}else{@()}
    $actions=@($actions|ForEach-Object{([string]$_).Trim()}|Where-Object{$_})
    if(@($actions|Sort-Object -Unique).Count -ne $actions.Count -or
       @($actions|Where-Object{$_ -cnotmatch '^/[a-z][a-z0-9_:-]*$'}).Count -gt 0){
        throw "Malformed $Context ActionCommands."
    }
    $known=@($CommandRoutes.Command|Sort-Object -Unique)
    foreach($action in $actions){
        if($known -cnotcontains $action){throw "$Context names unregistered action command '$action'."}
    }
    return @($actions)
}

function Set-VtReceiptOverrideBounds {
    param([string]$ModId,[string]$ModTree,$Documents,$Routes,$CommandRoutes,$Exceptions)
    $byPath=@{};foreach($document in @($Documents)){$byPath[[string]$document.RelativePath]=$document}
    $keys=@{}
    foreach($override in @($Exceptions.ReceiptRouteOverrides|Where-Object{[string]$_.ModId -ceq $ModId})){
        $source=([string]$override.Source -replace '\\','/').Trim()
        $marker=[string]$override.Marker;$signature=[string]$override.Signature
        $bound=[string]$override.Bound
        $actionCommands=@(Get-VtReceiptOverrideActionCommands -Override $override -CommandRoutes $CommandRoutes -Context "Receipt-route override '$ModId' '$signature'")
        $pinnedTrees=if($override.ContainsKey('ModTrees')){@($override.ModTrees)}else{@([string]$override.ModTree)}
        $key="$ModId`n$source`n$signature"
        if($keys.ContainsKey($key)){throw "Duplicate receipt-route override for '$ModId' '$source' '$signature'."}
        $keys[$key]=$true
        if($pinnedTrees.Count -eq 0 -or @($pinnedTrees|Where-Object{[string]$_ -notmatch '^[0-9a-f]{40}$'}).Count -gt 0 -or
            @($pinnedTrees|Sort-Object -Unique).Count -ne $pinnedTrees.Count -or $pinnedTrees -cnotcontains $ModTree){
            throw "Receipt-route override tree drift for '$ModId' '$signature': pinned=$($pinnedTrees -join ',') deployed=$ModTree."
        }
        if(-not$byPath.ContainsKey($source)){throw "Receipt-route override source missing for '$ModId': $source."}
        if([string]::IsNullOrWhiteSpace($bound) -or -not(Test-VtLiteralReceiptSignature $signature) -or
            (Get-VtMarkerFromSignature $signature) -cne $marker -or @($override.EmitterAnchors).Count -eq 0 -or @($override.GuardAnchors).Count -eq 0){
            throw "Malformed receipt-route override for '$ModId' '$source' '$signature'."
        }
        foreach($anchor in @($override.EmitterAnchors)){
            $anchorSource=Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource $source
            if(-not$byPath.ContainsKey($anchorSource) -or -not(Test-VtTokenAnchor -Tokens @($byPath[$anchorSource].Tokens) -Anchor $anchor)){
                throw "Receipt-route override emitter anchor drift for '$ModId' '$source' '$signature'."
            }
        }
        foreach($anchor in @($override.GuardAnchors)){
            $anchorSource=Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource $source
            if(-not$byPath.ContainsKey($anchorSource) -or -not(Test-VtTokenAnchor -Tokens @($byPath[$anchorSource].Tokens) -Anchor $anchor)){
                throw "Receipt-route override guard anchor drift for '$ModId' '$source' '$signature'."
            }
        }
        $matches=@($Routes|Where-Object{[string]$_.Source -ceq $source -and [string]$_.Signature -ceq $signature})
        if($matches.Count -eq 0){
            if(-not[bool]$override.AddRoute){throw "Receipt-route override no longer resolves an indexed route for '$ModId' '$signature'."}
            $Routes.Add([pscustomobject][ordered]@{
                Marker=$marker;Signature=$signature;Source=$source;Line=0;TokenIndex=-1
                Callable='audited-complex-route';Bound=$true;BoundProof=('override:'+$bound);ActionCommands=@($actionCommands)
            })
        }else{
            foreach($route in $matches){
                $route.Bound=$true;$route.BoundProof=('override:'+$bound)
                if($actionCommands.Count -gt 0){$route|Add-Member -NotePropertyName ActionCommands -NotePropertyValue @($actionCommands) -Force}
            }
        }
    }
}

function Test-VtReceiptOverrideDefinition {
    param($Override,[string]$Context)
    $marker=[string]$Override.Marker;$signature=[string]$Override.Signature
    if([string]::IsNullOrWhiteSpace([string]$Override.Bound) -or
       -not(Test-VtLiteralReceiptSignature $signature) -or
       (Get-VtMarkerFromSignature $signature) -cne $marker -or
       @($Override.EmitterAnchors).Count -eq 0 -or @($Override.GuardAnchors).Count -eq 0){
        throw "Malformed $Context '$marker' '$signature'."
    }
}

function Test-VtDocumentAnchors {
    param($ByPath,$Override,[string]$DefaultSource,[string]$Context)
    foreach($anchor in @($Override.EmitterAnchors)+@($Override.GuardAnchors)){
        $anchorSource=Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource $DefaultSource
        if(-not$ByPath.ContainsKey($anchorSource) -or -not(Test-VtTokenAnchor -Tokens @($ByPath[$anchorSource].Tokens) -Anchor $anchor)){
            throw "$Context anchor drift for '$($Override.Marker)' '$DefaultSource' '$($Override.Signature)'."
        }
    }
}

function Set-VtReceiptFamilyOverrides {
    param($Records,$DocumentsByMod,$Exceptions)
    $familyOverrides=if($Exceptions.ContainsKey('ReceiptFamilyOverrides')){@($Exceptions.ReceiptFamilyOverrides)}else{@()}
    $seen=@{}
    foreach($override in $familyOverrides){
        Test-VtReceiptOverrideDefinition -Override $override -Context 'receipt-family override'
        $modIds=if($override.ModIds){@($override.ModIds)}else{@($override.ModId)}
        $modIds=@($modIds|ForEach-Object{([string]$_).Trim()}|Where-Object{$_}|Sort-Object -Unique)
        $sourcesByMod=$override.SourcesByMod
        if($modIds.Count -eq 0 -or -not$sourcesByMod){throw "Malformed receipt-family override '$($override.Marker)'."}
        foreach($modId in $modIds){
            $record=@($Records|Where-Object{[string]$_.ModId -ceq $modId})
            if($record.Count -ne 1){throw "Receipt-family override '$($override.Marker)' cannot resolve ModId '$modId'."}
            $pinnedTrees=if($override.ModTrees -and $override.ModTrees.ContainsKey($modId)){@($override.ModTrees[$modId])}else{@()}
            if($pinnedTrees.Count -eq 0 -or @($pinnedTrees|Where-Object{[string]$_ -notmatch '^[0-9a-f]{40}$'}).Count -gt 0 -or
               @($pinnedTrees|Sort-Object -Unique).Count -ne $pinnedTrees.Count -or $pinnedTrees -cnotcontains [string]$record[0].ModTree){
                throw "Receipt-family override '$($override.Marker)' immutable-tree drift for '$modId': pinned=$($pinnedTrees -join ',') deployed=$($record[0].ModTree)."
            }
            $source=if($sourcesByMod.ContainsKey($modId)){([string]$sourcesByMod[$modId] -replace '\\','/').Trim()}else{$null}
            $key="$modId`n$source`n$($override.Signature)"
            if($seen.ContainsKey($key)){throw "Duplicate receipt-family override '$key'."};$seen[$key]=$true
            $documents=@($DocumentsByMod[$modId]);$byPath=@{};foreach($document in $documents){$byPath[[string]$document.RelativePath]=$document}
            if(-not$source -or -not$byPath.ContainsKey($source)){throw "Receipt-family override source missing for '$modId': $source."}
            Test-VtDocumentAnchors -ByPath $byPath -Override $override -DefaultSource $source -Context 'Receipt-family override'
            $indexed=@($record[0].ReceiptRoutes|Where-Object{
                [string]$_.Source -ceq $source -and [string]$_.Signature -ceq [string]$override.Signature
            })
            if($indexed.Count -gt 0){
                foreach($route in $indexed){$route.Bound=$true;$route.BoundProof=('override:'+ [string]$override.Bound)}
            }else{
                $record[0].ReceiptRoutes += [pscustomobject][ordered]@{
                    Marker=[string]$override.Marker;Signature=[string]$override.Signature;Source=$source;Line=0;TokenIndex=-1
                    Callable='audited-complex-family-route';Bound=$true;BoundProof=('override:'+ [string]$override.Bound);ActionCommands=@()
                }
            }
        }
    }
}

function Set-VtReceiptDiscoveryOverrides {
    param($Records,$DocumentsByMod,$Exceptions)
    $discoveries=if($Exceptions.ContainsKey('ReceiptDiscoveryOverrides')){@($Exceptions.ReceiptDiscoveryOverrides)}else{@()}
    $seen=@{}
    foreach($override in $discoveries){
        $modId=[string]$override.ModId;$source=([string]$override.Source -replace '\\','/').Trim()
        $marker=[string]$override.Marker;$signature=[string]$override.Signature;$tree=[string]$override.ModTree
        $key="$modId`n$source`n$signature";if($seen.ContainsKey($key)){throw "Duplicate receipt discovery '$key'."};$seen[$key]=$true
        if($tree -notmatch '^[0-9a-f]{40}$' -or -not(Test-VtLiteralReceiptSignature $signature) -or
           (Get-VtMarkerFromSignature $signature) -cne $marker -or @($override.EmitterAnchors).Count -eq 0){
            throw "Malformed receipt discovery '$marker' '$signature'."
        }
        $record=@($Records|Where-Object{[string]$_.ModId -ceq $modId});if($record.Count -ne 1){throw "Receipt discovery '$marker' cannot resolve ModId '$modId'."}
        if([string]$record[0].ModTree -cne $tree){throw "Receipt discovery '$marker' immutable-tree drift for '$modId'."}
        $documents=@($DocumentsByMod[$modId]);$byPath=@{};foreach($document in $documents){$byPath[[string]$document.RelativePath]=$document}
        if(-not$byPath.ContainsKey($source)){throw "Receipt discovery source missing for '$modId': $source."}
        foreach($anchor in @($override.EmitterAnchors)){
            $anchorSource=Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource $source
            if(-not$byPath.ContainsKey($anchorSource) -or -not(Test-VtTokenAnchor @($byPath[$anchorSource].Tokens) $anchor)){
                throw "Receipt discovery emitter anchor drift for '$modId' '$signature'."
            }
        }
        $indexed=@($record[0].ReceiptRoutes|Where-Object{[string]$_.Source -ceq $source -and [string]$_.Signature -ceq $signature})
        if($indexed.Count -eq 0){
            $record[0].ReceiptRoutes += [pscustomobject][ordered]@{
                Marker=$marker;Signature=$signature;Source=$source;Line=0;TokenIndex=-1
                Callable='audited-complex-unbounded-route';Bound=$false;BoundProof=$null;ActionCommands=@()
            }
        }
    }
}

function Test-VtAuthorityRetryableGitHubError([string]$Message) {
    return -not[string]::IsNullOrWhiteSpace($Message) -and [bool]($Message -match
        '(?is)(tls:|x509:|connection (?:reset|refused)|unexpected EOF|i/o timeout|context deadline exceeded|HTTP\s+(?:408|429|5\d\d)|status code\s+(?:408|429|5\d\d)|(?:502|503|504)\s+(?:Bad Gateway|Service Unavailable|Gateway Timeout))')
}

function Invoke-VtAuthorityGhRead {
    param([string[]]$Arguments,[string]$Description)
    $raw='';$exitCode=0
    for($attempt=1;$attempt -le 4;$attempt++){
        $oldPreference=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$raw=& gh @Arguments 2>&1|Out-String;$exitCode=$LASTEXITCODE}
        finally{$ErrorActionPreference=$oldPreference}
        if($exitCode -eq 0){return $raw}
        $delay=if($attempt -eq 1){2}elseif($attempt -eq 2){5}elseif($attempt -eq 3){10}else{0}
        if($delay -le 0 -or -not(Test-VtAuthorityRetryableGitHubError $raw)){
            throw "$Description failed (exit $exitCode, attempt $attempt/4): $($raw.Trim())"
        }
        Write-Warning "$Description hit a transient GitHub transport failure (attempt $attempt/4); retrying in $delay second(s)."
        Start-Sleep -Seconds $delay
    }
    throw "$Description failed after four attempts: $($raw.Trim())"
}

function Get-VtCardDeploymentManifest {
    [CmdletBinding()]
    param(
        [string]$Repository = 'Ensrick/vermintide-2-tweaker',
        [string]$ManifestJsonPath
    )
    if ($ManifestJsonPath) {
        if(-not(Test-Path -LiteralPath $ManifestJsonPath -PathType Leaf)){
            throw "Deployment manifest fixture not found: $ManifestJsonPath"
        }
        return (Get-Content -LiteralPath $ManifestJsonPath -Raw | ConvertFrom-Json)
    }
    if($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){throw "Repository must be OWNER/NAME, got '$Repository'."}
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is required to load the authoritative deployment manifest.' }
    $releaseRaw = Invoke-VtAuthorityGhRead -Arguments @('api',"repos/$Repository/releases/latest") -Description 'Unable to read latest GitHub release'
    $release = $releaseRaw | ConvertFrom-Json
    $assets = @($release.assets)
    $manifestAssets = @($assets | Where-Object { [string]$_.name -eq 'manifest.json' })
    if ($manifestAssets.Count -ne 1) { throw "Latest release '$($release.tag_name)' must contain exactly one manifest.json asset." }
    $manifestRaw = Invoke-VtAuthorityGhRead -Arguments @('api',"repos/$Repository/releases/assets/$($manifestAssets[0].id)",'-H','Accept: application/octet-stream') -Description 'Unable to download latest release manifest.json'
    $manifest = $manifestRaw | ConvertFrom-Json
    if ([string]$manifest.release_tag -cne [string]$release.tag_name) {
        throw "Release tag mismatch: latest=$($release.tag_name), manifest=$($manifest.release_tag)."
    }
    $manifest | Add-Member -NotePropertyName _authority_release_tag -NotePropertyValue ([string]$release.tag_name) -Force
    return $manifest
}

function Get-VtCardSourceAuthority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)]$DeploymentManifest
    )
    if ([int]$DeploymentManifest.manifest_schema -lt 2) { throw 'Deployment manifest schema 2 or newer is required.' }
    if ($DeploymentManifest.PSObject.Properties['_authority_release_tag'] -and
        [string]$DeploymentManifest._authority_release_tag -cne [string]$DeploymentManifest.release_tag) {
        throw "Release tag mismatch: fetched=$($DeploymentManifest._authority_release_tag), manifest=$($DeploymentManifest.release_tag)."
    }
    if ([string]::IsNullOrWhiteSpace([string]$DeploymentManifest.release_tag)) { throw 'Deployment manifest has no release_tag.' }
    $inventoryPath=Join-Path $RepoRoot 'tools/mod-inventory.psd1'
    $exceptionsPath=Join-Path $RepoRoot 'tools/verify/live_test_contract_exceptions.psd1'
    if(-not(Test-Path -LiteralPath $inventoryPath)){throw "Canonical mod inventory is missing: $inventoryPath"}
    if(-not(Test-Path -LiteralPath $exceptionsPath)){throw "Live-test card authority exceptions are missing: $exceptionsPath"}
    $inventory=Import-PowerShellDataFile -LiteralPath $inventoryPath
    $exceptions=Import-PowerShellDataFile -LiteralPath $exceptionsPath

    $inventoryById=@{}; $inventoryByWorkshop=@{}
    foreach($entry in @($inventory.Mods)){
        $id=[string]$entry.ModId; $item=[string]$entry.WorkshopId
        if([string]::IsNullOrWhiteSpace($id)-or$inventoryById.ContainsKey($id)){throw "Canonical mod inventory contains a missing or duplicate ModId '$id'."}
        if([string]::IsNullOrWhiteSpace($item)-or$inventoryByWorkshop.ContainsKey($item)){throw "Canonical mod inventory contains a missing or duplicate WorkshopId '$item'."}
        $inventoryById[$id]=$entry; $inventoryByWorkshop[$item]=$entry
    }
    $deployedById=@{}; $deployedByWorkshop=@{}
    foreach($row in @($DeploymentManifest.mods)){
        $id=[string]$row.mod_id; $item=[string]$row.workshop_id
        if([string]::IsNullOrWhiteSpace($id)-or$deployedById.ContainsKey($id)){throw "Deployment manifest contains a missing or duplicate mod_id '$id'."}
        if([string]::IsNullOrWhiteSpace($item)-or$deployedByWorkshop.ContainsKey($item)){throw "Deployment manifest contains a missing or duplicate workshop_id '$item'."}
        if(-not$inventoryById.ContainsKey($id)){throw "Deployment manifest contains non-inventory mod '$id'."}
        $deployedById[$id]=$row; $deployedByWorkshop[$item]=$row
    }
    foreach($id in @($inventoryById.Keys)){if(-not$deployedById.ContainsKey($id)){throw "Deployment manifest is missing inventory mod '$id'."}}
    # Fail cheap release-row defects before opening hundreds of immutable Lua
    # blobs. Legacy no-commit rows are validated against pinned trees below.
    foreach($id in @($deployedById.Keys)){
        $row=$deployedById[$id];$commit=[string]$row.source_commit
        if([string]::IsNullOrWhiteSpace($commit)){continue}
        if($commit -notmatch '^[0-9a-f]{40}$'){throw "Deployed mod '$id' source_commit is not a full 40-hex commit."}
        if([string]$row.source_state -cne 'clean'){throw "Deployed mod '$id' source_state must be clean, got '$($row.source_state)'."}
    }

    $legacyByKey=@{}
    foreach($legacy in @($exceptions.LegacySourceTrees)){
        $key=([string]$legacy.ModId)+"`n"+([string]$legacy.Version)
        if($legacyByKey.ContainsKey($key)){throw "Duplicate legacy source-tree exception '$key'."}
        if([string]$legacy.RootTree -notmatch '^[0-9a-f]{40}$' -or [string]$legacy.ModTree -notmatch '^[0-9a-f]{40}$' -or [string]::IsNullOrWhiteSpace([string]$legacy.Reason)){
            throw "Malformed legacy source-tree exception '$key'."
        }
        $legacyByKey[$key]=$legacy
    }

    # Hydrate every deployed Lua blob this pass will read in a few batched
    # fetches before the per-mod archive transactions begin (#750). Targets are
    # resolved leniently here; the record loop below is the authority on a
    # malformed or unreachable deployed tree.
    $prefetchTargets=@()
    foreach($entry in @($inventory.Mods)){
        $id=[string]$entry.ModId
        if(-not$deployedById.ContainsKey($id)){continue}
        $row=$deployedById[$id]
        $treeish=[string]$row.source_commit
        if([string]::IsNullOrWhiteSpace($treeish)){
            $legacyKey=$id+"`n"+([string]$row.version)
            if(-not$legacyByKey.ContainsKey($legacyKey)){continue}
            $treeish=[string]$legacyByKey[$legacyKey].RootTree
        }
        $prefetchTargets+=[pscustomobject]@{
            Commit=$treeish
            Root=(([string]$entry.Dir).TrimEnd([char[]]'\/') -replace '\\','/') + '/scripts/mods'
        }
    }
    Invoke-VtContractDeployedBlobPrefetch -RepoRoot $RepoRoot -DeployedTrees @($prefetchTargets)

    $records=New-Object System.Collections.Generic.List[object]
    $documentsByMod=@{}
    foreach($entry in @($inventory.Mods)){
        $recordWatch=[Diagnostics.Stopwatch]::StartNew()
        $id=[string]$entry.ModId; $row=$deployedById[$id]
        Write-Verbose "Indexing immutable deployed source for $id..."
        if([string]$row.workshop_id -cne [string]$entry.WorkshopId){throw "Workshop identity drift for '$id': inventory=$($entry.WorkshopId), deployed=$($row.workshop_id)."}
        if([string]::IsNullOrWhiteSpace([string]$row.version)){throw "Deployed mod '$id' has no version."}
        $relativeRoot=(([string]$entry.Dir).TrimEnd([char[]]'\/') -replace '\\','/') + '/scripts/mods'
        $commit=[string]$row.source_commit
        $rootTree=$null; $modTree=$null; $treeish=$null
        if(-not[string]::IsNullOrWhiteSpace($commit)){
            if($commit -notmatch '^[0-9a-f]{40}$'){throw "Deployed mod '$id' source_commit is not a full 40-hex commit."}
            if([string]$row.source_state -cne 'clean'){throw "Deployed mod '$id' source_state must be clean, got '$($row.source_state)'."}
            $type=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$commit) -Description "Source object for '$id'"
            if($type -cne 'commit'){throw "Deployed mod '$id' source_commit is not a commit object."}
            $rootTree=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$commit^{tree}") -Description "Root tree for '$id'"
            $modTree=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$commit`:$relativeRoot") -Description "Mod subtree for '$id'"
            if($rootTree -notmatch '^[0-9a-f]{40}$' -or $modTree -notmatch '^[0-9a-f]{40}$'){throw "Deployed source tree resolution failed for '$id'."}
            $treeish=$commit
        }else{
            $legacyKey=$id+"`n"+([string]$row.version)
            if(-not$legacyByKey.ContainsKey($legacyKey)){throw "Deployed mod '$id' has no source_commit and no exact legacy tree exception for '$($row.version)'."}
            $legacy=$legacyByKey[$legacyKey]; $rootTree=[string]$legacy.RootTree; $modTree=[string]$legacy.ModTree
            $type=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$rootTree) -Description "Legacy root tree for '$id'"
            if($type -cne 'tree'){throw "Legacy root tree for '$id' is not a tree object."}
            $derived=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$rootTree`:$relativeRoot") -Description "Legacy mod subtree for '$id'"
            if($derived -cne $modTree){throw "Legacy source-tree exception drift for '$id': pinned=$modTree, actual=$derived."}
            $treeish=$rootTree
        }
        $requiredSources=@(Get-VtExceptionSourcePaths -Exceptions $exceptions -ModId $id)
        $documents=@(Get-VtDeployedLuaDocuments -RepoRoot $RepoRoot -Treeish $treeish `
            -RelativeRoot $relativeRoot -RequiredRelativePaths $requiredSources)
        if($documents.Count -eq 0){throw "Deployed mod '$id' has no Lua source under '$relativeRoot'."}
        $documentsByMod[$id]=@($documents)
        $declaredVersions=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($document in $documents){
            if([string]$document.Content -notmatch '(?i)MOD_VERSION'){continue}
            $tokens=@($document.Tokens)
            for($versionIndex=0;$versionIndex+3 -lt $tokens.Count;$versionIndex++){
                if((Test-VtLuaToken $tokens[$versionIndex] 'local' 'Identifier') -and
                    (Test-VtLuaToken $tokens[$versionIndex+1] 'MOD_VERSION' 'Identifier') -and
                    (Test-VtLuaToken $tokens[$versionIndex+2] '=') -and
                    [string]$tokens[$versionIndex+3].Kind -eq 'String'){
                    $null=$declaredVersions.Add(([string]$tokens[$versionIndex+3].Value).TrimStart('v'))
                }
            }
        }
        $releaseVersion=([string]$row.version).TrimStart('v')
        if($declaredVersions.Count -ne 1 -or -not$declaredVersions.Contains($releaseVersion)){
            throw "Deployed mod '$id' MOD_VERSION drift: source=$(@($declaredVersions) -join ','), release=$releaseVersion."
        }
        $reachablePaths=Get-VtLoadTimeReachableLuaPaths -ModDir ([string]$entry.Dir) -Documents $documents
        $reachableDocuments=@($documents | Where-Object {$reachablePaths.Contains([string]$_.RelativePath)})
        if($reachableDocuments.Count -eq 0){throw "Deployed mod '$id' exposes no statically reachable Lua entry document."}
        foreach($document in $documents){
            if([string]$document.Content -notmatch '(?i)(?:_G|_ENV)\s*(?:\.|\[)\s*["'']?printf|rawset\s*\(\s*(?:_G|_ENV|getfenv)|\b(?:debug\.)?setfenv\s*\(|\bgetfenv\s*\('){continue}
            if(Test-VtLuaMutatesGlobalPrintf -Tokens @($document.Tokens)){
                throw "Deployed mod '$id' mutates global/environment printf in '$($document.RelativePath)'; raw printf authority is record-wide and fails closed."
            }
        }
        $commandRoutes=New-Object System.Collections.Generic.List[object]
        $receiptRoutes=New-Object System.Collections.Generic.List[object]
        $loadRoutes=New-Object System.Collections.Generic.List[object]
        $bannerRoutes=New-Object System.Collections.Generic.List[object]
        foreach($document in $reachableDocuments){
            if([string]$document.Content -notmatch '(?i)\bprintf\b|\bmod\s*:\s*(?:command|info|echo|warning|error)\b|v%s\s+loaded'){continue}
            $scan=Get-VtDirectLuaCallRoutes -Document $document
            foreach($x in @($scan.CommandRoutes)){$commandRoutes.Add($x)}
            foreach($x in @($scan.ReceiptRoutes)){$receiptRoutes.Add($x)}
            foreach($x in @($scan.LoadRoutes)){$loadRoutes.Add($x)}
            foreach($x in @($scan.ExactBannerRoutes)){$bannerRoutes.Add($x)}
        }
        foreach($x in @(Get-VtInjectedReceiptRoutes -ModDir ([string]$entry.Dir) -Documents $reachableDocuments)){$receiptRoutes.Add($x)}
        # Accept only a route-local structural proof or an immutable-tree,
        # exact-signature/token-anchor exception. Nearby prose and marker-wide
        # sibling emitters never prove this route finite.
        Set-VtStructuralReceiptBounds -Documents $documents -Routes $receiptRoutes
        Set-VtReceiptOverrideBounds -ModId $id -ModTree $modTree -Documents $documents -Routes $receiptRoutes -CommandRoutes $commandRoutes -Exceptions $exceptions
        if($loadRoutes.Count -eq 0){throw "Deployed mod '$id' exposes no literal runtime [*:LOAD] route."}
        $records.Add([pscustomobject][ordered]@{
            ModId=$id; Dir=[string]$entry.Dir; FriendlyName=[string]$row.friendly_name
            Version=([string]$row.version).TrimStart('v'); WorkshopId=[string]$row.workshop_id
            SourceCommit=if($commit){$commit}else{$null}; RootTree=$rootTree; ModTree=$modTree
            ReleaseTag=[string]$DeploymentManifest.release_tag
            LoadRoutes=@($loadRoutes.ToArray()); ExactBannerRoutes=@($bannerRoutes.ToArray())
            CommandRoutes=@($commandRoutes.ToArray()); ReceiptRoutes=@($receiptRoutes.ToArray())
            MenuSurfaces=@(Get-VtMenuSurfaces -Documents $reachableDocuments)
        })
        $recordWatch.Stop()
        Write-Verbose "Indexed $id ($($reachableDocuments.Count) reachable of $($documents.Count) candidate Lua files) in $($recordWatch.ElapsedMilliseconds) ms."
    }
    Set-VtReceiptFamilyOverrides -Records @($records.ToArray()) -DocumentsByMod $documentsByMod -Exceptions $exceptions
    Set-VtReceiptDiscoveryOverrides -Records @($records.ToArray()) -DocumentsByMod $documentsByMod -Exceptions $exceptions
    return [pscustomobject][ordered]@{ ReleaseTag=[string]$DeploymentManifest.release_tag; Records=@($records.ToArray()) }
}

function New-VtLiveTestCardAuthority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Source,
        [Parameter(Mandatory=$true)]$DeploymentManifest
    )
    # Source is already a deployment-bound record set. Keep this named
    # constructor so existing consumers have one migration point.
    if([string]$Source.ReleaseTag -cne [string]$DeploymentManifest.release_tag){throw 'Source/deployment release-tag drift.'}
    return $Source
}
