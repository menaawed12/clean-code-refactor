[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$skillPath = Join-Path $RepositoryRoot 'SKILL.md'
$readmePath = Join-Path $RepositoryRoot 'README.md'
$referencePath = Join-Path $RepositoryRoot 'references/language-hardening.md'
$staticQualityRulesPath = Join-Path $RepositoryRoot 'references/static-quality-rules.md'
$policyGuidancePath = Join-Path $RepositoryRoot 'references/policy-and-framework-guidance.md'
$apiSafetyPath = Join-Path $RepositoryRoot 'references/api-and-data-safety.md'
$testSupplyChainPath = Join-Path $RepositoryRoot 'references/test-performance-and-supply-chain.md'
$reviewReportPath = Join-Path $RepositoryRoot 'references/structured-review-report.md'
$installerPath = Join-Path $RepositoryRoot 'scripts/install.ps1'
$profileScriptPath = Join-Path $RepositoryRoot 'scripts/profile-repository.ps1'
$requiredHeadings = @(
    '## Workflow',
    '## Quality Gate: Clean as You Code',
    '## Lint and Duplicate Detection',
    '## Cross-Language Hardening',
    '## Verification',
    '## Completion Report'
)

foreach ($path in @($skillPath, $readmePath, $referencePath, $staticQualityRulesPath, $policyGuidancePath, $apiSafetyPath, $testSupplyChainPath, $reviewReportPath, $installerPath, $profileScriptPath)) {
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

if ($skill -notmatch '\[language-hardening\.md\]\(references/language-hardening\.md\)') {
    throw 'SKILL.md does not link to language-hardening.md.'
}

if ($skill -notmatch '\[static-quality-rules\.md\]\(references/static-quality-rules\.md\)') {
    throw 'SKILL.md does not link to static-quality-rules.md.'
}

foreach ($reference in @('policy-and-framework-guidance.md', 'api-and-data-safety.md', 'test-performance-and-supply-chain.md', 'structured-review-report.md')) {
    if ($skill -notmatch [regex]::Escape("references/$reference")) {
        throw "SKILL.md does not link to $reference."
    }
}

$allSkillContent = Get-Content -LiteralPath $skillPath, $referencePath, $staticQualityRulesPath -Raw
if ($allSkillContent -match 'SonarQube|SonarCloud|Sonar analysis|Sonar-style') {
    throw 'The skill must not reference or require a Sonar service.'
}

$installer = Get-Content -LiteralPath $installerPath -Raw
foreach ($editor in @('cursor', 'copilot', 'claude', 'codex', 'windsurf', 'cline', 'roo', 'continue', 'amazonq', 'opencode', 'kilo')) {
    if ($installer -notmatch "'$editor'") {
        throw "Installer is missing editor target: $editor"
    }
}

$readme = Get-Content -LiteralPath $readmePath -Raw
if ($readme -notmatch '## Language Support') {
    throw 'README.md is missing the language support section.'
}

if ($readme -notmatch '## Advanced Capabilities') {
    throw 'README.md is missing the advanced capabilities section.'
}

$markdownFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter '*.md'
$trailingWhitespace = $markdownFiles | Select-String -Pattern '[ \t]+$'
if ($trailingWhitespace) {
    throw "Trailing whitespace found in: $($trailingWhitespace[0].Path):$($trailingWhitespace[0].LineNumber)"
}

Write-Host 'Skill package validation passed.'
