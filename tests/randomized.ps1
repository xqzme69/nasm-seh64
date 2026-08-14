[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Nasm,

    [Parameter(Mandatory)]
    [string] $LlvmReadObj,

    [Parameter(Mandatory)]
    [string] $IncludeRoot,

    [Parameter(Mandatory)]
    [string] $Build,

    [ValidateRange(1, 20000)]
    [int] $Cases = 512,

    [int] $Seed = 0x5e6402
)

$ErrorActionPreference = 'Stop'
$includeRoot = [IO.Path]::TrimEndingDirectorySeparator(
    [IO.Path]::GetFullPath($IncludeRoot)
) + [IO.Path]::DirectorySeparatorChar

$gprs = @('rbx', 'rbp', 'rsi', 'rdi', 'r12', 'r13', 'r14', 'r15')
$xmms = 6..15 | ForEach-Object { "xmm$_" }
$random = [Random]::new($Seed)
$source = [Text.StringBuilder]::new()
$expected = @{}
$comdatCases = 0

function Select-RandomItems {
    param(
        [string[]] $Items,
        [int] $Count,
        [Random] $Generator
    )

    $copy = [Collections.Generic.List[string]]::new()
    foreach ($item in $Items) {
        $copy.Add($item)
    }

    for ($index = $copy.Count - 1; $index -gt 0; --$index) {
        $other = $Generator.Next($index + 1)
        $value = $copy[$index]
        $copy[$index] = $copy[$other]
        $copy[$other] = $value
    }

    return @($copy | Select-Object -First $Count)
}

function Get-FreeOffset {
    param(
        [int] $Width,
        [int] $Allocation,
        [Collections.IList] $Occupied,
        [Random] $Generator
    )

    $candidates = [Collections.Generic.List[int]]::new()
    for ($offset = 0; $offset + $Width -le $Allocation; $offset += $Width) {
        $free = $true
        foreach ($range in $Occupied) {
            if ($offset -lt $range.End -and $offset + $Width -gt $range.Begin) {
                $free = $false
                break
            }
        }
        if ($free) {
            $candidates.Add($offset)
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }
    return $candidates[$Generator.Next($candidates.Count)]
}

function Get-PushLength {
    param([string] $Register)

    if ($Register -match '^r1[2-5]$') {
        return 2
    }
    return 1
}

function Get-AllocationLength {
    param([int] $Size)

    if ($Size -le 127) {
        return 4
    }
    return 7
}

function Get-FrameLength {
    param([int] $Offset)

    if ($Offset -eq 0) {
        return 3
    }
    if ($Offset -le 127) {
        return 5
    }
    return 8
}

function Get-GprSaveLength {
    param([int] $Offset)

    if ($Offset -eq 0) {
        return 4
    }
    if ($Offset -le 127) {
        return 5
    }
    return 8
}

function Get-XmmSaveLength {
    param(
        [string] $Register,
        [int] $Offset
    )

    $length = if ($Offset -eq 0) { 5 } elseif ($Offset -le 127) { 6 } else { 9 }
    if ([int]($Register.Substring(3)) -ge 8) {
        $length++
    }
    return $length
}

function Add-Operation {
    param(
        [Collections.Generic.List[object]] $Operations,
        [int] $Offset,
        [string] $Text,
        [int] $Slots
    )

    $Operations.Add([pscustomobject]@{
        Offset = $Offset
        Text = $Text
        Slots = $Slots
    })
}

$null = $source.AppendLine('bits 64')
$null = $source.AppendLine('default rel')
$null = $source.AppendLine()
$null = $source.AppendLine('%include "seh64.inc"')
$null = $source.AppendLine()
$null = $source.AppendLine('section .text')

for ($caseIndex = 0; $caseIndex -lt $Cases; ++$caseIndex) {
    $name = 'seh64_random_{0:d5}' -f $caseIndex
    $isComdat = ($caseIndex % 97) -eq 0
    if ($isComdat) {
        $comdatCases++
    }

    if ($caseIndex -eq 0) {
        $pushes = @('r12')
        $allocation = 128
    }
    elseif ($caseIndex -eq 1) {
        $pushes = @()
        $allocation = 136
    }
    elseif ($caseIndex -eq 2) {
        $pushes = @('rbp', 'r15')
        $allocation = 0x108
    }
    elseif ($caseIndex -eq 3) {
        $pushes = @('r13')
        $allocation = 0
    }
    else {
        $pushCount = $random.Next(4)
        $withAllocation = $random.Next(100) -lt 85
        if (-not $withAllocation -and $pushCount -gt 0 -and ($pushCount % 2) -eq 0) {
            $pushCount = 1 + 2 * $random.Next(2)
        }
        $pushes = @(Select-RandomItems $gprs $pushCount $random)

        if ($withAllocation) {
            $base = if (($pushes.Count % 2) -eq 0) { 8 } else { 16 }
            $allocation = $base + 16 * $random.Next(64)
        }
        else {
            $allocation = 0
        }
    }

    $hasFrame = $allocation -gt 0 -and $pushes.Count -gt 0 -and
        ($caseIndex -eq 2 -or $random.Next(100) -lt 45)
    $frameRegister = $null
    $frameOffset = 0
    if ($hasFrame) {
        $frameRegister = if ($caseIndex -eq 2) { 'rbp' } else { $pushes[$random.Next($pushes.Count)] }
        $maxFrameOffset = [Math]::Min(240, $allocation)
        $frameOffset = if ($caseIndex -eq 2) {
            240
        }
        else {
            $frameSlots = [Math]::Floor($maxFrameOffset / 16)
            16 * $random.Next([int]$frameSlots + 1)
        }
    }

    $occupied = [Collections.Generic.List[object]]::new()
    $saves = [Collections.Generic.List[object]]::new()
    if ($allocation -gt 0) {
        $availableGprs = @($gprs | Where-Object { $_ -notin $pushes })
        $gprCount = [Math]::Min($availableGprs.Count, $random.Next(3))
        foreach ($register in @(Select-RandomItems $availableGprs $gprCount $random)) {
            $offset = Get-FreeOffset 8 $allocation $occupied $random
            if ($null -eq $offset) {
                break
            }
            $occupied.Add([pscustomobject]@{ Begin = $offset; End = $offset + 8 })
            $saves.Add([pscustomobject]@{ Kind = 'gpr'; Register = $register; Offset = $offset; Width = 8 })
        }

        $xmmCount = $random.Next(3)
        foreach ($register in @(Select-RandomItems $xmms $xmmCount $random)) {
            $offset = Get-FreeOffset 16 $allocation $occupied $random
            if ($null -eq $offset) {
                break
            }
            $occupied.Add([pscustomobject]@{ Begin = $offset; End = $offset + 16 })
            $saves.Add([pscustomobject]@{ Kind = 'xmm'; Register = $register; Offset = $offset; Width = 16 })
        }

        for ($index = $saves.Count - 1; $index -gt 0; --$index) {
            $other = $random.Next($index + 1)
            $value = $saves[$index]
            $saves[$index] = $saves[$other]
            $saves[$other] = $value
        }
    }

    $operations = [Collections.Generic.List[object]]::new()
    $pc = 0
    $slotCount = 0

    $null = $source.AppendLine()
    $null = $source.AppendLine("global $name")
    $procMacro = if ($isComdat) { 'SEH_PROC_COMDAT' } else { 'SEH_PROC' }
    $null = $source.AppendLine("$procMacro $name")

    foreach ($register in $pushes) {
        $null = $source.AppendLine("    SEH_PUSHREG $register")
        $pc += Get-PushLength $register
        Add-Operation $operations $pc ('PUSH_NONVOL reg={0}' -f $register.ToUpperInvariant()) 1
        $slotCount++
    }

    if ($allocation -gt 0) {
        $null = $source.AppendLine(('    SEH_ALLOCSTACK 0x{0:x}' -f $allocation))
        $pc += Get-AllocationLength $allocation
        $kind = if ($allocation -le 128) { 'ALLOC_SMALL' } else { 'ALLOC_LARGE' }
        $slots = if ($allocation -le 128) { 1 } else { 2 }
        Add-Operation $operations $pc ("$kind size=$allocation") $slots
        $slotCount += $slots
    }

    if ($hasFrame) {
        $null = $source.AppendLine(('    SEH_SETFRAME {0}, 0x{1:x}' -f $frameRegister, $frameOffset))
        $pc += Get-FrameLength $frameOffset
        Add-Operation $operations $pc ('SET_FPREG reg={0}, offset=0x{1:X}' -f
            $frameRegister.ToUpperInvariant(), $frameOffset) 1
        $slotCount++
    }

    foreach ($save in $saves) {
        if ($save.Kind -eq 'gpr') {
            $null = $source.AppendLine(('    SEH_SAVEREG {0}, 0x{1:x}' -f $save.Register, $save.Offset))
            $pc += Get-GprSaveLength $save.Offset
            Add-Operation $operations $pc ('SAVE_NONVOL reg={0}, offset=0x{1:X}' -f
                $save.Register.ToUpperInvariant(), $save.Offset) 2
            $slotCount += 2
        }
        else {
            $null = $source.AppendLine(('    SEH_SAVEXMM {0}, 0x{1:x}' -f $save.Register, $save.Offset))
            $pc += Get-XmmSaveLength $save.Register $save.Offset
            Add-Operation $operations $pc ('SAVE_XMM128 reg={0}, offset=0x{1:X}' -f
                $save.Register.ToUpperInvariant(), $save.Offset) 2
            $slotCount += 2
        }
    }

    $null = $source.AppendLine('    SEH_ENDPROLOG')
    $null = $source.AppendLine()
    for ($index = $saves.Count - 1; $index -ge 0; --$index) {
        $save = $saves[$index]
        if ($save.Kind -eq 'gpr') {
            $null = $source.AppendLine(('    mov {0}, [rsp + 0x{1:x}]' -f $save.Register, $save.Offset))
        }
        else {
            $null = $source.AppendLine(('    movdqa {0}, [rsp + 0x{1:x}]' -f $save.Register, $save.Offset))
        }
    }
    if ($allocation -gt 0) {
        $null = $source.AppendLine(('    add rsp, 0x{0:x}' -f $allocation))
    }
    for ($index = $pushes.Count - 1; $index -ge 0; --$index) {
        $null = $source.AppendLine("    pop $($pushes[$index])")
    }
    $null = $source.AppendLine('    ret')
    $null = $source.AppendLine('SEH_ENDPROC')

    $expected[$name] = [pscustomobject]@{
        Name = $name
        PrologSize = $pc
        FrameRegister = if ($hasFrame) { $frameRegister.ToUpperInvariant() } else { '-' }
        FrameOffset = if ($hasFrame) { [int]($frameOffset / 16) } else { -1 }
        SlotCount = $slotCount
        Operations = $operations
    }
}

New-Item -ItemType Directory -Force -Path $Build | Out-Null
$assembly = Join-Path $Build 'randomized.asm'
$object = Join-Path $Build 'randomized.obj'
[IO.File]::WriteAllText($assembly, $source.ToString(), [Text.UTF8Encoding]::new($false))

$nasmOutput = & $Nasm -f win64 -Wall -Werror "-I$includeRoot" -o $object $assembly 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "NASM rejected randomized seed 0x$($Seed.ToString('x8'))`n$($nasmOutput | Out-String)"
}

$readOutput = & $LlvmReadObj --unwind $object 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "llvm-readobj rejected randomized.obj`n$($readOutput | Out-String)"
}

$actual = @{}
$block = $null
$depth = 0
foreach ($line in $readOutput) {
    if ($null -eq $block) {
        if ($line -eq '  RuntimeFunction {') {
            $block = [Collections.Generic.List[string]]::new()
            $depth = 1
        }
        continue
    }

    $block.Add($line)
    $depth += ([regex]::Matches($line, '\{')).Count
    $depth -= ([regex]::Matches($line, '\}')).Count
    if ($depth -ne 0) {
        continue
    }

    $text = $block -join "`n"
    $nameMatch = [regex]::Match($text, '(?m)^\s+StartAddress: (?<name>seh64_random_[0-9]+)\b')
    if ($nameMatch.Success) {
        $name = $nameMatch.Groups['name'].Value
        $opMatches = [regex]::Matches($text, '(?m)^\s+0x(?<offset>[0-9A-F]+): (?<text>.+)$')
        $ops = [Collections.Generic.List[object]]::new()
        foreach ($match in $opMatches) {
            $ops.Add([pscustomobject]@{
                Offset = [Convert]::ToInt32($match.Groups['offset'].Value, 16)
                Text = $match.Groups['text'].Value.Trim()
            })
        }

        $prolog = [regex]::Match($text, '(?m)^\s+PrologSize: (?<value>[0-9]+)$')
        $frameRegister = [regex]::Match($text, '(?m)^\s+FrameRegister: (?<value>\S+)')
        $frameOffset = [regex]::Match($text, '(?m)^\s+FrameOffset: (?<value>\S+)')
        $slots = [regex]::Match($text, '(?m)^\s+UnwindCodeCount: (?<value>[0-9]+)$')
        if (-not ($prolog.Success -and $frameRegister.Success -and $frameOffset.Success -and $slots.Success)) {
            throw "incomplete llvm-readobj block for $name"
        }
        if ($actual.ContainsKey($name)) {
            throw "duplicate llvm-readobj block for $name"
        }

        $actual[$name] = [pscustomobject]@{
            PrologSize = [int]$prolog.Groups['value'].Value
            FrameRegister = $frameRegister.Groups['value'].Value
            FrameOffset = if ($frameOffset.Groups['value'].Value -eq '-') {
                -1
            }
            else {
                [Convert]::ToInt32($frameOffset.Groups['value'].Value.Substring(2), 16)
            }
            SlotCount = [int]$slots.Groups['value'].Value
            Operations = $ops
        }
    }

    $block = $null
}

if ($actual.Count -ne $Cases) {
    throw "randomized seed 0x$($Seed.ToString('x8')): expected $Cases runtime functions, got $($actual.Count)"
}

foreach ($name in $expected.Keys) {
    if (-not $actual.ContainsKey($name)) {
        throw "randomized seed 0x$($Seed.ToString('x8')): missing $name"
    }

    $want = $expected[$name]
    $got = $actual[$name]
    foreach ($field in 'PrologSize', 'FrameRegister', 'FrameOffset', 'SlotCount') {
        if ($want.$field -ne $got.$field) {
            throw "randomized seed 0x$($Seed.ToString('x8')) ${name}: $field expected $($want.$field), got $($got.$field)"
        }
    }

    $wantOps = @($want.Operations)
    [Array]::Reverse($wantOps)
    if ($wantOps.Count -ne $got.Operations.Count) {
        throw "randomized seed 0x$($Seed.ToString('x8')) ${name}: expected $($wantOps.Count) operations, got $($got.Operations.Count)"
    }
    for ($index = 0; $index -lt $wantOps.Count; ++$index) {
        if ($wantOps[$index].Offset -ne $got.Operations[$index].Offset -or
            $wantOps[$index].Text -ne $got.Operations[$index].Text) {
            throw "randomized seed 0x$($Seed.ToString('x8')) $name op $index expected 0x$($wantOps[$index].Offset.ToString('x')) $($wantOps[$index].Text), got 0x$($got.Operations[$index].Offset.ToString('x')) $($got.Operations[$index].Text)"
        }
    }
}

Write-Host ('PASS randomized: {0} prologues, {1} COMDAT, seed 0x{2}' -f
    $Cases, $comdatCases, $Seed.ToString('x8'))
