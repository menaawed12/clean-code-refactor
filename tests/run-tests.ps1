<#
.SYNOPSIS
    Behavioral test suite for the clean-code-refactor package (no Pester dependency).

.DESCRIPTION
    Exercises the installers end-to-end in disposable temp directories:
      fresh install, idempotent re-run, unmanaged-install skip, forced upgrade from a
      stale/unmanaged fixture (stale + nested reference removal), user-modification
      protection, dry-run (no writes), usage errors (no partial writes), paths with
      spaces and Unicode, containment against symlink redirection, user-scope installs
      with redirected homes, and JSON output shape. Then runs the bash suite when bash
      is available, and package validation.

.PARAMETER SkipBash
    Skip the bash installer test suite (for Windows-only CI jobs).
#>
[CmdletBinding()]
param(
    [switch]$SkipBash
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$installer = Join-Path $repositoryRoot 'scripts/install.ps1'
$validator = Join-Path $repositoryRoot 'scripts/validate-skill.ps1'
$bashSuite = Join-Path $repositoryRoot 'tests/install.sh.tests.sh'

$script:pass = 0
$script:fail = 0
$script:skipped = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        $script:pass++
        Write-Host "PASS: $Name"
    } else {
        $script:fail++
        Write-Host "FAIL: $Name $(if ($Detail) { "- $Detail" })" -ForegroundColor Red
    }
}

function Invoke-Installer {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer @Arguments 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $previous
    }
    return $LASTEXITCODE
}

function Invoke-InstallerOutput {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
}

function Get-TreeState {
    param([string]$Directory)
    $state = @{}
    if (-not (Test-Path -LiteralPath $Directory)) { return $state }
    foreach ($item in (Get-ChildItem -LiteralPath $Directory -Recurse -Force)) {
        $state[$item.FullName] = if ($item.PSIsContainer) { 'dir' } else { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
    }
    return $state
}

function New-TempDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ccr-test-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

$cleanup = @()
function Register-Cleanup {
    param([string]$PathValue)
    $script:cleanup += $PathValue
}

try {
    $registry = Get-Content -LiteralPath (Join-Path $repositoryRoot 'integrations/registry.json') -Raw | ConvertFrom-Json
    $version = $registry.package.version
    $powershellHost = (Get-Process -Id $PID).Path

    # ---------------------------------------------------------------- T1
    & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $validator *> $null
    Assert-True 'T1 package validation passes' ($LASTEXITCODE -eq 0)

    # ---------------------------------------------------------------- T2 fresh cursor install
    $target = New-TempDirectory; Register-Cleanup $target
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $target)
    $rulePath = Join-Path $target '.cursor/rules/clean-code-refactor.mdc'
    $ruleContent = if (Test-Path -LiteralPath $rulePath) { Get-Content -LiteralPath $rulePath -Raw } else { '' }
    $linkTargets = @([regex]::Matches($ruleContent, 'clean-code-refactor-references/([A-Za-z0-9][A-Za-z0-9._/-]*)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $missingLinks = @($linkTargets | Where-Object { -not (Test-Path -LiteralPath (Join-Path $target ".cursor/rules/clean-code-refactor-references/$_" )) })
    Assert-True 'T2 fresh cursor install exits 0' ($exitCode -eq 0)
    Assert-True 'T2 rule file exists' ((Test-Path -LiteralPath $rulePath))
    Assert-True 'T2 no double-prefixed reference links' ($ruleContent -notmatch 'clean-code-refactor-clean-code-refactor')
    Assert-True 'T2 every generated reference link resolves' ($missingLinks.Count -eq 0) ($missingLinks -join ', ')
    Assert-True 'T2 profiler tool installed' ((Test-Path -LiteralPath (Join-Path $target '.cursor/rules/clean-code-refactor-tools/profile-repository.ps1')))
    Assert-True 'T2 receipt written with version' ((Test-Path -LiteralPath (Join-Path $target '.cursor/rules/clean-code-refactor-tools/.clean-code-refactor-install.json')) -and ((Get-Content -LiteralPath (Join-Path $target '.cursor/rules/clean-code-refactor-tools/.clean-code-refactor-install.json') -Raw) -match ('"version":\s*"' + $version + '"')))

    # ---------------------------------------------------------------- T3 all project targets exist
    $target = New-TempDirectory; Register-Cleanup $target
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'all', '-TargetPath', $target)
    Assert-True 'T3 all-targets install exits 0' ($exitCode -eq 0)
    $missingTargets = @()
    foreach ($property in $registry.editors.PSObject.Properties) {
        foreach ($scopeName in @('project', 'user')) {
            $scopeDef = $property.Value.PSObject.Properties['scopes'].Value.PSObject.Properties[$scopeName]
            if (-not $scopeDef) { continue }
            if ($scopeName -eq 'user') { continue } # user destinations live outside a project root
            $destination = Join-Path $target ($scopeDef.Value.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $destination)) { $missingTargets += "$($property.Name):$scopeName" }
        }
    }
    Assert-True 'T3 every registry project target exists' ($missingTargets.Count -eq 0) ($missingTargets -join ', ')

    # ---------------------------------------------------------------- T4 idempotent re-run
    $json = Invoke-InstallerOutput -Arguments @('-Editor', 'all', '-TargetPath', $target, '-OutputFormat', 'Json')
    $plan = $null
    try { $plan = $json.Output | ConvertFrom-Json } catch { }
    Assert-True 'T4 re-run exits 0' ($json.ExitCode -eq 0)
    Assert-True 'T4 re-run reports everything up-to-date' ($null -ne $plan -and $plan.summary.upToDate -gt 0 -and $plan.summary.failed -eq 0) 'summary counts inconsistent'

    # ---------------------------------------------------------------- T5 unmanaged install is skipped without force
    $target = New-TempDirectory; Register-Cleanup $target
    $foreignDir = New-Item -ItemType Directory -Path (Join-Path $target '.cursor/rules') -Force
    $foreignPath = Join-Path $foreignDir.FullName 'clean-code-refactor.mdc'
    Set-Content -LiteralPath $foreignPath -Value 'user-owned rule content' -NoNewline
    $unrelatedPath = Join-Path $foreignDir.FullName 'team-conventions.mdc'
    Set-Content -LiteralPath $unrelatedPath -Value 'team rules' -NoNewline
    $beforeForeign = Get-Content -LiteralPath $foreignPath -Raw
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $target)
    Assert-True 'T5 unmanaged install skipped, exit 0' ($exitCode -eq 0)
    Assert-True 'T5 foreign rule untouched' ((Get-Content -LiteralPath $foreignPath -Raw) -eq $beforeForeign)
    Assert-True 'T5 unrelated rule untouched' ((Get-Content -LiteralPath $unrelatedPath -Raw) -eq 'team rules')
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $target, '-Force')
    Assert-True 'T5 force replaces unmanaged install' ($exitCode -eq 0 -and ((Get-Content -LiteralPath $foreignPath -Raw) -match 'clean-code-refactor'))

    # ---------------------------------------------------------------- T6 forced upgrade from stale unmanaged fixture
    $target = New-TempDirectory; Register-Cleanup $target
    $rulesDir = New-Item -ItemType Directory -Path (Join-Path $target '.cursor/rules/clean-code-refactor-references/references') -Force
    $referencesRoot = Split-Path -Parent $rulesDir.FullName
    Set-Content -LiteralPath (Join-Path $referencesRoot 'stale-old-file.md') -Value 'stale' -NoNewline
    Set-Content -LiteralPath (Join-Path $rulesDir.FullName 'junk.md') -Value 'nested junk' -NoNewline
    $staleRule = Join-Path (Split-Path -Parent $referencesRoot) 'clean-code-refactor.mdc'
    Set-Content -LiteralPath $staleRule -Value 'OLD BROKEN clean-code-refactor-references/language-hardening.md link (double prefix below) clean-code-refactor-clean-code-refactor-references/static-quality-rules.md' -NoNewline
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $target)
    Assert-True 'T6 stale unmanaged install skipped without force' ($exitCode -eq 0 -and (Get-Content -LiteralPath $staleRule -Raw) -match 'OLD BROKEN')
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $target, '-Force')
    $ruleContent = Get-Content -LiteralPath $staleRule -Raw
    Assert-True 'T6 forced upgrade exits 0' ($exitCode -eq 0)
    Assert-True 'T6 rule content updated' (($ruleContent -match $version) -and ($ruleContent -notmatch 'OLD BROKEN'))
    Assert-True 'T6 stale reference removed' (-not (Test-Path -LiteralPath (Join-Path $referencesRoot 'stale-old-file.md')))
    Assert-True 'T6 nested references directory removed' (-not (Test-Path -LiteralPath (Join-Path $referencesRoot 'references')))

    # ---------------------------------------------------------------- T7 user-modified owned file protection
    $target = New-TempDirectory; Register-Cleanup $target
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude', '-TargetPath', $target)
    $skillCopy = Join-Path $target '.claude/skills/clean-code-refactor/SKILL.md'
    Add-Content -LiteralPath $skillCopy -Value "`n<!-- user edit -->"
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude', '-TargetPath', $target)
    Assert-True 'T7 user modification skipped without force' (($exitCode -eq 0) -and ((Get-Content -LiteralPath $skillCopy -Raw) -match 'user edit'))
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude', '-TargetPath', $target, '-Force')
    Assert-True 'T7 force overwrites user modification' (($exitCode -eq 0) -and ((Get-Content -LiteralPath $skillCopy -Raw) -notmatch 'user edit'))

    # ---------------------------------------------------------------- T8 dry run writes nothing
    $target = New-TempDirectory; Register-Cleanup $target
    $before = Get-TreeState -Directory $target
    $result = Invoke-InstallerOutput -Arguments @('-Editor', 'all', '-TargetPath', $target, '-DryRun', '-OutputFormat', 'Json')
    $after = Get-TreeState -Directory $target
    $plan = $null
    try { $plan = $result.Output | ConvertFrom-Json } catch { }
    Assert-True 'T8 dry run exits 0 and reports dryRun' (($result.ExitCode -eq 0) -and ($null -ne $plan) -and ($plan.dryRun -eq $true))
    Assert-True 'T8 dry run changes nothing' (($before.Count -eq $after.Count) -and (-not (Compare-Object @($before.Keys) @($after.Keys))))

    # ---------------------------------------------------------------- T9 invalid editor, no partial writes
    $target = New-TempDirectory; Register-Cleanup $target
    $before = Get-TreeState -Directory $target
    $result = Invoke-InstallerOutput -Arguments @('-Editor', 'does-not-exist', '-TargetPath', $target)
    $after = Get-TreeState -Directory $target
    Assert-True 'T9 invalid editor exits 2' ($result.ExitCode -eq 2) "exit $($result.ExitCode)"
    Assert-True 'T9 invalid editor writes nothing' ($before.Count -eq $after.Count)

    # ---------------------------------------------------------------- T10 spaces and Unicode paths
    $target = New-TempDirectory; Register-Cleanup $target
    $fancy = Join-Path $target 'my project - ünïcode ✓'
    New-Item -ItemType Directory -Path $fancy -Force | Out-Null
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'cursor', '-TargetPath', $fancy)
    Assert-True 'T10 spaces and Unicode path install' (($exitCode -eq 0) -and (Test-Path -LiteralPath (Join-Path $fancy '.cursor/rules/clean-code-refactor.mdc')))

    # ---------------------------------------------------------------- T11 symlink containment
    $target = New-TempDirectory; Register-Cleanup $target
    $outside = New-TempDirectory; Register-Cleanup $outside
    $linkCreated = $false
    try {
        New-Item -ItemType SymbolicLink -Path (Join-Path $target '.cursor') -Target $outside -ErrorAction Stop | Out-Null
        $linkCreated = $true
    } catch {
        $script:skipped++
        Write-Host 'SKIP: T11 symlink containment (symlink creation not permitted on this host)'
    }
    if ($linkCreated) {
        $result = Invoke-InstallerOutput -Arguments @('-Editor', 'cursor', '-TargetPath', $target)
        $outsideState = Get-TreeState -Directory $outside
        Assert-True 'T11 symlinked destination refused (exit 2)' ($result.ExitCode -eq 2) "exit $($result.ExitCode)"
        Assert-True 'T11 nothing written outside the root' ($outsideState.Count -eq 0)
    }

    # ---------------------------------------------------------------- T12 user scope with redirected homes
    $fakeHome = New-TempDirectory; Register-Cleanup $fakeHome
    $fakeCodex = New-TempDirectory; Register-Cleanup $fakeCodex
    $exitCode = Invoke-Installer -Arguments @('-Scope', 'user', '-Editor', 'claude,cursor,opencode,codex', '-UserHome', $fakeHome, '-CodexHome', $fakeCodex)
    Assert-True 'T12 user-scope installs exit 0' ($exitCode -eq 0)
    Assert-True 'T12 claude user skill installed' ((Test-Path -LiteralPath (Join-Path $fakeHome '.claude/skills/clean-code-refactor/SKILL.md')))
    Assert-True 'T12 cursor user skill installed' ((Test-Path -LiteralPath (Join-Path $fakeHome '.cursor/skills/clean-code-refactor/SKILL.md')))
    Assert-True 'T12 opencode user skill installed' ((Test-Path -LiteralPath (Join-Path $fakeHome '.config/opencode/skills/clean-code-refactor/SKILL.md')))
    Assert-True 'T12 codex skill installed in redirected home' ((Test-Path -LiteralPath (Join-Path $fakeCodex 'skills/clean-code-refactor/SKILL.md')))
    # Project scope after user scope must not skip (separate units).
    $projectTarget = New-TempDirectory; Register-Cleanup $projectTarget
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude', '-TargetPath', $projectTarget)
    Assert-True 'T12 project install unaffected by user install' ($exitCode -eq 0)

    # ---------------------------------------------------------------- T13 JSON summary consistency
    $target = New-TempDirectory; Register-Cleanup $target
    $result = Invoke-InstallerOutput -Arguments @('-Editor', 'all', '-TargetPath', $target, '-OutputFormat', 'Json')
    $plan = $null
    try { $plan = $result.Output | ConvertFrom-Json } catch { }
    $count = 0
    if ($plan) { $count = @($plan.results).Count }
    Assert-True 'T13 JSON output parses with results' (($result.ExitCode -eq 0) -and ($null -ne $plan) -and ($count -gt 0))
    $sum = 0
    if ($plan) { $sum = $plan.summary.installed + $plan.summary.updated + $plan.summary.upToDate + $plan.summary.skipped + $plan.summary.failed }
    Assert-True 'T13 summary equals result count' ($sum -eq $count)

    # ---------------------------------------------------------------- T14 bash suite
    # Prefer Git Bash; System32 bash.exe is WSL and cannot run Windows-style paths.
    $bashExe = $null
    # These variables exist only on Windows; skip unset ones so Join-Path never gets $null.
    $gitBashCandidates = @(
        @($env:ProgramFiles, 'Git/bin/bash.exe'),
        @(${env:ProgramFiles(x86)}, 'Git/bin/bash.exe'),
        @($env:LOCALAPPDATA, 'Programs/Git/bin/bash.exe')
    ) | Where-Object { $_[0] } | ForEach-Object { Join-Path $_[0] $_[1] }
    foreach ($candidate in $gitBashCandidates) {
        if (Test-Path -LiteralPath $candidate) { $bashExe = $candidate; break }
    }
    if (-not $bashExe) {
        $resolvedBash = Get-Command bash -ErrorAction SilentlyContinue
        if ($resolvedBash -and $resolvedBash.Source -notmatch '\\Windows\\System32\\bash\.exe$') { $bashExe = $resolvedBash.Source }
    }
    if ($SkipBash) {
        $script:skipped++
        Write-Host 'SKIP: T14 bash suite (-SkipBash)'
    } elseif (-not $bashExe) {
        $script:skipped++
        Write-Host 'SKIP: T14 bash suite (Git Bash not available)'
    } else {
        # Git Bash needs a POSIX-style path; also guard stderr redirection against 'Stop'.
        $bashSuitePath = $bashSuite -replace '\\', '/'
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $bashExe $bashSuitePath *> $null
        } finally {
            $ErrorActionPreference = $previous
        }
        Assert-True 'T14 bash installer suite passes' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
    }

    # ---------------------------------------------------------------- profiler smoke test
    $fakeRepo = New-TempDirectory; Register-Cleanup $fakeRepo
    New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'src/auth'), (Join-Path $fakeRepo '.github/workflows'), (Join-Path $fakeRepo 'docs'), (Join-Path $fakeRepo 'node_modules/should-not-be-read') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeRepo 'package.json') -Value '{ "dependencies": { "react": "18.0.0" } }' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo '.github/workflows/ci.yml') -Value 'on: push' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'src/auth/login.py') -Value 'def login(): pass' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'docs/authentication-policy.md') -Value 'documentation about authentication policy' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'node_modules/should-not-be-read/leak.go') -Value 'module leak' -NoNewline
    $profileOutput = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'scripts/profile-repository.ps1') -Path $fakeRepo -OutputFormat Json | Out-String
    $profile = $null
    try { $profile = $profileOutput | ConvertFrom-Json } catch { }
    Assert-True 'T15 profiler JSON parses and is complete' (($null -ne $profile) -and ($profile.complete -eq $true))
    Assert-True 'T15 profiler detects nested language manifest' ($profile.languages -contains 'TypeScript/JavaScript')
    Assert-True 'T15 profiler detects React framework' ($profile.frameworks -contains 'React/Next.js')
    Assert-True 'T15 profiler detects GitHub Actions config' ($profile.configuredChecks -contains 'GitHub Actions')
    Assert-True 'T15 profiler labels auth surface as code risk' ($profile.riskSignals -contains 'authentication or authorization surface')
    Assert-True 'T15 profiler labels auth doc as documentation hint' ($profile.documentationHints -contains 'authentication or authorization surface')
    Assert-True 'T15 profiler evidence path present' (($profile.signals | Where-Object { $_.value -eq 'authentication or authorization surface' -and $_.category -eq 'riskSignals' } | ForEach-Object { $_.evidence -contains 'src/auth/login.py' }) -contains $true)
    Assert-True 'T15 pruned directories are excluded' (($profile.signals | Where-Object { $_.evidence -match 'node_modules' } | Measure-Object).Count -eq 0)
} finally {
    foreach ($path in $script:cleanup) {
        try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

Write-Host ''
Write-Host "PowerShell suite: $($script:pass) passed, $($script:fail) failed, $($script:skipped) skipped."
if ($script:fail -gt 0) { exit 1 }
exit 0
