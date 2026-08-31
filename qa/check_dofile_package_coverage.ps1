# check_dofile_package_coverage.ps1
#
# Literal mod:dofile targets are runtime resources, not ordinary loose files.
# VMB compiles only Lua paths named by the owning resource package (or matched
# by its wildcard). A source-only helper therefore passes ordinary unit tests
# but becomes "Resource not found" in-game. This blocking gate rejects that
# drift across whitespace and comments, including multiline calls.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# PowerShell object allocation per Lua token made this repository-wide Quick
# gate take more than a minute once the active source exceeded 15 MB. Keep the
# exact lexical contract in a tiny in-process scanner shared by PS7 and PS5.1.
if (-not ('Vt2DofilePackageScanner' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

public sealed class Vt2DofileTarget
{
    public string Path { get; private set; }
    public int Line { get; private set; }

    public Vt2DofileTarget(string path, int line)
    {
        Path = path;
        Line = line;
    }
}

public static class Vt2DofilePackageScanner
{
    private const int Identifier = 1;
    private const int StringLiteral = 2;
    private const int Symbol = 3;
    private const int Other = 4;

    private sealed class Token
    {
        public int Kind;
        public string Value;
        public int Line;

        public Token(int kind, string value, int line)
        {
            Kind = kind;
            Value = value;
            Line = line;
        }
    }

    private static bool IsRelevantIdentifier(string value)
    {
        return value == "mod" || value == "dofile" || value == "pcall" || value == "lua";
    }

    private static void AddOther(List<Token> tokens, int line)
    {
        if (tokens.Count == 0 || tokens[tokens.Count - 1].Kind != Other)
            tokens.Add(new Token(Other, "<other>", line));
    }

    private static int LongBracketLevel(string text, int index)
    {
        if (index >= text.Length || text[index] != '[') return -1;
        int cursor = index + 1;
        while (cursor < text.Length && text[cursor] == '=') cursor++;
        if (cursor >= text.Length || text[cursor] != '[') return -1;
        return cursor - index - 1;
    }

    private static int SkipLongBracket(string text, int index, int level, ref int line)
    {
        int start = index + level + 2;
        string close = "]" + new string('=', level) + "]";
        int closeAt = text.IndexOf(close, start, StringComparison.Ordinal);
        int end = closeAt < 0 ? text.Length : closeAt + close.Length;
        for (int i = index; i < end; i++)
            if (text[i] == '\n') line++;
        return end;
    }

    private static List<Token> Tokenize(string text)
    {
        List<Token> tokens = new List<Token>();
        int index = 0;
        int line = 1;

        while (index < text.Length)
        {
            char current = text[index];
            if (current == '\n') { line++; index++; continue; }
            if (Char.IsWhiteSpace(current)) { index++; continue; }

            if (current == '-' && index + 1 < text.Length && text[index + 1] == '-')
            {
                int level = LongBracketLevel(text, index + 2);
                if (level >= 0)
                {
                    index = SkipLongBracket(text, index + 2, level, ref line);
                    continue;
                }
                while (index < text.Length && text[index] != '\n') index++;
                continue;
            }

            int longLevel = LongBracketLevel(text, index);
            if (longLevel >= 0)
            {
                int tokenLine = line;
                index = SkipLongBracket(text, index, longLevel, ref line);
                AddOther(tokens, tokenLine);
                continue;
            }

            if (current == '"' || current == '\'')
            {
                char quote = current;
                int tokenLine = line;
                index++;
                StringBuilder value = new StringBuilder();
                while (index < text.Length)
                {
                    current = text[index];
                    if (current == '\n') line++;
                    if (current == '\\' && index + 1 < text.Length)
                    {
                        index++;
                        value.Append(text[index]);
                        index++;
                        continue;
                    }
                    if (current == quote) { index++; break; }
                    value.Append(current);
                    index++;
                }
                tokens.Add(new Token(StringLiteral, value.ToString(), tokenLine));
                continue;
            }

            if (Char.IsLetter(current) || current == '_')
            {
                int start = index;
                int tokenLine = line;
                index++;
                while (index < text.Length &&
                    (Char.IsLetterOrDigit(text[index]) || text[index] == '_')) index++;
                string value = text.Substring(start, index - start);
                if (IsRelevantIdentifier(value))
                    tokens.Add(new Token(Identifier, value, tokenLine));
                else
                    AddOther(tokens, tokenLine);
                continue;
            }

            if (".:(),=[]".IndexOf(current) >= 0)
                tokens.Add(new Token(Symbol, current.ToString(), line));
            else
                AddOther(tokens, line);
            index++;
        }
        return tokens;
    }

    private static bool Is(List<Token> tokens, int index, string value)
    {
        return index >= 0 && index < tokens.Count && tokens[index].Value == value;
    }

    public static Vt2DofileTarget[] GetDofileTargets(string text)
    {
        List<Token> tokens = Tokenize(text ?? "");
        List<Vt2DofileTarget> targets = new List<Vt2DofileTarget>();
        for (int i = 0; i < tokens.Count; i++)
        {
            if (Is(tokens, i, "mod") && Is(tokens, i + 1, ":") &&
                Is(tokens, i + 2, "dofile") && Is(tokens, i + 3, "(") &&
                i + 4 < tokens.Count && tokens[i + 4].Kind == StringLiteral)
            {
                targets.Add(new Vt2DofileTarget(tokens[i + 4].Value, tokens[i].Line));
                continue;
            }
            if (Is(tokens, i, "mod") && Is(tokens, i + 1, ".") &&
                Is(tokens, i + 2, "dofile") && Is(tokens, i + 3, "(") &&
                Is(tokens, i + 4, "mod") && Is(tokens, i + 5, ",") &&
                i + 6 < tokens.Count && tokens[i + 6].Kind == StringLiteral)
            {
                targets.Add(new Vt2DofileTarget(tokens[i + 6].Value, tokens[i].Line));
                continue;
            }
            if (Is(tokens, i, "pcall") && Is(tokens, i + 1, "(") &&
                Is(tokens, i + 2, "mod") && Is(tokens, i + 3, ".") &&
                Is(tokens, i + 4, "dofile") && Is(tokens, i + 5, ",") &&
                Is(tokens, i + 6, "mod") && Is(tokens, i + 7, ",") &&
                i + 8 < tokens.Count && tokens[i + 8].Kind == StringLiteral)
            {
                targets.Add(new Vt2DofileTarget(tokens[i + 8].Value, tokens[i].Line));
            }
        }
        return targets.ToArray();
    }

    public static string[] GetPackageLuaEntries(string text)
    {
        List<Token> tokens = Tokenize(text ?? "");
        List<string> entries = new List<string>();
        for (int i = 0; i + 2 < tokens.Count; i++)
        {
            if (!Is(tokens, i, "lua") || !Is(tokens, i + 1, "=") ||
                !Is(tokens, i + 2, "[")) continue;
            int depth = 1;
            int cursor = i + 3;
            while (cursor < tokens.Count && depth > 0)
            {
                if (Is(tokens, cursor, "[")) depth++;
                else if (Is(tokens, cursor, "]")) depth--;
                else if (depth > 0 && tokens[cursor].Kind == StringLiteral)
                    entries.Add(tokens[cursor].Value);
                cursor++;
            }
            i = cursor - 1;
        }
        return entries.ToArray();
    }
}
'@
}

function Get-DofileLiteralTargets([string]$Text) {
    return [Vt2DofilePackageScanner]::GetDofileTargets($Text)
}

function Get-PackageLuaEntries([string]$Text) {
    return [Vt2DofilePackageScanner]::GetPackageLuaEntries($Text)
}

function Test-TargetCovered([string]$Target, $PackageEntries) {
    foreach ($entry in $PackageEntries) {
        if ($entry -ceq $Target -or ($entry.Contains('*') -and $Target -clike $entry)) {
            return $true
        }
    }
    return $false
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $source = @'
local prose = "mod:dofile('scripts/mods/fake/in_string')"
-- mod:dofile("scripts/mods/fake/in_line_comment")
--[=[ mod:dofile("scripts/mods/fake/in_block_comment") ]=]
local long_prose = [=[mod:dofile("scripts/mods/fake/in_long_string")]=]
local one = mod:dofile(
    -- a comment may split the call from its literal target
    "scripts/mods/example/multiline_colon"
)
local two = mod.dofile(
    mod,
    'scripts/mods/example/multiline_dot')
local ok, three = pcall(
    mod.dofile,
    mod,
    "scripts/mods/example/multiline_pcall")
'@
    $targets = @(Get-DofileLiteralTargets -Text $source)
    $expected = @(
        'scripts/mods/example/multiline_colon',
        'scripts/mods/example/multiline_dot',
        'scripts/mods/example/multiline_pcall'
    )
    if ($targets.Count -ne $expected.Count) {
        $failures.Add("multiline/comment lexer returned $($targets.Count), expected $($expected.Count)")
    } else {
        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ($targets[$i].Path -cne $expected[$i]) {
                $failures.Add("target[$i] was '$($targets[$i].Path)', expected '$($expected[$i])'")
            }
        }
    }

    $package = @'
lua = [
    "scripts/mods/example/exact"
    -- "scripts/mods/example/comment_only"
    "scripts/mods/example/helpers/*"
]
material = [ "scripts/mods/example/material_only" ]
--[=[ lua = [ "scripts/mods/example/block_comment_only" ] ]=]
'@
    $entries = @(Get-PackageLuaEntries -Text $package)
    if ($entries.Count -ne 2 -or $entries[0] -cne 'scripts/mods/example/exact' -or
        $entries[1] -cne 'scripts/mods/example/helpers/*') {
        $failures.Add("package lexer did not isolate the active lua list")
    }
    if (-not (Test-TargetCovered 'scripts/mods/example/exact' $entries) -or
        -not (Test-TargetCovered 'scripts/mods/example/helpers/child' $entries) -or
        (Test-TargetCovered 'scripts/mods/example/Helpers/child' $entries) -or
        (Test-TargetCovered 'scripts/mods/example/material_only' $entries) -or
        (Test-TargetCovered 'scripts/mods/example/comment_only' $entries)) {
        $failures.Add("case-exact/wildcard/comment package coverage verdict drifted")
    }

    if ($failures.Count -gt 0) {
        Write-Host "[check_dofile_package_coverage -SelfTest] FAILED" -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  ERROR: $failure" -ForegroundColor Red }
        return 2
    }
    Write-Host "[check_dofile_package_coverage -SelfTest] OK - multiline and comment adversaries passed" -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path (Split-Path $scriptPath -Parent) -Parent
}
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = New-Object System.Collections.Generic.List[string]
$inventory = Import-PowerShellDataFile (Join-Path $repoRoot "tools\mod-inventory.psd1")

foreach ($modEntry in $inventory.Mods) {
    $modDir = Get-Item -LiteralPath (Join-Path $repoRoot $modEntry.Dir)
    $packageRoot = Join-Path $modDir.FullName "resource_packages"
    $scriptRoot = Join-Path $modDir.FullName "scripts"
    if (-not (Test-Path -LiteralPath $packageRoot) -or
        -not (Test-Path -LiteralPath $scriptRoot)) {
        continue
    }

    $packageEntries = New-Object System.Collections.Generic.List[string]
    foreach ($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.package") {
        foreach ($entry in Get-PackageLuaEntries -Text (Read-Utf8 $packageFile.FullName)) {
            $packageEntries.Add($entry)
        }
    }

    foreach ($luaFile in Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.lua") {
        $luaSource = Read-Utf8 $luaFile.FullName
        if ($luaSource.IndexOf('dofile', [System.StringComparison]::Ordinal) -lt 0) {
            continue
        }
        foreach ($target in Get-DofileLiteralTargets -Text $luaSource) {
            $sourcePath = Join-Path $modDir.FullName (($target.Path -replace '/', '\') + ".lua")
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                $errors.Add("$($modDir.Name): $($luaFile.Name):$($target.Line) dofile target has no source file: $($target.Path).lua")
                continue
            }
            if (-not (Test-TargetCovered $target.Path $packageEntries)) {
                $errors.Add("$($modDir.Name): $($luaFile.Name):$($target.Line) dofile target omitted from resource package: $($target.Path)")
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "[check_dofile_package_coverage] FAIL - $($errors.Count) error(s)" -ForegroundColor Red
    foreach ($errorText in $errors) { Write-Host "  ERROR: $errorText" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host "[check_dofile_package_coverage] OK - literal mod:dofile targets are package-covered" -ForegroundColor Green
}
exit 0
