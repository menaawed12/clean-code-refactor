[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$skillPath = Join-Path $RepositoryRoot '.cursor/skills/clean-code-refactor/SKILL.md'
$referencePath = Join-Path $RepositoryRoot '.cursor/skills/clean-code-refactor/references/language-hardening.md'
$requiredHeadings = @(
    '## Workflow',
    '## Quality Gate: Clean as You Code',
    '## Lint and Duplicate Detection',
    '## Cross-Language Hardening',
    '## Verification',
    '## Completion Report'
)

foreach ($path in @($skillPath, $referencePath)) {
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

$markdownFiles = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter '*.md'
$trailingWhitespace = $markdownFiles | Select-String -Pattern '[ \t]+$'
if ($trailingWhitespace) {
    throw "Trailing whitespace found in: $($trailingWhitespace[0].Path):$($trailingWhitespace[0].LineNumber)"
}

Write-Host 'Skill package validation passed.'
