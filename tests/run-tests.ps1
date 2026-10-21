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

# The installer prefers XDG_CONFIG_HOME over -UserHome; clear it so user-scope tests
# stay inside their redirected homes and never write to the host's real config.
Remove-Item -Path Env:XDG_CONFIG_HOME -ErrorAction SilentlyContinue
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
    Assert-True 'T2 bash profiler tool installed' ((Test-Path -LiteralPath (Join-Path $target '.cursor/rules/clean-code-refactor-tools/profile-repository.sh')))
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
    try { $plan = $json.Output | ConvertFrom-Json } catch { $plan = $null }
    Assert-True 'T4 re-run exits 0' ($json.ExitCode -eq 0)
    Assert-True 'T4 re-run reports everything up-to-date' ($null -ne $plan -and $plan.summary.upToDate -gt 0 -and $plan.summary.updated -eq 0 -and $plan.summary.failed -eq 0) "summary: $($plan.summary | ConvertTo-Json -Compress)"

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
    try { $plan = $result.Output | ConvertFrom-Json } catch { $plan = $null }
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
    $exitCode = Invoke-Installer -Arguments @('-Scope', 'user', '-Editor', 'agents,claude,cursor,opencode,codex', '-UserHome', $fakeHome, '-CodexHome', $fakeCodex)
    Assert-True 'T12 user-scope installs exit 0' ($exitCode -eq 0)
    Assert-True 'T12 shared .agents user skill installed' ((Test-Path -LiteralPath (Join-Path $fakeHome '.agents/skills/clean-code-refactor/SKILL.md')))
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
    try { $plan = $result.Output | ConvertFrom-Json } catch { $plan = $null }
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

    # ---------------------------------------------------------------- T17 installers are interchangeable
    # A bash install must look up-to-date to the PowerShell installer: same bytes, same receipts.
    if (-not $bashExe) {
        $script:skipped++
        Write-Host 'SKIP: T17 cross-installer equivalence (bash not available)'
    } else {
        $crossTarget = New-TempDirectory; Register-Cleanup $crossTarget
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $bashExe (($bashSuite -replace 'tests[\\/]install\.sh\.tests\.sh$', 'scripts/install.sh') -replace '\\', '/') --editor all --target ($crossTarget -replace '\\', '/') *> $null
            $bashExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previous
        }
        Assert-True 'T17 bash install of every target exits 0' ($bashExit -eq 0) "exit $bashExit"
        $cross = Invoke-InstallerOutput -Arguments @('-Editor', 'all', '-TargetPath', $crossTarget, '-OutputFormat', 'Json')
        $crossPlan = $null
        try { $crossPlan = $cross.Output | ConvertFrom-Json } catch { $crossPlan = $null }
        Assert-True 'T17 PowerShell sees the bash install as up-to-date' ($null -ne $crossPlan -and $crossPlan.summary.updated -eq 0 -and $crossPlan.summary.upToDate -gt 0) "summary: $($crossPlan.summary | ConvertTo-Json -Compress)"
    }

    # ---------------------------------------------------------------- T18 organization and project policy
    $checkPolicy = Join-Path $repositoryRoot 'scripts/check-policy.ps1'
    $examplePolicy = Join-Path $repositoryRoot 'policy/policy.example.json'
    $policyProject = New-TempDirectory; Register-Cleanup $policyProject
    New-Item -ItemType Directory -Path (Join-Path $policyProject '.clean-code-refactor') | Out-Null
    Set-Content -LiteralPath (Join-Path $policyProject '.clean-code-refactor/policy.json') -NoNewline -Value '{ "policyVersion": 1, "gates": { "newCodeCoverageMin": 50, "newCodeDuplicationMax": 1 }, "exceptions": { "requireTicket": false }, "profile": { "default": "legacy-safe" }, "bannedApis": [ { "id": "js-eval", "text": "noop", "reason": "override" } ] }'
    $policyReport = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checkPolicy -ProjectPath $policyProject -OrgPolicyPath $examplePolicy | Out-String | ConvertFrom-Json
    Assert-True 'T18 project policy cannot lower the coverage minimum' ($policyReport.effective.gates.newCodeCoverageMin -eq 85)
    Assert-True 'T18 project policy can lower the duplication maximum' ($policyReport.effective.gates.newCodeDuplicationMax -eq 1)
    Assert-True 'T18 project policy cannot switch off exception tickets' ($policyReport.effective.exceptions.requireTicket -eq $true)
    Assert-True 'T18 project policy cannot redefine an organization banned API' (@($policyReport.effective.bannedApis | Where-Object { $_.id -eq 'js-eval' -and $_.text -eq 'eval(' }).Count -eq 1)
    Assert-True 'T18 project policy cannot choose a forbidden legacy-safe profile' ($policyReport.effective.profile.default -eq 'strict')
    Assert-True 'T18 loosening attempts are reported' (@($policyReport.ignored).Count -eq 4)
    Set-Content -LiteralPath (Join-Path $policyProject '.clean-code-refactor/policy.json') -NoNewline -Value '{ "policyVersion": 1, "gates": { "unknown": 1 } }'
    & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checkPolicy -ProjectPath $policyProject *> $null
    Assert-True 'T18 an invalid project policy fails the check' ($LASTEXITCODE -eq 1)

    $policyTarget = New-TempDirectory; Register-Cleanup $policyTarget
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude,cursor', '-TargetPath', $policyTarget, '-PolicyFile', $examplePolicy)
    Assert-True 'T18 install with an organization policy exits 0' ($exitCode -eq 0)
    Assert-True 'T18 policy installed in skill folder and next to rule-file tools' ((Test-Path -LiteralPath (Join-Path $policyTarget '.claude/skills/clean-code-refactor/policy.json')) -and (Test-Path -LiteralPath (Join-Path $policyTarget '.cursor/rules/clean-code-refactor-tools/policy.json')))
    $installedReport = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $policyTarget '.claude/skills/clean-code-refactor/scripts/check-policy.ps1') -ProjectPath $policyTarget | Out-String | ConvertFrom-Json
    Assert-True 'T18 installed check-policy finds the organization policy' ($installedReport.effective.gates.newCodeCoverageMin -eq 85)
    $invalidPolicy = Join-Path $policyTarget 'invalid-policy.json'
    Set-Content -LiteralPath $invalidPolicy -NoNewline -Value '{ "policyVersion": 9 }'
    $invalidTarget = New-TempDirectory; Register-Cleanup $invalidTarget
    $exitCode = Invoke-Installer -Arguments @('-Editor', 'claude', '-TargetPath', $invalidTarget, '-PolicyFile', $invalidPolicy)
    Assert-True 'T18 invalid policy is rejected before writing' (($exitCode -eq 2) -and -not (Test-Path -LiteralPath (Join-Path $invalidTarget '.claude')))

    # ---------------------------------------------------------------- T19 verify mode
    $verifyTarget = New-TempDirectory; Register-Cleanup $verifyTarget
    $null = Invoke-Installer -Arguments @('-Editor', 'claude,cursor', '-TargetPath', $verifyTarget)
    $stateBefore = Get-TreeState -Directory $verifyTarget
    $verifyRun = Invoke-InstallerOutput -Arguments @('-Verify', '-Editor', 'claude,cursor', '-TargetPath', $verifyTarget, '-OutputFormat', 'Json')
    $verifyReport = $null
    try { $verifyReport = $verifyRun.Output | ConvertFrom-Json } catch { $verifyReport = $null }
    Assert-True 'T19 clean install verifies' (($verifyRun.ExitCode -eq 0) -and ($null -ne $verifyReport) -and $verifyReport.passed)
    $stateAfter = Get-TreeState -Directory $verifyTarget
    Assert-True 'T19 verify writes nothing' (($stateBefore.Count -eq $stateAfter.Count) -and -not (Compare-Object @($stateBefore.Values) @($stateAfter.Values)))
    Assert-True 'T19 version pin mismatch fails' ((Invoke-Installer -Arguments @('-Verify', '-Editor', 'claude', '-TargetPath', $verifyTarget, '-ExpectVersion', '0.0.1')) -eq 1)
    Add-Content -LiteralPath (Join-Path $verifyTarget '.claude/skills/clean-code-refactor/references/agent-security.md') -Value 'tampered'
    $tamperRun = Invoke-InstallerOutput -Arguments @('-Verify', '-Editor', 'claude', '-TargetPath', $verifyTarget, '-OutputFormat', 'Json')
    $tamperReport = $null
    try { $tamperReport = $tamperRun.Output | ConvertFrom-Json } catch { $tamperReport = $null }
    Assert-True 'T19 tampering is reported as modified' (($tamperRun.ExitCode -eq 1) -and ($null -ne $tamperReport) -and (@($tamperReport.results)[0].status -eq 'modified'))

    # ---------------------------------------------------------------- profiler smoke test
    $fakeRepo = New-TempDirectory; Register-Cleanup $fakeRepo
    New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'src/auth'), (Join-Path $fakeRepo '.github/workflows'), (Join-Path $fakeRepo 'docs'), (Join-Path $fakeRepo 'node_modules/should-not-be-read') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeRepo 'package.json') -Value '{ "dependencies": { "react": "18.0.0" } }' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo '.github/workflows/ci.yml') -Value 'on: push' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'src/auth/login.py') -Value 'def login(): pass' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'docs/authentication-policy.md') -Value 'documentation about authentication policy' -NoNewline
    Set-Content -LiteralPath (Join-Path $fakeRepo 'node_modules/should-not-be-read/leak.go') -Value 'module leak' -NoNewline
    $profileOutput = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'scripts/profile-repository.ps1') -Path $fakeRepo -OutputFormat Json | Out-String
    $profileReport = $null
    try { $profileReport = $profileOutput | ConvertFrom-Json } catch { $profileReport = $null }
    Assert-True 'T15 profiler JSON parses and is complete' (($null -ne $profileReport) -and ($profileReport.complete -eq $true))
    Assert-True 'T15 profiler detects nested language manifest' ($profileReport.languages -contains 'TypeScript/JavaScript')
    Assert-True 'T15 profiler detects React framework' ($profileReport.frameworks -contains 'React/Next.js')
    Assert-True 'T15 profiler detects GitHub Actions config' ($profileReport.configuredChecks -contains 'GitHub Actions')
    Assert-True 'T15 profiler labels auth surface as code risk' ($profileReport.riskSignals -contains 'authentication or authorization surface')
    Assert-True 'T15 profiler labels auth doc as documentation hint' ($profileReport.documentationHints -contains 'authentication or authorization surface')
    Assert-True 'T15 profiler evidence path present' (($profileReport.signals | Where-Object { $_.value -eq 'authentication or authorization surface' -and $_.category -eq 'riskSignals' } | ForEach-Object { $_.evidence -contains 'src/auth/login.py' }) -contains $true)
    Assert-True 'T15 pruned directories are excluded' (($profileReport.signals | Where-Object { $_.evidence -match 'node_modules' } | Measure-Object).Count -eq 0)
    $profileJson = $profileOutput -replace '\s+', ' '
    Assert-True 'T15 single-value lists stay JSON arrays' ($profileJson -match '"languages": \[ ?"')
    Assert-True 'T15 empty lists are JSON arrays, not null' ($profileJson -match '"deliverySignals": \[ ?\]')

    # A scan cut short by the file limit must say so, even in the last directory walked.
    $bigRepo = New-TempDirectory; Register-Cleanup $bigRepo
    foreach ($index in 1..150) { New-Item -ItemType File -Path (Join-Path $bigRepo "f$index.py") | Out-Null }
    $bigOutput = & $powershellHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'scripts/profile-repository.ps1') -Path $bigRepo -OutputFormat Json -MaxFiles 100 | Out-String
    $bigReport = $null
    try { $bigReport = $bigOutput | ConvertFrom-Json } catch { $bigReport = $null }
    Assert-True 'T15 truncated scan is reported incomplete' (($null -ne $bigReport) -and ($bigReport.complete -eq $false) -and ($bigReport.stats.scannedFiles -eq 100))

    # ---------------------------------------------------------------- T16 profiler parity
    # profile-repository.sh must report what profile-repository.ps1 reports for the same tree.
    if (-not $bashExe) {
        $script:skipped++
        Write-Host 'SKIP: T16 profiler parity (bash not available)'
    } else {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $bashProfileOutput = & $bashExe ((Join-Path $repositoryRoot 'scripts/profile-repository.sh') -replace '\\', '/') --path ($fakeRepo -replace '\\', '/') --format json 2>&1 | Out-String
            $bashExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previous
        }
        $bashReport = $null
        try { $bashReport = $bashProfileOutput | ConvertFrom-Json } catch { $bashReport = $null }
        Assert-True 'T16 bash profiler JSON parses' (($bashExit -eq 0) -and ($null -ne $bashReport)) "exit $bashExit"
        if ($null -ne $bashReport) {
            foreach ($field in @('suggestedProfile', 'complete', 'languages', 'frameworks', 'configuredChecks', 'deliverySignals', 'riskSignals', 'documentationHints', 'notes')) {
                $expected = (@($profileReport.$field) | Sort-Object) -join '|'
                $actual = (@($bashReport.$field) | Sort-Object) -join '|'
                Assert-True "T16 profilers agree on $field" ($expected -eq $actual) "ps '$expected' vs bash '$actual'"
            }
            $expectedSignals = (@($profileReport.signals | ForEach-Object { "$($_.category)/$($_.value)/$($_.confidence)/$(@($_.evidence).Count)" }) | Sort-Object) -join '|'
            $actualSignals = (@($bashReport.signals | ForEach-Object { "$($_.category)/$($_.value)/$($_.confidence)/$(@($_.evidence).Count)" }) | Sort-Object) -join '|'
            Assert-True 'T16 profilers agree on signals and evidence counts' ($expectedSignals -eq $actualSignals) "ps '$expectedSignals' vs bash '$actualSignals'"
            $expectedStats = ($profileReport.stats.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '|'
            $actualStats = ($bashReport.stats.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '|'
            Assert-True 'T16 profilers agree on scan statistics' ($expectedStats -eq $actualStats) "ps '$expectedStats' vs bash '$actualStats'"
        }
    }
} finally {
    foreach ($path in $script:cleanup) {
        try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } catch { Write-Verbose "Cleanup failed for ${path}: $_" }
    }
}

Write-Host ''
Write-Host "PowerShell suite: $($script:pass) passed, $($script:fail) failed, $($script:skipped) skipped."
if ($script:fail -gt 0) { exit 1 }
exit 0
