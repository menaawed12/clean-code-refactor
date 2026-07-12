[CmdletBinding()]
param(
    [ValidateSet(
        'all',
        'agents',
        'cursor',
        'copilot',
        'claude',
        'codex',
        'windsurf',
        'cline',
        'roo',
        'continue',
        'amazonq',
        'opencode',
        'kilo'
    )]
    [string[]]$Editor = @('all'),

    [string]$TargetPath = (Get-Location).Path,

    [string]$CodexHome = $(
        if ($env:CODEX_HOME) {
            $env:CODEX_HOME
        } else {
            Join-Path $HOME '.codex'
        }
    ),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillSource = Join-Path $repositoryRoot 'SKILL.md'
$referenceSource = Join-Path $repositoryRoot 'references'
$targetRoot = [System.IO.Path]::GetFullPath($TargetPath)

foreach ($path in @($skillSource, $referenceSource)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required source is missing: $path"
    }
}

if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "Target project directory does not exist: $targetRoot"
}

$skillText = Get-Content -LiteralPath $skillSource -Raw
$skillBody = $skillText -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
$ruleBody = $skillBody.Replace(
    'references/language-hardening.md',
    'clean-code-refactor-references/language-hardening.md'
)
$ruleBody = $ruleBody.Replace(
    'references/static-quality-rules.md',
    'clean-code-refactor-references/static-quality-rules.md'
)

function Test-ReplaceAllowed {
    param([string]$Path)

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Warning "Skipped existing path (use -Force to replace): $Path"
        return $false
    }
    return $true
}

function Copy-SkillFolder {
    param([string]$Destination)

    if (-not (Test-ReplaceAllowed $Destination)) {
        return
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $skillSource -Destination (Join-Path $Destination 'SKILL.md') -Force
    Copy-Item -LiteralPath $referenceSource -Destination (Join-Path $Destination 'references') -Recurse -Force
    Write-Host "Installed skill folder: $Destination"
}

function Install-RuleFile {
    param(
        [string]$Destination,
        [ValidateSet('plain', 'cursor', 'continue')][string]$Format = 'plain'
    )

    if (-not (Test-ReplaceAllowed $Destination)) {
        return
    }
    $parent = Split-Path -Parent $Destination
    $referenceDestination = Join-Path $parent 'clean-code-refactor-references'
    if ((Test-Path -LiteralPath $referenceDestination) -and -not $Force) {
        Write-Warning "Skipped rule because its reference directory already exists (use -Force to replace): $referenceDestination"
        return
    }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $content = $ruleBody
    switch ($Format) {
        'cursor' {
            $content = "---`n" +
                "description: Apply clean-code refactoring, hardening, lint remediation, and duplicate detection.`n" +
                "globs:`n" +
                "alwaysApply: false`n" +
                "---`n`n" +
                $ruleBody +
                "`n`n@clean-code-refactor-references/language-hardening.md`n" +
                "@clean-code-refactor-references/static-quality-rules.md`n"
        }
        'continue' {
            $content = "---`n" +
                "name: Clean Code Refactor`n" +
                "description: Refactor, review, and harden changed code.`n" +
                "alwaysApply: false`n" +
                "---`n`n" +
                $ruleBody
        }
    }
    Set-Content -LiteralPath $Destination -Value $content -NoNewline
    Copy-Item -LiteralPath $referenceSource -Destination $referenceDestination -Recurse -Force
    Write-Host "Installed rule: $Destination"
}

function Install-AgentPointer {
    $skillDestination = Join-Path $targetRoot '.agents/skills/clean-code-refactor'
    Copy-SkillFolder $skillDestination

    $agentsPath = Join-Path $targetRoot 'AGENTS.md'
    $marker = '<!-- clean-code-refactor-skill -->'
    $pointer = @"

$marker
## Clean Code Refactor

For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.agents/skills/clean-code-refactor/SKILL.md`.
<!-- /clean-code-refactor-skill -->
"@
    if (-not (Test-Path -LiteralPath $agentsPath)) {
        Set-Content -LiteralPath $agentsPath -Value ($pointer.TrimStart()) -NoNewline
        Write-Host "Created agent pointer: $agentsPath"
    } elseif ((Get-Content -LiteralPath $agentsPath -Raw) -notmatch [regex]::Escape($marker)) {
        Add-Content -LiteralPath $agentsPath -Value $pointer
        Write-Host "Added agent pointer: $agentsPath"
    }
}

function Install-CopilotPointer {
    $instructionsPath = Join-Path $targetRoot '.github/copilot-instructions.md'
    $marker = '<!-- clean-code-refactor-skill -->'
    $pointer = @"

$marker
## Clean Code Refactor

For refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow `.github/skills/clean-code-refactor/SKILL.md`.
<!-- /clean-code-refactor-skill -->
"@
    if (-not (Test-Path -LiteralPath $instructionsPath)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $instructionsPath) -Force | Out-Null
        Set-Content -LiteralPath $instructionsPath -Value ($pointer.TrimStart()) -NoNewline
        Write-Host "Created Copilot pointer: $instructionsPath"
    } elseif ((Get-Content -LiteralPath $instructionsPath -Raw) -notmatch [regex]::Escape($marker)) {
        Add-Content -LiteralPath $instructionsPath -Value $pointer
        Write-Host "Added Copilot pointer: $instructionsPath"
    }
}

function Install-KiloRule {
    $rulePath = Join-Path $targetRoot '.kilo/rules/clean-code-refactor.md'
    Install-RuleFile $rulePath

    $configPath = Join-Path $targetRoot 'kilo.jsonc'
    $ruleReference = '.kilo/rules/clean-code-refactor.md'
    if (-not (Test-Path -LiteralPath $configPath)) {
        $config = "{`n  `"instructions`": [`n    `"$ruleReference`"`n  ]`n}`n"
        Set-Content -LiteralPath $configPath -Value $config -NoNewline
        Write-Host "Created Kilo Code configuration: $configPath"
    } elseif ((Get-Content -LiteralPath $configPath -Raw) -notmatch [regex]::Escape($ruleReference)) {
        Write-Warning "Add `"$ruleReference`" to the instructions array in $configPath to enable the Kilo Code rule."
    }
}

$requestedEditors = if ($Editor -contains 'all') {
    @('agents', 'cursor', 'copilot', 'claude', 'windsurf', 'cline', 'roo', 'continue', 'amazonq', 'opencode', 'kilo')
} else {
    $Editor
}

foreach ($selectedEditor in $requestedEditors | Select-Object -Unique) {
    switch ($selectedEditor) {
        'agents' { Install-AgentPointer }
        'cursor' { Install-RuleFile (Join-Path $targetRoot '.cursor/rules/clean-code-refactor.mdc') 'cursor' }
        'copilot' {
            Copy-SkillFolder (Join-Path $targetRoot '.github/skills/clean-code-refactor')
            Install-CopilotPointer
        }
        'claude' { Copy-SkillFolder (Join-Path $targetRoot '.claude/skills/clean-code-refactor') }
        'codex' { Copy-SkillFolder (Join-Path $CodexHome 'skills/clean-code-refactor') }
        'windsurf' { Install-RuleFile (Join-Path $targetRoot '.windsurf/rules/clean-code-refactor.md') }
        'cline' { Install-RuleFile (Join-Path $targetRoot '.clinerules/clean-code-refactor.md') }
        'roo' { Install-RuleFile (Join-Path $targetRoot '.roo/rules/clean-code-refactor.md') }
        'continue' { Install-RuleFile (Join-Path $targetRoot '.continue/rules/clean-code-refactor.md') 'continue' }
        'amazonq' { Install-RuleFile (Join-Path $targetRoot '.amazonq/rules/clean-code-refactor.md') }
        'opencode' { Copy-SkillFolder (Join-Path $targetRoot '.opencode/skills/clean-code-refactor') }
        'kilo' { Install-KiloRule }
    }
}
