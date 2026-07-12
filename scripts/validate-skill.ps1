[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$skillPath = Join-Path $RepositoryRoot 'SKILL.md'
$referencePath = Join-Path $RepositoryRoot 'references/language-hardening.md'
$installerPath = Join-Path $RepositoryRoot 'scripts/install.ps1'
$requiredHeadings = @(
    '## Workflow',
    '## Quality Gate: Clean as You Code',
    '## Lint and Duplicate Detection',
    '## Cross-Language Hardening',
    '## Verification',
    '## Completion Report'
)

foreach ($path in @($skillPath, $referencePath, $installerPath)) {
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

if ($skill -notmatch '\[language-hardening\.md\]\(references/language-hardening\.md\)') {
    throw 'SKILL.md does not link to language-hardening.md.'
}

$installer = Get-Content -LiteralPath $installerPath -Raw
foreach ($editor in @('cursor', 'copilot', 'claude', 'codex', 'windsurf', 'cline', 'roo', 'continue', 'amazonq', 'opencode', 'kilo')) {
    if ($installer -notmatch "'$editor'") {
        throw "Installer is missing editor target: $editor"
    }
}

$markdownFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter '*.md'
$trailingWhitespace = $markdownFiles | Select-String -Pattern '[ \t]+$'
if ($trailingWhitespace) {
    throw "Trailing whitespace found in: $($trailingWhitespace[0].Path):$($trailingWhitespace[0].LineNumber)"
}

Write-Host 'Skill package validation passed.'
