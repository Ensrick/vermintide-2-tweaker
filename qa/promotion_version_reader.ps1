# Shared, source-qualified MOD_VERSION reader for stable-promotion authority.
#
# This file is dot-sourced by both check_promotion_authorization.ps1 and
# check_promotion.ps1. Keep it Windows PowerShell 5.1 compatible and free of
# process-level side effects.

function Get-PromotionLuaLongBracket {
    param(
        [string]$Text,
        [int]$Index
    )

    if ($Index -lt 0 -or $Index -ge $Text.Length -or $Text[$Index] -ne '[') {
        return $null
    }
    $cursor = $Index + 1
    while ($cursor -lt $Text.Length -and $Text[$cursor] -eq '=') { $cursor++ }
    if ($cursor -ge $Text.Length -or $Text[$cursor] -ne '[') {
        return $null
    }
    $equals = $cursor - $Index - 1
    return [pscustomobject]@{
        OpenLength = $equals + 2
        CloseText = ']' + ('=' * $equals) + ']'
    }
}

function Get-PromotionLuaTokens {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$SourceLabel = '<Lua source>'
    )

    $tokens = New-Object System.Collections.Generic.List[object]
    $index = 0
    $line = 1
    while ($index -lt $Text.Length) {
        $ch = $Text[$index]
        if ([char]::IsWhiteSpace($ch)) {
            if ($ch -eq "`n") { $line++ }
            $index++
            continue
        }

        # Lua comments: -- line comments and --[=*[ long comments ]=*].
        if ($ch -eq '-' -and $index + 1 -lt $Text.Length -and $Text[$index + 1] -eq '-') {
            $longComment = Get-PromotionLuaLongBracket -Text $Text -Index ($index + 2)
            if ($null -ne $longComment) {
                $contentStart = $index + 2 + $longComment.OpenLength
                $closeAt = $Text.IndexOf(
                    $longComment.CloseText,
                    $contentStart,
                    [System.StringComparison]::Ordinal
                )
                if ($closeAt -lt 0) {
                    throw "unterminated Lua long comment in $SourceLabel"
                }
                while ($index -lt ($closeAt + $longComment.CloseText.Length)) {
                    if ($Text[$index] -eq "`n") { $line++ }
                    $index++
                }
                continue
            }
            while ($index -lt $Text.Length -and $Text[$index] -ne "`n") { $index++ }
            continue
        }

        # Long-bracket strings are data, never executable version declarations.
        if ($ch -eq '[') {
            $longString = Get-PromotionLuaLongBracket -Text $Text -Index $index
            if ($null -ne $longString) {
                $startLine = $line
                $startIndex = $index
                $contentStart = $index + $longString.OpenLength
                $closeAt = $Text.IndexOf(
                    $longString.CloseText,
                    $contentStart,
                    [System.StringComparison]::Ordinal
                )
                if ($closeAt -lt 0) {
                    throw "unterminated Lua long string in $SourceLabel"
                }
                while ($index -lt ($closeAt + $longString.CloseText.Length)) {
                    if ($Text[$index] -eq "`n") { $line++ }
                    $index++
                }
                [void]$tokens.Add([pscustomobject]@{
                    Kind = 'long-string'
                    Text = '<long-string>'
                    Value = $null
                    Quote = $null
                    HasEscape = $false
                    Line = $startLine
                    Position = $startIndex
                })
                continue
            }
        }

        # Short quoted strings are one token. Their contents are never rescanned.
        if ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            $startLine = $line
            $startIndex = $index
            $bodyStart = $index + 1
            $hasEscape = $false
            $index++
            $closed = $false
            while ($index -lt $Text.Length) {
                $current = $Text[$index]
                if ($current -eq '\') {
                    $hasEscape = $true
                    $index++
                    if ($index -ge $Text.Length) { break }
                    if ($Text[$index] -eq "`n") { $line++ }
                    $index++
                    continue
                }
                if ($current -eq $quote) {
                    $value = $Text.Substring($bodyStart, $index - $bodyStart)
                    $index++
                    $closed = $true
                    [void]$tokens.Add([pscustomobject]@{
                        Kind = 'short-string'
                        Text = '<short-string>'
                        Value = $value
                        Quote = "$quote"
                        HasEscape = $hasEscape
                        Line = $startLine
                        Position = $startIndex
                    })
                    break
                }
                if ($current -eq "`n" -or $current -eq "`r") {
                    throw "raw newline in Lua short string in $SourceLabel at line $startLine"
                }
                $index++
            }
            if (-not $closed) {
                throw "unterminated Lua short string in $SourceLabel at line $startLine"
            }
            continue
        }

        $code = [int][char]$ch
        $isIdentifierStart = ($code -ge 65 -and $code -le 90) -or
            ($code -ge 97 -and $code -le 122) -or $ch -eq '_'
        if ($isIdentifierStart) {
            $start = $index
            $index++
            while ($index -lt $Text.Length) {
                $next = $Text[$index]
                $nextCode = [int][char]$next
                $isIdentifierPart = ($nextCode -ge 65 -and $nextCode -le 90) -or
                    ($nextCode -ge 97 -and $nextCode -le 122) -or
                    ($nextCode -ge 48 -and $nextCode -le 57) -or $next -eq '_'
                if (-not $isIdentifierPart) { break }
                $index++
            }
            $identifier = $Text.Substring($start, $index - $start)
            [void]$tokens.Add([pscustomobject]@{
                Kind = 'identifier'
                Text = $identifier
                Value = $identifier
                Quote = $null
                HasEscape = $false
                Line = $line
                Position = $start
            })
            continue
        }

        [void]$tokens.Add([pscustomobject]@{
            Kind = 'symbol'
            Text = "$ch"
            Value = "$ch"
            Quote = $null
            HasEscape = $false
            Line = $line
            Position = $index
        })
        $index++
    }
    return @($tokens.ToArray())
}

function Test-PromotionLuaLabelEndingAt {
    param(
        [object[]]$Tokens,
        [int]$EndIndex
    )

    # Vermintide's Lua dialect supports `::label::`. The closing `::` is a
    # statement boundary, never a member separator for the following name.
    if ($EndIndex -lt 4) { return $false }
    return $Tokens[$EndIndex].Kind -eq 'symbol' -and $Tokens[$EndIndex].Text -eq ':' -and
        $Tokens[$EndIndex - 1].Kind -eq 'symbol' -and $Tokens[$EndIndex - 1].Text -eq ':' -and
        $Tokens[$EndIndex - 2].Kind -eq 'identifier' -and
        $Tokens[$EndIndex - 3].Kind -eq 'symbol' -and $Tokens[$EndIndex - 3].Text -eq ':' -and
        $Tokens[$EndIndex - 4].Kind -eq 'symbol' -and $Tokens[$EndIndex - 4].Text -eq ':'
}

function Test-PromotionLuaMemberIdentifier {
    param(
        [object[]]$Tokens,
        [int]$IdentifierIndex
    )

    if ($IdentifierIndex -lt 2) { return $false }
    $separator = $Tokens[$IdentifierIndex - 1]
    if ($separator.Kind -ne 'symbol' -or $separator.Text -notin @('.', ':')) {
        return $false
    }
    if ($separator.Text -eq ':' -and
            (Test-PromotionLuaLabelEndingAt -Tokens $Tokens -EndIndex ($IdentifierIndex - 1))) {
        return $false
    }

    # A separator proves a member only when it has an actual receiver. This
    # deliberately excludes the punctuation of a statement label.
    $receiver = $Tokens[$IdentifierIndex - 2]
    return $receiver.Kind -eq 'identifier' -or
        ($receiver.Kind -eq 'symbol' -and $receiver.Text -in @(')', ']'))
}

function Test-PromotionLuaPotentialAssignmentLhs {
    param(
        [object[]]$Tokens,
        [int]$VersionIndex
    )

    $versionToken = $Tokens[$VersionIndex]
    $parenDepth = 0
    $bracketDepth = 0
    $braceDepth = 0
    $right = $versionToken
    for ($cursor = $VersionIndex - 1; $cursor -ge 0; $cursor--) {
        $token = $Tokens[$cursor]
        $atBase = $parenDepth -eq 0 -and $bracketDepth -eq 0 -and $braceDepth -eq 0
        if ($atBase) {
            if (Test-PromotionLuaLabelEndingAt -Tokens $Tokens -EndIndex $cursor) {
                return $true
            }
            $endsExpression = ($token.Kind -eq 'identifier' -and
                    $token.Text -notin @('and', 'or', 'not', 'local', 'return', 'then', 'do', 'else')) -or
                $token.Kind -in @('short-string', 'long-string') -or
                ($token.Kind -eq 'symbol' -and
                    ($token.Text -in @(')', ']', '}') -or $token.Text -match '^[0-9]$'))
            $rightStartsStatement = $right.Kind -eq 'identifier' -and
                $right.Text -notin @('and', 'or')
            if ($endsExpression -and $rightStartsStatement) {
                return $true
            }
            if ($token.Kind -eq 'symbol' -and $token.Text -eq ';') { return $true }
            if ($token.Kind -eq 'symbol' -and $token.Text -eq '=' -and
                    -not ($cursor -gt 0 -and $Tokens[$cursor - 1].Kind -eq 'symbol' -and
                        $Tokens[$cursor - 1].Text -eq '=') -and
                    -not ($cursor + 1 -lt $Tokens.Count -and $Tokens[$cursor + 1].Kind -eq 'symbol' -and
                        $Tokens[$cursor + 1].Text -eq '=')) {
                return $false
            }
            if ($token.Kind -eq 'identifier') {
                if ($token.Text -eq 'return') { return $false }
                if ($token.Text -in @('local', 'then', 'do', 'else', 'repeat', 'end', 'until', 'function')) {
                    return $true
                }
            }
        }

        # Reverse-balanced delimiters prove whether this read is inside an
        # enclosing call/table/index expression that began before MOD_VERSION.
        if ($token.Kind -eq 'symbol') {
            if ($token.Text -eq ')') { $parenDepth++ }
            elseif ($token.Text -eq '(') { if ($parenDepth -gt 0) { $parenDepth-- } else { return $false } }
            elseif ($token.Text -eq ']') { $bracketDepth++ }
            elseif ($token.Text -eq '[') { if ($bracketDepth -gt 0) { $bracketDepth-- } else { return $false } }
            elseif ($token.Text -eq '}') { $braceDepth++ }
            elseif ($token.Text -eq '{') { if ($braceDepth -gt 0) { $braceDepth-- } else { return $false } }
        }
        $right = $token
    }
    return $true
}

function Test-PromotionLuaNamedBinding {
    param(
        [object[]]$Tokens,
        [int]$VersionIndex
    )

    # `local x, MOD_VERSION` and `for x, MOD_VERSION in ...` are bindings even
    # without an immediate '=' after the version token. Walk only the closed
    # NameList grammar; arbitrary expressions terminate the proof.
    $cursor = $VersionIndex - 1
    $expectName = $false
    while ($cursor -ge 0) {
        $token = $Tokens[$cursor]
        if (-not $expectName) {
            if ($token.Kind -eq 'identifier' -and $token.Text -in @('local', 'for')) {
                return $true
            }
            if ($token.Kind -ne 'symbol' -or $token.Text -ne ',') { return $false }
            $expectName = $true
        } else {
            if ($token.Kind -ne 'identifier') { return $false }
            $expectName = $false
        }
        $cursor--
    }
    return $false
}

function Test-PromotionLuaFunctionParameterBinding {
    param(
        [object[]]$Tokens,
        [int]$VersionIndex
    )

    # Lua function parameters are lexical bindings. Find the unmatched opening
    # parenthesis which owns this token, then accept only the closed FuncName /
    # anonymous-function grammar immediately before it. This rejects both
    # `function f(MOD_VERSION)` and `local f = function(x, MOD_VERSION)` without
    # confusing an ordinary call such as `f(MOD_VERSION)` with a declaration.
    $parenDepth = 0
    $openIndex = -1
    for ($cursor = $VersionIndex - 1; $cursor -ge 0; $cursor--) {
        $token = $Tokens[$cursor]
        if ($token.Kind -ne 'symbol') { continue }
        if ($token.Text -eq ')') {
            $parenDepth++
        } elseif ($token.Text -eq '(') {
            if ($parenDepth -gt 0) {
                $parenDepth--
            } else {
                $openIndex = $cursor
                break
            }
        }
    }
    if ($openIndex -lt 1) { return $false }

    $cursor = $openIndex - 1
    if ($Tokens[$cursor].Kind -eq 'identifier' -and $Tokens[$cursor].Text -ceq 'function') {
        return $true
    }
    if ($Tokens[$cursor].Kind -ne 'identifier') { return $false }
    $cursor--
    while ($cursor -ge 0) {
        $token = $Tokens[$cursor]
        if ($token.Kind -eq 'identifier' -and $token.Text -ceq 'function') {
            return $true
        }
        if ($token.Kind -ne 'symbol' -or $token.Text -notin @('.', ':') -or $cursor -lt 1) {
            return $false
        }
        $cursor--
        if ($Tokens[$cursor].Kind -ne 'identifier') { return $false }
        $cursor--
    }
    return $false
}

function Test-PromotionLuaAssignmentTail {
    param(
        [object[]]$Tokens,
        [int]$VersionIndex
    )

    # The immediate '=' case is handled by the caller. Here, conservatively scan
    # a comma tail for a top-level assignment operator. This catches complex Lua
    # lvalues such as `(t).x` and `f().x`, but stops at the unmatched delimiter of
    # an enclosing call/table or at an evident next statement. Ordinary reads
    # such as `fn(MOD_VERSION, x)` and `local x = MOD_VERSION, y` remain valid.
    $cursor = $VersionIndex + 1
    if ($cursor -ge $Tokens.Count -or $Tokens[$cursor].Kind -ne 'symbol' -or
            $Tokens[$cursor].Text -ne ',') {
        return $false
    }
    if (-not (Test-PromotionLuaPotentialAssignmentLhs -Tokens $Tokens -VersionIndex $VersionIndex)) {
        return $false
    }

    $parenDepth = 0
    $bracketDepth = 0
    $braceDepth = 0
    $previous = $Tokens[$VersionIndex]
    while ($cursor -lt $Tokens.Count) {
        $token = $Tokens[$cursor]
        $atBase = $parenDepth -eq 0 -and $bracketDepth -eq 0 -and $braceDepth -eq 0
        if ($atBase) {
            if ($token.Kind -eq 'symbol' -and $token.Text -eq '=' -and
                    -not ($cursor + 1 -lt $Tokens.Count -and $Tokens[$cursor + 1].Kind -eq 'symbol' -and
                        $Tokens[$cursor + 1].Text -eq '=')) {
                return $true
            }
            if ($token.Kind -eq 'symbol' -and $token.Text -eq ';') { return $false }
            if ($token.Kind -eq 'symbol' -and $token.Text -in @(')', ']', '}')) { return $false }

            $previousEndsExpression = $previous.Kind -in @('identifier', 'short-string', 'long-string') -or
                ($previous.Kind -eq 'symbol' -and $previous.Text -in @(')', ']', '}'))
            $startsNewStatement = $token.Kind -eq 'identifier'
            if ($token.Line -gt $previous.Line -and $previousEndsExpression -and $startsNewStatement) {
                return $false
            }
        }

        if ($token.Kind -eq 'symbol') {
            if ($token.Text -eq '(') { $parenDepth++ }
            elseif ($token.Text -eq ')') { if ($parenDepth -gt 0) { $parenDepth-- } else { return $false } }
            elseif ($token.Text -eq '[') { $bracketDepth++ }
            elseif ($token.Text -eq ']') { if ($bracketDepth -gt 0) { $bracketDepth-- } else { return $false } }
            elseif ($token.Text -eq '{') { $braceDepth++ }
            elseif ($token.Text -eq '}') { if ($braceDepth -gt 0) { $braceDepth-- } else { return $false } }
        }
        $previous = $token
        $cursor++
    }
    return $false
}

function Get-CanonicalPromotionModVersion {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$SourceLabel = '<Lua source>'
    )

    $versionPattern = '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?$'
    $tokens = @(Get-PromotionLuaTokens -Text $Text -SourceLabel $SourceLabel)
    $candidates = New-Object System.Collections.Generic.List[object]
    $directAssignments = New-Object System.Collections.Generic.List[object]
    $blockDepth = 0
    $pendingLoopDo = 0

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($token.Kind -eq 'identifier') {
            # Track enough Lua block structure to reject a declaration hidden in
            # an unreachable/nested block. Reassignments are counted at every
            # block depth because a closure can mutate the file-local value.
            if ($token.Text -in @('if', 'function', 'for', 'while', 'repeat')) {
                $blockDepth++
                if ($token.Text -in @('for', 'while')) { $pendingLoopDo++ }
            } elseif ($token.Text -eq 'do') {
                if ($pendingLoopDo -gt 0) { $pendingLoopDo-- } else { $blockDepth++ }
            } elseif ($token.Text -in @('end', 'until')) {
                if ($blockDepth -gt 0) { $blockDepth-- }
            }
        }

        $isImmediateAssignment = $token.Kind -eq 'identifier' -and $token.Text -ceq 'MOD_VERSION' -and
            $i + 1 -lt $tokens.Count -and $tokens[$i + 1].Kind -eq 'symbol' -and
            $tokens[$i + 1].Text -eq '=' -and
            -not ($i + 2 -lt $tokens.Count -and $tokens[$i + 2].Kind -eq 'symbol' -and
                $tokens[$i + 2].Text -eq '=')
        $isListAssignment = $token.Kind -eq 'identifier' -and $token.Text -ceq 'MOD_VERSION' -and
            (Test-PromotionLuaAssignmentTail -Tokens $tokens -VersionIndex $i)
        $isFunctionBinding = $token.Kind -eq 'identifier' -and $token.Text -ceq 'MOD_VERSION' -and
            $i -gt 0 -and $tokens[$i - 1].Kind -eq 'identifier' -and
            $tokens[$i - 1].Text -ceq 'function'
        $isNamedBinding = $token.Kind -eq 'identifier' -and $token.Text -ceq 'MOD_VERSION' -and
            (Test-PromotionLuaNamedBinding -Tokens $tokens -VersionIndex $i)
        $isParameterBinding = $token.Kind -eq 'identifier' -and $token.Text -ceq 'MOD_VERSION' -and
            (Test-PromotionLuaFunctionParameterBinding -Tokens $tokens -VersionIndex $i)
        if ($isImmediateAssignment -or $isListAssignment -or $isFunctionBinding -or
                $isNamedBinding -or $isParameterBinding) {
            $isMember = Test-PromotionLuaMemberIdentifier -Tokens $tokens -IdentifierIndex $i
            if (-not $isMember) {
                [void]$directAssignments.Add($token)
                $isLocal = $i -gt 0 -and $tokens[$i - 1].Kind -eq 'identifier' -and
                    $tokens[$i - 1].Text -ceq 'local'
                if ($isImmediateAssignment -and $isLocal -and $blockDepth -eq 0 -and $i + 2 -lt $tokens.Count) {
                    $localToken = $tokens[$i - 1]
                    $valueToken = $tokens[$i + 2]
                    $sameLine = $localToken.Line -eq $token.Line -and
                        $tokens[$i + 1].Line -eq $token.Line -and $valueToken.Line -eq $token.Line
                    $lineStartsHere = $i -lt 2 -or $tokens[$i - 2].Line -lt $token.Line
                    $afterIndex = $i + 3
                    if ($afterIndex -lt $tokens.Count -and
                            $tokens[$afterIndex].Kind -eq 'symbol' -and
                            $tokens[$afterIndex].Text -eq ';' -and
                            $tokens[$afterIndex].Line -eq $token.Line) {
                        $afterIndex++
                    }
                    $lineEndsHere = $afterIndex -ge $tokens.Count -or
                        $tokens[$afterIndex].Line -gt $token.Line
                    $continuation = $afterIndex -lt $tokens.Count -and
                        $tokens[$afterIndex].Text -in @('.', '+', '-', '*', '/', '%', '^', 'and', 'or', '(', '[')
                    if ($sameLine -and $lineStartsHere -and $lineEndsHere -and -not $continuation -and
                            $valueToken.Kind -eq 'short-string' -and $valueToken.Quote -ceq '"' -and
                            -not $valueToken.HasEscape) {
                        [void]$candidates.Add([pscustomobject]@{
                            Version = "$($valueToken.Value)"
                            Line = $token.Line
                        })
                    }
                }
            }
        }
    }

    if ($candidates.Count -eq 0) {
        if ($directAssignments.Count -gt 0) {
            throw "$SourceLabel has MOD_VERSION assignment text but no canonical top-level local MOD_VERSION = `"MAJOR.MINOR.PATCH[-suffix]`" declaration"
        }
        throw "$SourceLabel has no canonical MOD_VERSION declaration"
    }
    if ($candidates.Count -ne 1) {
        throw "$SourceLabel has duplicate or ambiguous canonical MOD_VERSION declarations"
    }
    if ($directAssignments.Count -ne 1) {
        throw "$SourceLabel reassigns or ambiguously redeclares MOD_VERSION"
    }
    $version = "$($candidates[0].Version)"
    if ($version -notmatch $versionPattern) {
        throw "$SourceLabel has invalid canonical MOD_VERSION '$version'"
    }
    return $version
}
