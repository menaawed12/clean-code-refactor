<#
.SYNOPSIS
    Validates the clean-code-refactor skill package.

.DESCRIPTION
    Layer 1 of the package's verification (behavioral installer tests live in tests/):
      - Required files and sections exist.
      - SKILL.md front matter, required sections, language coverage, and reference links.
      - Every relative Markdown link in the package resolves to an existing file.
      - The rule-body path transformation is single-pass: no double prefixes, and every
        generated local link resolves against the package sources.
      - integrations/registry.json parses, is internally consistent, and stays in parity
        with both installers' embedded target tables (drift fails validation).
      - Installers declare the behavioral contract markers (dry-run, force, preflight).
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

# Resolved in the body: $PSScriptRoot is empty inside parameter defaults when a
# CmdletBinding script is launched with powershell.exe -File (Windows PowerShell 5.1).
if (-not $RepositoryRoot) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$ErrorActionPreference = 'Stop'
$skillPath = Join-Path $RepositoryRoot 'SKILL.md'
$readmePath = Join-Path $RepositoryRoot 'README.md'
$referenceDir = Join-Path $RepositoryRoot 'references'
$agentSecurityPath = Join-Path $referenceDir 'agent-security.md'
$referencePath = Join-Path $referenceDir 'language-hardening.md'
$staticQualityRulesPath = Join-Path $referenceDir 'static-quality-rules.md'
$policyGuidancePath = Join-Path $referenceDir 'policy-and-framework-guidance.md'
$apiSafetyPath = Join-Path $referenceDir 'api-and-data-safety.md'
$testSupplyChainPath = Join-Path $referenceDir 'test-performance-and-supply-chain.md'
$reviewReportPath = Join-Path $referenceDir 'structured-review-report.md'
$securityPolicyPath = Join-Path $RepositoryRoot 'SECURITY.md'
$registryPath = Join-Path $RepositoryRoot 'integrations/registry.json'
$compatibilityDocPath = Join-Path $RepositoryRoot 'docs/ide-compatibility.md'
$installerPath = Join-Path $RepositoryRoot 'scripts/install.ps1'
$bashInstallerPath = Join-Path $RepositoryRoot 'scripts/install.sh'
$profileScriptPath = Join-Path $RepositoryRoot 'scripts/profile-repository.ps1'
$psTestRunnerPath = Join-Path $RepositoryRoot 'tests/run-tests.ps1'
$bashTestRunnerPath = Join-Path $RepositoryRoot 'tests/install.sh.tests.sh'
$requiredHeadings = @(
    '## Workflow',
    '## Quality Gate: Clean as You Code',
    '## Lint and Duplicate Detection',
    '## Cross-Language Hardening',
    '## Verification',
    '## Completion Report'
)

foreach ($path in @($skillPath, $readmePath, $referencePath, $staticQualityRulesPath, $policyGuidancePath, $apiSafetyPath, $testSupplyChainPath, $reviewReportPath, $agentSecurityPath, $securityPolicyPath, $registryPath, $compatibilityDocPath, $installerPath, $bashInstallerPath, $profileScriptPath, $psTestRunnerPath, $bashTestRunnerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$skill = Get-Content -LiteralPath $skillPath -Raw
if ($skill -notmatch '(?s)^---\r?\nname: "clean-code-refactor"\r?\ndescription: ".+?"\r?\ncompatibility: ".+?"\r?\nmetadata:\r?\n  author: ".+?"\r?\n---') {
    throw 'SKILL.md front matter is invalid or incomplete.'
}

foreach ($heading in $requiredHeadings) {
    if ($skill -notmatch [regex]::Escape($heading)) {
        throw "SKILL.md is missing required section: $heading"
    }
}

foreach ($language in @('Python', 'TypeScript', 'Java', 'Kotlin', 'Scala', 'C#', 'Go', 'Rust', 'Dart', 'Elixir', 'SQL')) {
    if ($skill -notmatch [regex]::Escape($language)) {
        throw "SKILL.md is missing language support: $language"
    }
}

foreach ($reference in @('language-hardening.md', 'static-quality-rules.md', 'policy-and-framework-guidance.md', 'api-and-data-safety.md', 'test-performance-and-supply-chain.md', 'structured-review-report.md', 'agent-security.md')) {
    if ($skill -notmatch [regex]::Escape("references/$reference")) {
        throw "SKILL.md does not link to $reference."
    }
}

$allSkillContent = Get-Content -LiteralPath $skillPath, $referencePath, $staticQualityRulesPath -Raw
if ($allSkillContent -match 'SonarQube|SonarCloud|Sonar analysis|Sonar-style') {
    throw 'The skill must not reference or require a Sonar service.'
}

if ($skill -notmatch [regex]::Escape('references/agent-security.md')) {
    throw 'SKILL.md does not reference the agent trust-boundary guidance.'
}

# --------------------------- markdown link resolution ----------------------

$markdownFiles = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($markdownFile in $markdownFiles) {
    $content = Get-Content -LiteralPath $markdownFile.FullName -Raw
    $directory = Split-Path -Parent $markdownFile.FullName
    $targets = @()
    foreach ($match in [regex]::Matches($content, '\[[^\]]*\]\(([^)\s]+)\)')) { $targets += $match.Groups[1].Value }
    foreach ($match in [regex]::Matches($content, '(?m)^\[[^\]]+\]:\s+(\S+)')) { $targets += $match.Groups[1].Value }
    foreach ($target in $targets) {
        if ($target -match '^(https?:|mailto:|#)' -or $target -notmatch '\.[A-Za-z0-9]+$') { continue }
        $candidate = Join-Path $directory ($target -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Broken link in $($markdownFile.Name): $target"
        }
    }
}

# --------------------------- generated-rule transformation -----------------

$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
function Get-Prop { param($Object, [string]$Name) $p = $Object.PSObject.Properties[$Name]; if ($p) { $p.Value } else { $null } }
$package = Get-Prop $registry 'package'
$layout = Get-Prop $registry 'ruleFileLayout'
$referencesDirName = Get-Prop $layout 'referencesDirName'
$toolsDirName = Get-Prop $layout 'toolsDirName'
$profilerFileName = Get-Prop $layout 'profilerFileName'
$body = $skill -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
$body = $body.Replace('references/', "$referencesDirName/")
$body = $body.Replace('scripts/profile-repository.ps1', "$toolsDirName/$profilerFileName")
if ($body -match 'clean-code-refactor-clean-code-refactor') {
    throw 'Rule-body transformation produced a double-prefixed reference path.'
}
foreach ($match in [regex]::Matches($body, [regex]::Escape("$referencesDirName/") + '([A-Za-z0-9][A-Za-z0-9._/-]*)')) {
    $candidate = Join-Path $referenceDir ($match.Groups[1].Value.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Generated rule would reference a missing package file: $referencesDirName/$($match.Groups[1].Value)"
    }
}
if ($body -match 'scripts/profile-repository\.ps1') {
    throw 'Rule-body transformation did not rewrite the profiler path.'
}

# --------------------------- registry consistency --------------------------

$validRoots = @('project', 'codex-home', 'home', 'xdg-config')
$validKinds = @('skill-folder', 'rule-file')
$validFormats = @('plain', 'cursor', 'continue')
$registryEditors = @()
foreach ($property in (Get-Prop $registry 'editors').PSObject.Properties) {
    $id = $property.Name
    $definition = $property.Value
    $registryEditors += $id
    $kind = Get-Prop $definition 'kind'
    if ($validKinds -notcontains $kind) { throw "Registry editor '$id' has invalid kind '$kind'." }
    $scopes = Get-Prop $definition 'scopes'
    if ($null -eq $scopes) { throw "Registry editor '$id' declares no scopes." }
    foreach ($scopeName in @('project', 'user')) {
        $scopeDef = Get-Prop $scopes $scopeName
        if ($null -eq $scopeDef) { continue }
        if ($validRoots -notcontains (Get-Prop $scopeDef 'root')) { throw "Registry editor '$id' scope '$scopeName' has invalid root." }
        $pathValue = Get-Prop $scopeDef 'path'
        if (-not $pathValue -or $pathValue -match '(\.\.|^/|^[A-Za-z]:)') { throw "Registry editor '$id' scope '$scopeName' has invalid path '$pathValue'." }
        $scopeKind = Get-Prop $scopeDef 'kind'
        if (-not $scopeKind) { $scopeKind = $kind }
        if ($validKinds -notcontains $scopeKind) { throw "Registry editor '$id' scope '$scopeName' has invalid kind '$scopeKind'." }
        if ($scopeKind -eq 'rule-file') {
            $format = Get-Prop $scopeDef 'format'
            if (-not $format) { $format = 'plain' }
            if ($validFormats -notcontains $format) { throw "Registry editor '$id' has invalid rule format '$format'." }
        }
    }
}

# --------------------------- installer parity ------------------------------

$installer = Get-Content -LiteralPath $installerPath -Raw
$bashInstaller = Get-Content -LiteralPath $bashInstallerPath -Raw

# The PowerShell installer is registry-driven: it must consume integrations/registry.json
# rather than duplicating editor ids (per-id parity is enforced against the bash tables below).
if ($installer -notmatch [regex]::Escape('integrations/registry.json')) {
    throw 'PowerShell installer does not load integrations/registry.json.'
}
if ($installer -notmatch 'editors') {
    throw 'PowerShell installer does not read the registry editors collection.'
}

foreach ($id in $registryEditors) {
    if ($bashInstaller -notmatch ("\b{0}\b" -f [regex]::Escape($id))) {
        throw "Bash installer does not declare editor target: $id"
    }
}

function Get-BashTargetTable {
    param([string]$Text, [string]$TableName)
    # Locate the heredoc block robustly.
    $pattern = "(?s)$TableName=\`$\(\s*cat <<'$TableName" + "_EOF'\r?\n(.*?)\r?\n$TableName" + "_EOF\s*\)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "Bash installer target table '$TableName' is missing or malformed." }
    return $match.Groups[1].Value
}

function ConvertTo-TargetMap {
    param([string]$TableText)
    $map = @{}
    foreach ($line in ($TableText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $columns = $line -split '\|'
        if ($columns.Count -lt 11) { throw "Bash target row has too few columns: $line" }
        $map[$columns[0]] = [pscustomobject]@{
            id = $columns[0]; kind = $columns[1]; root = $columns[2]; path = $columns[3]
            format = $columns[4]; verification = $columns[10]
        }
    }
    return $map
}

$projectTable = ConvertTo-TargetMap -TableText (Get-BashTargetTable -Text $bashInstaller -TableName 'PROJECT_TARGETS')
$userTable = ConvertTo-TargetMap -TableText (Get-BashTargetTable -Text $bashInstaller -TableName 'USER_TARGETS')

foreach ($property in (Get-Prop $registry 'editors').PSObject.Properties) {
    $id = $property.Name
    $definition = $property.Value
    foreach ($scopeName in @('project', 'user')) {
        $scopeDef = Get-Prop (Get-Prop $definition 'scopes') $scopeName
        $table = if ($scopeName -eq 'project') { $projectTable } else { $userTable }
        if ($null -eq $scopeDef) {
            if ($table.ContainsKey($id)) { throw "Bash installer declares a $scopeName target for '$id' that the registry does not." }
            continue
        }
        if (-not $table.ContainsKey($id)) { throw "Bash installer is missing the $scopeName target for '$id'." }
        $row = $table[$id]
        $scopeKind = Get-Prop $scopeDef 'kind'
        if (-not $scopeKind) { $scopeKind = Get-Prop $definition 'kind' }
        $format = Get-Prop $scopeDef 'format'
        if (-not $format) { $format = 'plain' }
        $verification = Get-Prop $scopeDef 'verification'
        if (-not $verification) { $verification = '-' }
        if ($row.kind -ne $scopeKind) { throw "Kind mismatch for '$id' ($scopeName): registry '$scopeKind' vs bash '$($row.kind)'." }
        if ($row.root -ne (Get-Prop $scopeDef 'root')) { throw "Root mismatch for '$id' ($scopeName)." }
        if ($row.path -ne (Get-Prop $scopeDef 'path')) { throw "Path mismatch for '$id' ($scopeName): registry '$(Get-Prop $scopeDef 'path')' vs bash '$($row.path)'." }
        if ($scopeKind -eq 'rule-file' -and $row.format -ne $format) { throw "Format mismatch for '$id' ($scopeName)." }
        if ($row.verification -ne $verification) { throw "Verification marker mismatch for '$id' ($scopeName)." }
    }
}

# --------------------------- behavioral contract markers -------------------

foreach ($token in @('DryRun', 'Force', 'Preflight', 'OutputFormat')) {
    if ($installer -notmatch [regex]::Escape($token)) {
        throw "PowerShell installer is missing required behavior marker: $token"
    }
}
foreach ($token in @('--dry-run', '--force', 'preflight', '--json', '--scope')) {
    if ($bashInstaller -notmatch [regex]::Escape($token)) {
        throw "Bash installer is missing required behavior marker: $token"
    }
}
foreach ($token in @('MaxFiles', 'MaxDepth', 'TimeoutSeconds', 'incompleteReason')) {
    if ((Get-Content -LiteralPath $profileScriptPath -Raw) -notmatch [regex]::Escape($token)) {
        throw "Profiler is missing required bounded-scan feature: $token"
    }
}

# --------------------------- README and hygiene ----------------------------

$readme = Get-Content -LiteralPath $readmePath -Raw
if ($readme -notmatch '## Language Support') { throw 'README.md is missing the language support section.' }
if ($readme -notmatch '## Advanced Capabilities') { throw 'README.md is missing the advanced capabilities section.' }

$trailingWhitespace = $markdownFiles | Select-String -Pattern '[ \t]+$'
if ($trailingWhitespace) {
    throw "Trailing whitespace found in: $($trailingWhitespace[0].Path):$($trailingWhitespace[0].LineNumber)"
}

Write-Host 'Skill package validation passed.'
