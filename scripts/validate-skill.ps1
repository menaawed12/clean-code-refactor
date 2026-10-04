<#
.SYNOPSIS
    Validates the clean-code-refactor skill package.

.DESCRIPTION
    Layer 1 of the package's verification (behavioral installer tests live in tests/):
      - Required files and sections exist.
      - SKILL.md front matter against the Agent Skills specification (fields, name
        format, length limits), required sections, language coverage, and reference links.
      - Every relative Markdown link in the package resolves to an existing file.
      - The rule-body path transformation is single-pass: no double prefixes, and every
        generated local link resolves against the package sources.
      - integrations/registry.json parses and is internally consistent; the PowerShell
        installer reads it directly and scripts/install.sh must match what
        scripts/sync-bash-installer.ps1 generates from it (drift fails validation).
      - The package version is single-sourced in integrations/registry.json and matches
        SKILL.md metadata and a CHANGELOG.md entry.
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
$aiCodePath = Join-Path $referenceDir 'ai-and-agent-code.md'
$standardsMappingPath = Join-Path $referenceDir 'standards-mapping.md'
$securityPolicyPath = Join-Path $RepositoryRoot 'SECURITY.md'
$changelogPath = Join-Path $RepositoryRoot 'CHANGELOG.md'
$registryPath = Join-Path $RepositoryRoot 'integrations/registry.json'
$compatibilityDocPath = Join-Path $RepositoryRoot 'docs/ide-compatibility.md'
$installerPath = Join-Path $RepositoryRoot 'scripts/install.ps1'
$bashInstallerPath = Join-Path $RepositoryRoot 'scripts/install.sh'
$profileScriptPath = Join-Path $RepositoryRoot 'scripts/profile-repository.ps1'
$bashProfileScriptPath = Join-Path $RepositoryRoot 'scripts/profile-repository.sh'
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

foreach ($path in @($skillPath, $readmePath, $referencePath, $staticQualityRulesPath, $policyGuidancePath, $apiSafetyPath, $testSupplyChainPath, $reviewReportPath, $aiCodePath, $standardsMappingPath, $agentSecurityPath, $securityPolicyPath, $changelogPath, $registryPath, $compatibilityDocPath, $installerPath, $bashInstallerPath, $profileScriptPath, $bashProfileScriptPath, $psTestRunnerPath, $bashTestRunnerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$skill = Get-Content -LiteralPath $skillPath -Raw

# --------------------------- front matter (Agent Skills specification) -----

function ConvertFrom-FrontMatterScalar {
    param([string]$Value)
    $Value = $Value.Trim()
    if ($Value.Length -ge 2 -and (($Value[0] -eq '"' -and $Value[-1] -eq '"') -or ($Value[0] -eq "'" -and $Value[-1] -eq "'"))) {
        return $Value.Substring(1, $Value.Length - 2)
    }
    return $Value
}

# Parses the subset of YAML the package uses: top-level scalars plus one level of
# string-valued maps (metadata). Anything else is rejected rather than guessed at.
function ConvertFrom-FrontMatter {
    param([string]$Text)
    $match = [regex]::Match($Text, '(?s)^---\r?\n(.*?)\r?\n---\r?\n')
    if (-not $match.Success) { throw 'SKILL.md must start with a front matter block delimited by --- lines.' }
    $fields = [ordered]@{}
    $currentMap = $null
    foreach ($line in ($match.Groups[1].Value -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') { continue }
        if ($line -match '^  ([A-Za-z0-9_-]+):\s*(.*)$' -and $null -ne $currentMap) {
            $currentMap[$Matches[1]] = ConvertFrom-FrontMatterScalar $Matches[2]
        } elseif ($line -match '^([A-Za-z0-9_-]+):\s*$') {
            $currentMap = [ordered]@{}
            $fields[$Matches[1]] = $currentMap
        } elseif ($line -match '^([A-Za-z0-9_-]+):\s+(.+)$') {
            $currentMap = $null
            $fields[$Matches[1]] = ConvertFrom-FrontMatterScalar $Matches[2]
        } else {
            throw "SKILL.md front matter line is not supported: $line"
        }
    }
    return $fields
}

$frontMatter = ConvertFrom-FrontMatter -Text $skill
$allowedFields = @('name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools')
foreach ($key in $frontMatter.Keys) {
    if ($allowedFields -notcontains $key) { throw "SKILL.md front matter has unknown field '$key' (allowed: $($allowedFields -join ', '))." }
}
foreach ($key in @('name', 'description', 'license', 'compatibility', 'metadata')) {
    if (-not $frontMatter.Contains($key)) { throw "SKILL.md front matter is missing '$key'." }
}
foreach ($key in @('name', 'description', 'license', 'compatibility')) {
    if ($frontMatter[$key] -isnot [string]) { throw "SKILL.md front matter '$key' must be a string." }
}
$skillName = $frontMatter['name']
if ($skillName.Length -gt 64 -or $skillName -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    throw "SKILL.md name '$skillName' must be 1-64 lowercase letters, digits, and single hyphens."
}
if ($frontMatter['description'].Length -lt 1 -or $frontMatter['description'].Length -gt 1024) {
    throw "SKILL.md description must be 1-1024 characters (found $($frontMatter['description'].Length))."
}
if ($frontMatter['compatibility'].Length -gt 500) {
    throw "SKILL.md compatibility must be at most 500 characters (found $($frontMatter['compatibility'].Length))."
}
$skillMetadata = $frontMatter['metadata']
if ($skillMetadata -isnot [System.Collections.IDictionary]) { throw 'SKILL.md metadata must be a map of string values.' }
foreach ($key in @('author', 'version')) {
    if (-not $skillMetadata.Contains($key) -or [string]::IsNullOrWhiteSpace($skillMetadata[$key])) { throw "SKILL.md metadata is missing '$key'." }
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

foreach ($reference in @('language-hardening.md', 'static-quality-rules.md', 'policy-and-framework-guidance.md', 'api-and-data-safety.md', 'test-performance-and-supply-chain.md', 'structured-review-report.md', 'agent-security.md', 'ai-and-agent-code.md', 'standards-mapping.md')) {
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

# --------------------------- single-source version -------------------------
# integrations/registry.json owns the package name and version; every other copy must match.

$packageVersion = Get-Prop $package 'version'
if ($packageVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Registry package version '$packageVersion' is not MAJOR.MINOR.PATCH." }
if ($skillName -ne (Get-Prop $package 'name')) { throw "SKILL.md name '$skillName' does not match registry package name '$(Get-Prop $package 'name')'." }
if ($skillMetadata['version'] -ne $packageVersion) { throw "SKILL.md metadata version '$($skillMetadata['version'])' does not match registry version '$packageVersion'." }
if ((Get-Content -LiteralPath $changelogPath -Raw) -notmatch ('(?m)^## \[' + [regex]::Escape($packageVersion) + '\]')) {
    throw "CHANGELOG.md has no '## [$packageVersion]' entry."
}

$layout = Get-Prop $registry 'ruleFileLayout'
$referencesDirName = Get-Prop $layout 'referencesDirName'
$toolsDirName = Get-Prop $layout 'toolsDirName'
$toolSources = @(Get-Prop $package 'toolSources')
if ($toolSources.Count -eq 0) { throw 'Registry package.toolSources must list the shipped tool scripts.' }
foreach ($toolSource in $toolSources) {
    if ($toolSource -notmatch '^scripts/[A-Za-z0-9._-]+$') { throw "Registry tool source '$toolSource' must be a file directly under scripts/." }
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $toolSource) -PathType Leaf)) { throw "Registry tool source is missing: $toolSource" }
}
$body = $skill -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
$body = $body.Replace('references/', "$referencesDirName/")
foreach ($toolSource in $toolSources) { $body = $body.Replace($toolSource, "$toolsDirName/$(Split-Path -Leaf $toolSource)") }
if ($body -match 'clean-code-refactor-clean-code-refactor') {
    throw 'Rule-body transformation produced a double-prefixed reference path.'
}
foreach ($match in [regex]::Matches($body, [regex]::Escape("$referencesDirName/") + '([A-Za-z0-9][A-Za-z0-9._/-]*)')) {
    $candidate = Join-Path $referenceDir ($match.Groups[1].Value.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Generated rule would reference a missing package file: $referencesDirName/$($match.Groups[1].Value)"
    }
}
foreach ($toolSource in $toolSources) {
    if ($body.Contains($toolSource)) { throw "Rule-body transformation did not rewrite the tool path $toolSource." }
}

# --------------------------- registry consistency --------------------------

$validRoots = @('project', 'codex-home', 'home', 'xdg-config')
$validKinds = @('skill-folder', 'rule-file')
$validFormats = @('plain', 'cursor', 'continue')
foreach ($property in (Get-Prop $registry 'editors').PSObject.Properties) {
    $id = $property.Name
    $definition = $property.Value
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

# The bash installer's copy of the registry (version, tool list, editor ids, and both
# target tables) is generated by sync-bash-installer.ps1; any drift fails validation.
$syncScript = Join-Path $RepositoryRoot 'scripts/sync-bash-installer.ps1'
$syncOutput = & $syncScript -RepositoryRoot $RepositoryRoot -Check
if ($LASTEXITCODE -ne 0) { throw ($syncOutput -join ' ') }

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
foreach ($token in @('--max-files', '--max-depth', '--max-file-bytes', '--timeout-seconds', 'incompleteReason')) {
    if ((Get-Content -LiteralPath $bashProfileScriptPath -Raw) -notmatch [regex]::Escape($token)) {
        throw "Bash profiler is missing required bounded-scan feature: $token"
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
