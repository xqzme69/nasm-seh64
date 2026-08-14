[CmdletBinding()]
param(
    [string] $Nasm,
    [string] $Yasm,
    [string] $LlvmReadObj,
    [string] $VcVars64,
    [ValidateRange(0, 20000)]
    [int] $RandomCases = 512,
    [int] $RandomSeed = 0x5e6402,
    [switch] $StaticOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$includeRoot = [IO.Path]::TrimEndingDirectorySeparator($root) + [IO.Path]::DirectorySeparatorChar
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$build = Join-Path $tempRoot ("nasm-seh64-tests-{0}" -f $PID)

function Resolve-Tool {
    param(
        [string] $ExplicitPath,
        [string] $CommandName,
        [string[]] $KnownPaths
    )

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "tool not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($path in $KnownPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    throw "tool not found: $CommandName"
}

function Find-Tool {
    param(
        [string] $ExplicitPath,
        [string] $CommandName,
        [string[]] $KnownPaths
    )

    if ($ExplicitPath) {
        return Resolve-Tool $ExplicitPath $CommandName $KnownPaths
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($path in $KnownPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    return $null
}

function Invoke-Nasm {
    param(
        [string] $Source,
        [string] $Object,
        [bool] $ShouldPass,
        [string] $ExpectedError
    )

    $output = & $script:NasmPath -f win64 -Wall -Werror "-I$script:includeRoot" -o $Object $Source 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($ShouldPass -and $exitCode -ne 0) {
        throw "NASM rejected $Source`n$text"
    }
    if (-not $ShouldPass -and $exitCode -eq 0) {
        throw "NASM accepted invalid fixture: $Source"
    }
    if (-not $ShouldPass -and $text -notlike "*$ExpectedError*") {
        throw "wrong diagnostic for $Source`nexpected: $ExpectedError`nactual: $text"
    }
}

function Read-Unwind {
    param([string] $Object)

    $output = & $script:ReadObjPath --sections --relocations --unwind $Object 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readobj failed for $Object`n$($output | Out-String)"
    }
    return ($output | Out-String)
}

function Assert-Match {
    param(
        [string] $Text,
        [string] $Pattern,
        [string] $Message
    )

    if ($Text -notmatch $Pattern) {
        throw "$Message`nmissing pattern: $Pattern"
    }
}

function Get-UnwindSignature {
    param([string] $Text)

    $lines = [regex]::Matches(
        $Text,
        '(?m)^\s+(?:PrologSize|FrameRegister|FrameOffset|UnwindCodeCount|0x[0-9A-F]+:).*$'
    )
    return (($lines | ForEach-Object { $_.Value.Trim() }) -join "`n")
}

function Resolve-VcVars64 {
    param([string] $ExplicitPath)

    if (-not $IsWindows) {
        throw 'MSVC x64 tools are only available on Windows'
    }

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "vcvars64.bat not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and $install) {
            $candidate = Join-Path ($install | Select-Object -First 1) 'VC\Auxiliary\Build\vcvars64.bat'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    $knownPaths = @(
        'C:\Program Files\Microsoft Visual Studio\18\Professional\VC\Auxiliary\Build\vcvars64.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
    )
    foreach ($path in $knownPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    if (Get-Command 'cl.exe' -ErrorAction SilentlyContinue) {
        return $null
    }

    throw 'MSVC x64 tools not found; install them or run tests\run.ps1 -StaticOnly'
}

function Invoke-RuntimeTest {
    $runtimeObject = Join-Path $script:build 'unwind_fixture.obj'
    $cObject = Join-Path $script:build 'unwind_test.obj'
    $executable = Join-Path $script:build 'unwind_test.exe'
    $assembly = Join-Path $script:root 'tests/runtime/unwind_fixture.asm'
    $source = Join-Path $script:root 'tests/runtime/unwind_test.c'

    Invoke-Nasm $assembly $runtimeObject $true ''
    $vcvars = Resolve-VcVars64 $script:VcVars64

    if ($vcvars) {
        $compile = 'call "{0}" >nul && cl.exe /nologo /W4 /WX /O2 /std:c11 /Fo:"{1}" /Fe:"{2}" "{3}" "{4}"' -f `
            $vcvars, $cObject, $executable, $source, $runtimeObject
        $compilerOutput = & $env:ComSpec /d /s /c $compile 2>&1
    }
    else {
        $compilerOutput = & cl.exe /nologo /W4 /WX /O2 /std:c11 "/Fo:$cObject" "/Fe:$executable" $source $runtimeObject 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "MSVC failed to build the runtime test`n$($compilerOutput | Out-String)"
    }

    $runtimeOutput = & $executable 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Windows unwind test failed`n$($runtimeOutput | Out-String)"
    }
    $runtimeText = ($runtimeOutput | Out-String).Trim()
    Assert-Match $runtimeText '^PASS runtime:' 'runtime test did not report a complete pass'
    Write-Host $runtimeText

    $clangCl = Find-Tool '' 'clang-cl.exe' @('C:\Program Files\LLVM\bin\clang-cl.exe')
    if ($clangCl -and $vcvars) {
        $clangObject = Join-Path $script:build 'unwind_test-clang.obj'
        $lldExecutable = Join-Path $script:build 'unwind_test-lld.exe'
        $clangBuild = 'call "{0}" >nul && "{1}" /nologo /W4 /WX /O2 /std:c11 /c /Fo:"{2}" "{3}" && "{1}" /nologo -fuse-ld=lld /Fe:"{4}" "{2}" "{5}"' -f `
            $vcvars, $clangCl, $clangObject, $source, $lldExecutable, $runtimeObject
        $clangOutput = & $env:ComSpec /d /s /c $clangBuild 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "clang-cl/lld-link failed to build the runtime test`n$($clangOutput | Out-String)"
        }

        $lldOutput = & $lldExecutable 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "lld-linked unwind test failed`n$($lldOutput | Out-String)"
        }
        Assert-Match ($lldOutput | Out-String) '^PASS runtime:' 'lld-linked runtime test did not report a complete pass'
        Write-Host 'PASS linkers: link.exe and lld-link'
    }
    else {
        Write-Host 'SKIP lld-link: clang-cl or an initialized MSVC environment was not found'
    }
}

function Assert-ComdatImage {
    param(
        [string] $Image,
        [string] $Linker
    )

    $unwind = & $script:ReadObjPath --unwind $Image 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readobj failed for $Linker COMDAT image`n$unwind"
    }
    if ([regex]::Matches($unwind, 'RuntimeFunction \{').Count -ne 4) {
        throw "$Linker did not retain exactly four COMDAT runtime functions`n$unwind"
    }
    Assert-Match $unwind 'ALLOC_SMALL size=40' "$Linker discarded the referenced COMDAT function"
    if ([regex]::Matches($unwind, 'ChainInfo').Count -ne 2) {
        throw "$Linker discarded a level of associated chained unwind metadata`n$unwind"
    }
    Assert-Match $unwind 'SAVE_NONVOL reg=R12, offset=0x10' "$Linker lost chained unwind metadata"
    Assert-Match $unwind 'SAVE_NONVOL reg=R13, offset=0x18' "$Linker lost multi-level chained unwind metadata"
    if ($unwind -match 'ALLOC_SMALL size=56') {
        throw "$Linker retained the unreferenced COMDAT function or its unwind metadata"
    }
}

function Invoke-ComdatLinkTests {
    param([string] $Object)

    $tested = 0
    $lldLink = if ($IsWindows) {
        Find-Tool '' 'lld-link.exe' @('C:\Program Files\LLVM\bin\lld-link.exe')
    }
    else {
        $null
    }
    if ($lldLink) {
        $lldImage = Join-Path $script:build 'comdat-lld.exe'
        $lldOutput = & $lldLink /entry:seh64_comdat_entry /subsystem:console /nodefaultlib /opt:ref "/out:$lldImage" $Object 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "lld-link failed the COMDAT fixture`n$($lldOutput | Out-String)"
        }
        Assert-ComdatImage $lldImage 'lld-link'
        $tested++
    }
    else {
        Write-Host 'SKIP COMDAT linker: lld-link.exe was not found'
    }

    $vcvars = $null
    try {
        $vcvars = Resolve-VcVars64 $script:VcVars64
    }
    catch {
        if ($script:VcVars64) {
            throw
        }
    }

    $linkImage = Join-Path $script:build 'comdat-link.exe'
    $linkAttempted = $false
    if ($vcvars) {
        $linkAttempted = $true
        $link = 'call "{0}" >nul && link.exe /nologo /entry:seh64_comdat_entry /subsystem:console /nodefaultlib /opt:ref /out:"{1}" "{2}"' -f `
            $vcvars, $linkImage, $Object
        $linkOutput = & $env:ComSpec /d /s /c $link 2>&1
        $linkExitCode = $LASTEXITCODE
    }
    elseif (Get-Command 'link.exe' -ErrorAction SilentlyContinue) {
        $linkAttempted = $true
        $linkOutput = & link.exe /nologo /entry:seh64_comdat_entry /subsystem:console /nodefaultlib /opt:ref "/out:$linkImage" $Object 2>&1
        $linkExitCode = $LASTEXITCODE
    }

    if ($linkAttempted) {
        if ($linkExitCode -ne 0) {
            throw "link.exe failed the COMDAT fixture`n$($linkOutput | Out-String)"
        }
        Assert-ComdatImage $linkImage 'link.exe'
        $tested++
    }
    else {
        Write-Host 'SKIP COMDAT linker: link.exe environment was not found'
    }

    if ($tested -gt 0) {
        Write-Host ("PASS COMDAT: associative metadata and dead stripping with {0} linker(s)" -f $tested)
    }
    else {
        Write-Host 'SKIP COMDAT link: no PE linker was found'
    }
}

function Invoke-RandomizedTests {
    if ($script:RandomCases -eq 0) {
        return
    }

    $runner = Join-Path $script:root 'tests/randomized.ps1'
    $randomBuild = Join-Path $script:build 'randomized'
    $pwsh = (Get-Process -Id $PID).Path
    $output = & $pwsh -NoProfile -File $runner `
        -Nasm $script:NasmPath `
        -LlvmReadObj $script:ReadObjPath `
        -IncludeRoot $script:root `
        -Build $randomBuild `
        -Cases $script:RandomCases `
        -Seed $script:RandomSeed 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "randomized unwind validation failed`n$($output | Out-String)"
    }
    Write-Host (($output | Out-String).Trim())
}

function Invoke-ReferenceTests {
    param([string] $NasmUnwind)

    $expected = Get-UnwindSignature $NasmUnwind
    $tested = 0
    $yasmCommand = if ($IsWindows) { 'yasm.exe' } else { 'yasm' }
    $yasmKnownPaths = if ($IsWindows) { @('C:\Strawberry\c\bin\yasm.exe') } else { @() }
    $yasmPath = Find-Tool $script:Yasm $yasmCommand $yasmKnownPaths

    if ($yasmPath) {
        $yasmObject = Join-Path $script:build 'reference-yasm.obj'
        $yasmSource = Join-Path $script:root 'tests/reference/yasm.asm'
        $yasmOutput = & $yasmPath -f win64 -o $yasmObject $yasmSource 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Yasm rejected its reference fixture`n$($yasmOutput | Out-String)"
        }
        $actual = Get-UnwindSignature (Read-Unwind $yasmObject)
        if ($actual -ne $expected) {
            throw "Yasm reference differs from seh64.inc`nexpected:`n$expected`nactual:`n$actual"
        }
        $tested++
    }
    else {
        Write-Host 'SKIP reference: yasm.exe was not found'
    }

    $vcvars = $null
    try {
        $vcvars = Resolve-VcVars64 $script:VcVars64
    }
    catch {
        if ($script:VcVars64) {
            throw
        }
    }

    if ($vcvars) {
        $masmObject = Join-Path $script:build 'reference-masm.obj'
        $masmSource = Join-Path $script:root 'tests/reference/masm.asm'
        $masmBuild = 'call "{0}" >nul && ml64.exe /nologo /W3 /WX /Fo"{1}" /c "{2}"' -f `
            $vcvars, $masmObject, $masmSource
        $masmOutput = & $env:ComSpec /d /s /c $masmBuild 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "MASM rejected its reference fixture`n$($masmOutput | Out-String)"
        }
        $actual = Get-UnwindSignature (Read-Unwind $masmObject)
        if ($actual -ne $expected) {
            throw "MASM reference differs from seh64.inc`nexpected:`n$expected`nactual:`n$actual"
        }
        $tested++
    }
    else {
        Write-Host 'SKIP reference: ml64.exe environment was not found'
    }

    if ($tested -gt 0) {
        Write-Host ("PASS differential: {0} reference assembler(s)" -f $tested)
    }
}

$nasmCommand = if ($IsWindows) { 'nasm.exe' } else { 'nasm' }
$readObjCommand = if ($IsWindows) { 'llvm-readobj.exe' } else { 'llvm-readobj' }
$NasmPath = Resolve-Tool $Nasm $nasmCommand @(
    'C:\Strawberry\c\bin\nasm.exe',
    'C:\Program Files\NASM\nasm.exe'
)
$ReadObjPath = Resolve-Tool $LlvmReadObj $readObjCommand @(
    'C:\Program Files\LLVM\bin\llvm-readobj.exe'
)

New-Item -ItemType Directory -Force -Path $build | Out-Null

try {
    $valid = @(
        @{ Source = 'examples/basic.asm'; Object = 'basic.obj' },
        @{ Source = 'tests/fixtures/valid/handlers.asm'; Object = 'handlers.obj' },
        @{ Source = 'tests/fixtures/valid/chain.asm'; Object = 'chain.obj' },
        @{ Source = 'tests/fixtures/valid/machframe.asm'; Object = 'machframe.obj' },
        @{ Source = 'tests/fixtures/valid/home_space.asm'; Object = 'home_space.obj' },
        @{ Source = 'tests/fixtures/valid/registers.asm'; Object = 'registers.obj' },
        @{ Source = 'tests/fixtures/valid/multichain.asm'; Object = 'multichain.obj' },
        @{ Source = 'tests/fixtures/valid/include_twice.asm'; Object = 'include_twice.obj' },
        @{ Source = 'tests/fixtures/valid/custom_probe.asm'; Object = 'custom_probe.obj' },
        @{ Source = 'tests/fixtures/valid/encodings.asm'; Object = 'encodings.obj' },
        @{ Source = 'tests/fixtures/valid/comdat.asm'; Object = 'comdat.obj' }
    )

    foreach ($fixture in $valid) {
        Invoke-Nasm (Join-Path $root $fixture.Source) (Join-Path $build $fixture.Object) $true ''
    }

    $basic = Read-Unwind (Join-Path $build 'basic.obj')
    Assert-Match $basic 'FrameRegister: RBP' 'basic fixture lost its frame register'
    Assert-Match $basic 'ALLOC_SMALL size=72' 'basic fixture lost its stack allocation'
    Assert-Match $basic 'SAVE_NONVOL reg=RSI, offset=0x30' 'basic fixture lost its RSI save'
    Assert-Match $basic 'SAVE_XMM128 reg=XMM6, offset=0x10' 'basic fixture lost its XMM6 save'

    $handlers = Read-Unwind (Join-Path $build 'handlers.obj')
    Assert-Match $handlers 'ExceptionHandler' 'handler fixture lost UNW_FLAG_EHANDLER'
    Assert-Match $handlers 'TerminateHandler' 'handler fixture lost UNW_FLAG_UHANDLER'
    Assert-Match $handlers 'Handler: seh64_test_handler' 'handler RVA points at the wrong symbol'
    $handlerHex = & $ReadObjPath --hex-dump=.xdata (Join-Path $build 'handlers.obj') 2>&1 | Out-String
    Assert-Match $handlerHex '36484553' 'handler payload was not emitted after the handler RVA'

    $chain = Read-Unwind (Join-Path $build 'chain.obj')
    Assert-Match $chain 'ChainInfo' 'chained fixture lost UNW_FLAG_CHAININFO'
    Assert-Match $chain 'SAVE_NONVOL reg=R12, offset=0x10' 'chained fixture lost its shrink-wrapped R12 save'
    Assert-Match $chain 'StartAddress: seh64_chain_parent' 'chained fixture points at the wrong primary range'

    $machframe = Read-Unwind (Join-Path $build 'machframe.obj')
    Assert-Match $machframe 'PUSH_MACHFRAME errcode=yes' 'machine-frame fixture has the wrong OpInfo'
    Assert-Match $machframe 'SAVE_NONVOL reg=RBX, offset=0x0' 'machine-frame chain lost its backed GPR save'

    $homeSpace = Read-Unwind (Join-Path $build 'home_space.obj')
    Assert-Match $homeSpace 'SAVE_NONVOL reg=RBX, offset=0x10' 'GPR save in caller home space was lost'
    Assert-Match $homeSpace 'SAVE_XMM128 reg=XMM6, offset=0x20' 'XMM save in caller home space was lost'

    $registers = Read-Unwind (Join-Path $build 'registers.obj')
    foreach ($register in @('RBX', 'RBP', 'RSI', 'RDI', 'R12', 'R13', 'R14', 'R15')) {
        Assert-Match $registers "PUSH_NONVOL reg=$register" "register map is wrong for $register"
    }
    foreach ($number in 6..15) {
        Assert-Match $registers "SAVE_XMM128 reg=XMM$number," "register map is wrong for XMM$number"
    }
    Assert-Match $registers 'FrameRegister: R13' 'high frame-register encoding is wrong'
    Assert-Match $registers 'FrameOffset: 0xF' 'maximum frame-register offset is wrong'

    $multichain = Read-Unwind (Join-Path $build 'multichain.obj')
    if ([regex]::Matches($multichain, 'ChainInfo').Count -ne 2) {
        throw 'multi-level chain does not contain exactly two chained ranges'
    }
    Assert-Match $multichain 'SAVE_NONVOL reg=R12, offset=0x0' 'first chained save is wrong'
    Assert-Match $multichain 'SAVE_NONVOL reg=R13, offset=0x8' 'second chained save is wrong'

    $includeTwice = Read-Unwind (Join-Path $build 'include_twice.obj')
    Assert-Match $includeTwice 'ALLOC_SMALL size=40' 'include guard changed the generated unwind record'

    $customProbe = Read-Unwind (Join-Path $build 'custom_probe.obj')
    Assert-Match $customProbe 'ALLOC_LARGE size=4096' 'custom-probe allocation has the wrong unwind form'
    if ($customProbe -match '__chkstk') {
        throw 'custom stack-probe fixture still references __chkstk'
    }
    $customSymbols = & $ReadObjPath --symbols (Join-Path $build 'custom_probe.obj') 2>&1 | Out-String
    Assert-Match $customSymbols 'Name: local_stack_probe' 'custom stack-probe symbol is missing'

    $encodings = Read-Unwind (Join-Path $build 'encodings.obj')
    Assert-Match $encodings '(?s)Name: \.pdata.*?RawDataSize: 72' '.pdata does not contain exactly six RUNTIME_FUNCTION records'
    Assert-Match $encodings '(?s)Section \(1\) \.text \{.*?__chkstk' '__chkstk relocations escaped the .text section'
    Assert-Match $encodings 'ALLOC_SMALL size=128' '128-byte allocation did not use UWOP_ALLOC_SMALL'
    Assert-Match $encodings 'ALLOC_LARGE size=136' '136-byte allocation did not use UWOP_ALLOC_LARGE form 0'
    Assert-Match $encodings 'ALLOC_LARGE size=524280' 'last form-0 allocation boundary is wrong'
    Assert-Match $encodings 'ALLOC_LARGE size=524288' 'first form-1 allocation boundary is wrong'
    Assert-Match $encodings 'SAVE_NONVOL_FAR reg=R12, offset=0x80000' 'GPR far-save boundary is wrong'
    Assert-Match $encodings 'SAVE_XMM128_FAR reg=XMM15, offset=0x100000' 'XMM far-save boundary is wrong'
    if ([regex]::Matches($encodings, 'RuntimeFunction \{').Count -ne 6) {
        throw 'encodings fixture does not contain exactly six runtime functions'
    }

    $comdatObject = Join-Path $build 'comdat.obj'
    $comdat = Read-Unwind $comdatObject
    if ([regex]::Matches($comdat, 'RuntimeFunction \{').Count -ne 5) {
        throw 'COMDAT object does not contain all five source runtime functions'
    }
    Assert-Match $comdat 'StartAddress: seh64_comdat_chain_child' 'COMDAT chain child is missing'
    Assert-Match $comdat 'StartAddress: seh64_comdat_chain_grandchild' 'COMDAT chain grandchild is missing'
    if ([regex]::Matches($comdat, 'ChainInfo').Count -ne 2) {
        throw 'COMDAT multi-level chain lost CHAININFO'
    }
    $comdatSymbols = & $ReadObjPath --sections --symbols $comdatObject 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readobj failed to inspect COMDAT symbols`n$comdatSymbols"
    }
    if ([regex]::Matches($comdatSymbols, 'Selection: NoDuplicates').Count -ne 3) {
        throw 'SEH_PROC_COMDAT did not emit three root COMDAT code sections'
    }
    if ([regex]::Matches($comdatSymbols, 'Selection: Associative').Count -ne 7) {
        throw 'COMDAT unwind metadata or chained code has the wrong association count'
    }
    if ([regex]::Matches($comdatSymbols, 'AssocSection: \.text\$seh64').Count -ne 7) {
        throw 'COMDAT associative sections do not point at their code roots'
    }

    $invalid = @(
        @{ Source = 'alloc_unaligned.asm'; Error = 'seh64: invalid_alloc_unaligned: SEH64-E115: SEH_ALLOCSTACK 13: size must be 8-byte aligned' },
        @{ Source = 'xmm_offset_unaligned.asm'; Error = 'SEH64-E167' },
        @{ Source = 'xmm_address_unaligned.asm'; Error = 'SEH64-E169' },
        @{ Source = 'volatile_push.asm'; Error = 'SEH64-E104' },
        @{ Source = 'frame_twice.asm'; Error = 'SEH64-E123' },
        @{ Source = 'frame_unsaved.asm'; Error = 'SEH64-E126' },
        @{ Source = 'frame_unbacked.asm'; Error = 'SEH64-E129' },
        @{ Source = 'save_before_frame.asm'; Error = 'SEH64-E124' },
        @{ Source = 'prolog_too_long.asm'; Error = 'SEH64-E202' },
        @{ Source = 'operation_after_prolog.asm'; Error = 'SEH64-E101' },
        @{ Source = 'stack_unaligned.asm'; Error = 'SEH64-E204' },
        @{ Source = 'save_overlap.asm'; Error = 'SEH64-E147' },
        @{ Source = 'save_unbacked.asm'; Error = 'SEH64-E148' },
        @{ Source = 'machine_frame_overlap.asm'; Error = 'SEH64-E147' },
        @{ Source = 'save_twice.asm'; Error = 'SEH64-E143' },
        @{ Source = 'save_slot_overlap_gpr.asm'; Error = 'SEH64-E149' },
        @{ Source = 'save_slot_overlap_xmm.asm'; Error = 'SEH64-E172' },
        @{ Source = 'chain_save_slot_overlap.asm'; Error = 'SEH64-E149' },
        @{ Source = 'chain_machine_frame_overlap.asm'; Error = 'SEH64-E147' },
        @{ Source = 'chain_parent_missing.asm'; Error = 'SEH64-E012' },
        @{ Source = 'chain_handler.asm'; Error = 'SEH64-E192' },
        @{ Source = 'chain_xmm_save.asm'; Error = 'SEH64-E162' },
        @{ Source = 'handler_flags.asm'; Error = 'SEH64-E194' },
        @{ Source = 'pushframe_late.asm'; Error = 'SEH64-E183' },
        @{ Source = 'alloc_after_save.asm'; Error = 'SEH64-E113' },
        @{ Source = 'push_after_alloc.asm'; Error = 'SEH64-E103' },
        @{ Source = 'probe_config.asm'; Error = 'SEH64-E003' }
    )

    foreach ($fixture in $invalid) {
        $source = Join-Path $root (Join-Path 'tests/fixtures/invalid' $fixture.Source)
        $object = Join-Path $build ($fixture.Source -replace '\.asm$', '.obj')
        Invoke-Nasm $source $object $false $fixture.Error
    }

    Write-Host ("PASS static: {0} valid fixtures, {1} rejected fixtures" -f $valid.Count, $invalid.Count)
    Invoke-ComdatLinkTests $comdatObject
    Invoke-RandomizedTests
    Invoke-ReferenceTests $basic
    if (-not $StaticOnly) {
        Invoke-RuntimeTest
    }
    Write-Host "NASM: $NasmPath"
    Write-Host "llvm-readobj: $ReadObjPath"
}
finally {
    $resolvedBuild = [IO.Path]::GetFullPath($build)
    if ($resolvedBuild.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedBuild) -like 'nasm-seh64-tests-*') {
        Remove-Item -LiteralPath $resolvedBuild -Recurse -Force -ErrorAction SilentlyContinue
    }
}
