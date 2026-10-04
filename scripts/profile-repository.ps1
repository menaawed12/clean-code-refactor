<#
.SYNOPSIS
    Profiles a repository to suggest a review profile. Local and read-only.

.DESCRIPTION
    Bounded, pre-pruned directory walk (fixes recursive-enumeration filtering):
      - Excluded directories are pruned BEFORE descent; reparse points are not followed.
      - Portable path handling (no Windows-only separators in filtering).
      - Bounds: file count, depth, per-file read size, and wall-clock time.
      - Reports pruned/skipped/error counts and an explicit incomplete status.

    Discovery improvements:
      - Finds nested projects (manifests at any bounded depth), not only root manifests.
      - Detects shell scripts. Distinguishes configured checks (e.g. .github/workflows
        with actual workflow files) from directory-name hints.
      - Filename/directory risk signals are computed from path tokens and labeled with
        evidence and confidence; documentation-only matches are reported separately
        as documentation hints instead of code risks.

.PARAMETER Path
    Repository root to profile.

.PARAMETER OutputFormat
    'Markdown' (default) or 'Json'.

.PARAMETER MaxFiles
    Maximum number of files inspected (100..100000; default 20000).

.PARAMETER MaxDepth
    Maximum directory depth below the root (1..64; default 12).

.PARAMETER MaxFileBytes
    Maximum bytes read per manifest file (default 524288).

.PARAMETER TimeoutSeconds
    Wall-clock budget for the walk (default 30). Exceeding it marks the report incomplete.
#>
# MaxFileBytes is read by Read-BoundedText through script scope, which the analyzer cannot follow.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MaxFileBytes', Justification = 'Read by Read-BoundedText through script scope.')]
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,

    [ValidateSet('Markdown', 'Json')]
    [string]$OutputFormat = 'Markdown',

    [ValidateRange(100, 100000)]
    [int]$MaxFiles = 20000,

    [ValidateRange(1, 64)]
    [int]$MaxDepth = 12,

    [ValidateRange(1024, 10485760)]
    [int]$MaxFileBytes = 524288,

    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')

$excludedDirectories = @{
    '.git' = $true; 'node_modules' = $true; 'vendor' = $true; 'bower_components' = $true
    'bin' = $true; 'obj' = $true; 'dist' = $true; 'build' = $true; 'out' = $true; 'target' = $true
    '.venv' = $true; 'venv' = $true; '__pycache__' = $true; '.tox' = $true
    '.mypy_cache' = $true; '.pytest_cache' = $true; 'site-packages' = $true
    '.gradle' = $true; '.idea' = $true; '.vs' = $true; 'packages' = $true; 'Pods' = $true
    '.terraform' = $true; '.dart_tool' = $true; '.next' = $true; '.nuxt' = $true
    'coverage' = $true; '.cache' = $true; '.bundle' = $true
}

$codeExtensions = @('.py', '.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx', '.java', '.kt', '.kts', '.scala',
    '.cs', '.vb', '.fs', '.go', '.rs', '.c', '.h', '.cpp', '.hpp', '.cc', '.m', '.mm', '.php', '.rb',
    '.swift', '.dart', '.ex', '.exs', '.erl', '.hrl', '.clj', '.cljs', '.hs', '.lua', '.pl', '.pm',
    '.r', '.jl', '.sql', '.sh', '.bash', '.zsh', '.fish', '.ps1', '.psm1', '.psd1', '.tf', '.hcl',
    '.yml', '.yaml', '.json', '.toml', '.gradle', '.groovy')
$docExtensions = @('.md', '.mdx', '.rst', '.txt', '.adoc')

$manifestNames = @{
    'package.json' = $true; 'pyproject.toml' = $true; 'requirements.txt' = $true; 'Pipfile' = $true
    'setup.py' = $true; 'pom.xml' = $true; 'build.gradle' = $true; 'build.gradle.kts' = $true
    'settings.gradle' = $true; 'settings.gradle.kts' = $true; 'Cargo.toml' = $true; 'go.mod' = $true
    'Gemfile' = $true; 'composer.json' = $true; 'pubspec.yaml' = $true; 'global.json' = $true
    'tsconfig.json' = $true; 'jsconfig.json' = $true
}

$checkNames = @{
    '.eslintrc' = 'ESLint'; '.eslintrc.js' = 'ESLint'; '.eslintrc.json' = 'ESLint'; '.eslintrc.yml' = 'ESLint'
    'eslint.config.js' = 'ESLint'; 'eslint.config.mjs' = 'ESLint'; 'eslint.config.ts' = 'ESLint'
    '.prettierrc' = 'Prettier'; 'prettier.config.js' = 'Prettier'
    'pytest.ini' = 'Pytest'; 'tox.ini' = 'Pytest/tox'; 'conftest.py' = 'Pytest'
    '.pre-commit-config.yaml' = 'Pre-commit'; 'Dockerfile' = 'Docker'; 'docker-compose.yml' = 'Docker'
    'docker-compose.yaml' = 'Docker'; 'kustomization.yaml' = 'Kustomize'; 'Chart.yaml' = 'Helm'
    'Makefile' = 'Make'; '.gitlab-ci.yml' = 'GitLab CI'; 'azure-pipelines.yml' = 'Azure Pipelines'
    'jest.config.js' = 'Jest'; 'jest.config.ts' = 'Jest'; 'vitest.config.ts' = 'Vitest'
    'tsconfig.json' = 'TypeScript'; 'phpstan.neon' = 'PHPStan'; '.rubocop.yml' = 'RuboCop'
    '.golangci.yml' = 'golangci-lint'; 'clippy.toml' = 'Clippy'; '.swiftlint.yml' = 'SwiftLint'
}

$authTokens = @{ 'auth' = $true; 'authn' = $true; 'authz' = $true; 'authentication' = $true
    'authorization' = $true; 'identity' = $true; 'permission' = $true; 'permissions' = $true
    'rbac' = $true; 'oauth' = $true; 'jwt' = $true; 'sso' = $true }
$schemaTokens = @{ 'migration' = $true; 'migrations' = $true; 'schema' = $true; 'seed' = $true; 'seeds' = $true }
$paymentTokens = @{ 'payment' = $true; 'payments' = $true; 'billing' = $true; 'invoice' = $true; 'checkout' = $true }
$deliveryTokens = @{ 'terraform' = $true; 'deploy' = $true; 'deployment' = $true; 'deployments' = $true
    'pipeline' = $true; 'pipelines' = $true; 'workflow' = $true; 'workflows' = $true; 'infra' = $true
    'infrastructure' = $true; 'helm' = $true; 'k8s' = $true }

$stats = [ordered]@{
    scannedFiles = 0; directoriesPruned = 0; directoriesSkipped = 0
    readErrors = 0; oversizeFiles = 0; manifestsRead = 0; shellScripts = 0
}
$script:incompleteReason = $null

$signals = [System.Collections.Generic.List[object]]::new()

function Add-Signal {
    param([string]$Category, [string]$Value, [string]$Confidence, [string]$EvidenceRelativePath)
    foreach ($signal in $signals) {
        if ($signal.category -eq $Category -and $signal.value -eq $Value) {
            if ($EvidenceRelativePath -and $signal.evidence.Count -lt 5 -and -not $signal.evidence.Contains($EvidenceRelativePath)) {
                $signal.evidence.Add($EvidenceRelativePath)
                if ($signal.confidence -eq 'low' -and $Confidence -eq 'high') { $signal.confidence = 'high' }
            }
            return
        }
    }
    $evidence = [System.Collections.Generic.List[string]]::new()
    if ($EvidenceRelativePath) { $evidence.Add($EvidenceRelativePath) }
    $signals.Add([pscustomobject]@{ category = $Category; value = $Value; confidence = $Confidence; evidence = $evidence })
}

function Test-HasToken {
    param([string[]]$Tokens, [hashtable]$Set)
    foreach ($token in $Tokens) { if ($Set.ContainsKey($token)) { return $true } }
    return $false
}

function Read-BoundedText {
    param([string]$FileFullName)
    try {
        $length = (Get-Item -LiteralPath $FileFullName -Force).Length
        if ($length -gt $MaxFileBytes) { $stats.oversizeFiles++; return $null }
        $stats.manifestsRead++
        return (Get-Content -LiteralPath $FileFullName -Raw)
    } catch {
        $stats.readErrors++
        return $null
    }
}

function Add-ManifestFramework {
    param([string]$Name, [string]$Text, [string]$Relative)
    if ($null -eq $Text) { return }
    switch ($Name) {
        'package.json' {
            if ($Text -match '"(?:react|next)"') { Add-Signal -Category 'framework' -Value 'React/Next.js' -Confidence 'high' -EvidenceRelativePath $Relative }
            if ($Text -match '"@angular/') { Add-Signal -Category 'framework' -Value 'Angular' -Confidence 'high' -EvidenceRelativePath $Relative }
            if ($Text -match '"(?:vue|nuxt)"') { Add-Signal -Category 'framework' -Value 'Vue/Nuxt' -Confidence 'high' -EvidenceRelativePath $Relative }
            if ($Text -match '"(?:express|nestjs|@nestjs)"') { Add-Signal -Category 'framework' -Value 'Node/NestJS' -Confidence 'high' -EvidenceRelativePath $Relative }
        }
        'composer.json' { if ($Text -match '(?i)laravel') { Add-Signal -Category 'framework' -Value 'Laravel' -Confidence 'high' -EvidenceRelativePath $Relative } }
        'Gemfile' { if ($Text -match '(?i)rails') { Add-Signal -Category 'framework' -Value 'Rails' -Confidence 'high' -EvidenceRelativePath $Relative } }
        'pubspec.yaml' { if ($Text -match '(?i)flutter') { Add-Signal -Category 'framework' -Value 'Flutter' -Confidence 'high' -EvidenceRelativePath $Relative } }
        'pyproject.toml' {
            if ($Text -match '(?i)django') { Add-Signal -Category 'framework' -Value 'Django' -Confidence 'high' -EvidenceRelativePath $Relative }
            if ($Text -match '(?i)fastapi') { Add-Signal -Category 'framework' -Value 'FastAPI' -Confidence 'high' -EvidenceRelativePath $Relative }
            if ($Text -match '(?i)flask') { Add-Signal -Category 'framework' -Value 'Flask' -Confidence 'high' -EvidenceRelativePath $Relative }
        }
    }
}

# ------------------------------ bounded walk -------------------------------

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$stack = [System.Collections.Generic.Stack[object]]::new()
$stack.Push([pscustomobject]@{ Dir = $root; Depth = 0 })

while ($stack.Count -gt 0) {
    if ($stats.scannedFiles -ge $MaxFiles) {
        $script:incompleteReason = "file inspection limit reached ($MaxFiles files)"
        break
    }
    if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
        $script:incompleteReason = "time budget exceeded (${TimeoutSeconds}s)"
        break
    }
    $current = $stack.Pop()
    $entries = $null
    try { $entries = Get-ChildItem -LiteralPath $current.Dir -Force -ErrorAction Stop } catch { $stats.readErrors++; continue }

    foreach ($entry in $entries) {
        if ($entry.PSIsContainer) {
            $relative = $entry.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            if ($excludedDirectories.ContainsKey($entry.Name)) { $stats.directoriesPruned++; continue }
            if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $stats.directoriesSkipped++
                Add-Signal -Category 'note' -Value 'reparse point not followed' -Confidence 'info' -EvidenceRelativePath $relative
                continue
            }
            if ($current.Depth -ge $MaxDepth) { $stats.directoriesSkipped++; continue }
            $stack.Push([pscustomobject]@{ Dir = $entry.FullName; Depth = $current.Depth + 1 })
        } else {
            if ($stats.scannedFiles -ge $MaxFiles) {
                $script:incompleteReason = "file inspection limit reached ($MaxFiles files)"
                break
            }
            $stats.scannedFiles++
            $relative = $entry.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            $extension = $entry.Extension.ToLowerInvariant()

            # Manifest-based language/framework detection (any depth), bounded read.
            if ($manifestNames.ContainsKey($entry.Name)) {
                switch -Regex ($entry.Name) {
                    '^(package\.json|tsconfig\.json|jsconfig\.json)$' { Add-Signal -Category 'language' -Value 'TypeScript/JavaScript' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^(pyproject\.toml|requirements\.txt|Pipfile|setup\.py)$' { Add-Signal -Category 'language' -Value 'Python' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^(pom\.xml|build\.gradle|build\.gradle\.kts|settings\.gradle|settings\.gradle\.kts)$' { Add-Signal -Category 'language' -Value 'Java/Kotlin/Scala' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^(global\.json)$' { Add-Signal -Category 'language' -Value '.NET' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^go\.mod$' { Add-Signal -Category 'language' -Value 'Go' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^Cargo\.toml$' { Add-Signal -Category 'language' -Value 'Rust' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^composer\.json$' { Add-Signal -Category 'language' -Value 'PHP' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^Gemfile$' { Add-Signal -Category 'language' -Value 'Ruby' -Confidence 'high' -EvidenceRelativePath $relative }
                    '^pubspec\.yaml$' { Add-Signal -Category 'language' -Value 'Dart/Flutter' -Confidence 'high' -EvidenceRelativePath $relative }
                }
                if ($entry.Name -in @('package.json', 'composer.json', 'Gemfile', 'pubspec.yaml', 'pyproject.toml')) {
                    if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        # A symlinked manifest could point outside the repository; never read it.
                        Add-Signal -Category 'note' -Value 'symlinked manifest not read' -Confidence 'info' -EvidenceRelativePath $relative
                    } else {
                        $manifestText = Read-BoundedText -FileFullName $entry.FullName
                        Add-ManifestFramework -Name $entry.Name -Text $manifestText -Relative $relative
                    }
                }
            }
            if ($extension -in @('.sln', '.csproj', '.fsproj', '.vbproj')) { Add-Signal -Category 'language' -Value '.NET' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($extension -in @('.sh', '.bash', '.zsh', '.fish')) { $stats.shellScripts++; Add-Signal -Category 'language' -Value 'Shell' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($extension -eq '.ps1' -or $extension -eq '.psm1') { $stats.shellScripts++; Add-Signal -Category 'language' -Value 'PowerShell' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($entry.Name -eq 'Dockerfile' -or $extension -eq '.dockerfile') { Add-Signal -Category 'delivery' -Value 'Docker' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($extension -eq '.tf' -or $extension -eq '.tfvars') { Add-Signal -Category 'delivery' -Value 'Terraform' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($entry.Name -eq 'Chart.yaml') { Add-Signal -Category 'delivery' -Value 'Helm chart' -Confidence 'high' -EvidenceRelativePath $relative }
            if ($checkNames.ContainsKey($entry.Name)) { Add-Signal -Category 'check' -Value $checkNames[$entry.Name] -Confidence 'medium' -EvidenceRelativePath $relative }
            if ($relative -eq '.github/workflows' -or $relative -like '.github/workflows/*') {
                if ($extension -eq '.yml' -or $extension -eq '.yaml') { Add-Signal -Category 'check' -Value 'GitHub Actions' -Confidence 'high' -EvidenceRelativePath $relative }
            }

            # Token-based risk signals with documentation/code distinction.
            $isDoc = $docExtensions -contains $extension
            $isCode = $codeExtensions -contains $extension -or $extension -eq ''
            if ($isDoc -or $isCode) {
                $segments = ($relative -replace '\.[A-Za-z0-9]+$', '') -split '[\\/]+'
                $tokens = @()
                foreach ($segment in $segments) { $tokens += ($segment -split '[^A-Za-z0-9]+' | Where-Object { $_ }) }
                $tokens = @($tokens | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
                $target = if ($isDoc -and -not $isCode) { 'documentationHints' } else { 'riskSignals' }
                $confidence = if ($isDoc -and -not $isCode) { 'documentation-only' } else { 'low' }
                if (Test-HasToken -Tokens $tokens -Set $authTokens) { Add-Signal -Category $target -Value 'authentication or authorization surface' -Confidence $confidence -EvidenceRelativePath $relative }
                if (Test-HasToken -Tokens $tokens -Set $schemaTokens) { Add-Signal -Category $target -Value 'database schema or migration surface' -Confidence $confidence -EvidenceRelativePath $relative }
                if (Test-HasToken -Tokens $tokens -Set $paymentTokens) { Add-Signal -Category $target -Value 'payment or billing surface' -Confidence $confidence -EvidenceRelativePath $relative }
                if (Test-HasToken -Tokens $tokens -Set $deliveryTokens) { Add-Signal -Category $target -Value 'delivery or infrastructure surface' -Confidence $confidence -EvidenceRelativePath $relative }
            }
        }
    }
}
$stopwatch.Stop()

function Get-SignalValue {
    param([string]$Category)
    @($signals | Where-Object { $_.category -eq $Category } | Sort-Object value | ForEach-Object value)
}

# @() keeps empty and single-item results as JSON arrays; function output is unrolled.
$languages = @(Get-SignalValue -Category 'language')
$frameworks = @(Get-SignalValue -Category 'framework')
$checks = @(Get-SignalValue -Category 'check')
$delivery = @(Get-SignalValue -Category 'delivery')
$riskSignals = @(Get-SignalValue -Category 'riskSignals')
$docHints = @(Get-SignalValue -Category 'documentationHints')
$notes = @(Get-SignalValue -Category 'note')

$complete = ($null -eq $script:incompleteReason)
$profileSuggestion = if ($riskSignals.Count -gt 0) {
    'strict'
} elseif ($delivery -contains 'Terraform' -or $delivery -contains 'Helm chart') {
    'infrastructure'
} elseif ($frameworks.Count -gt 0) {
    'api-service or frontend (select by changed surface)'
} else {
    'legacy-safe or strict (select by change risk)'
}

$result = [ordered]@{
    repository = $root
    suggestedProfile = $profileSuggestion
    complete = $complete
    incompleteReason = $script:incompleteReason
    languages = $languages
    frameworks = $frameworks
    configuredChecks = $checks
    deliverySignals = $delivery
    riskSignals = $riskSignals
    documentationHints = $docHints
    notes = $notes
    signals = @($signals | Sort-Object category, value)
    stats = $stats
    note = 'Read-only discovery only. Confirm actual commands and project conventions before changing code. Documentation-only signals are labeled; verify each risk signal against real code.'
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

Write-Output "# Repository Profile"
Write-Output ""
Write-Output "- Repository: $($result.repository)"
Write-Output "- Suggested profile: $($result.suggestedProfile)"
foreach ($property in @('languages', 'frameworks', 'configuredChecks', 'deliverySignals', 'riskSignals', 'documentationHints')) {
    $label = ($property -creplace '([A-Z])', ' $1').Trim()
    $values = $result[$property]
    Write-Output "- ${label}: $(if ($values.Count) { $values -join ', ' } else { 'none detected' })"
}
foreach ($signal in ($signals | Where-Object { $_.category -in @('language', 'framework', 'check', 'delivery', 'riskSignals') } | Sort-Object category, value)) {
    Write-Output "  - $($signal.category): $($signal.value) [$($signal.confidence)] <- $($signal.evidence -join ', ')"
}
Write-Output "- Files sampled: $($stats.scannedFiles); directories pruned: $($stats.directoriesPruned); directories skipped: $($stats.directoriesSkipped); read errors: $($stats.readErrors); shell scripts: $($stats.shellScripts)"
if ($complete) {
    Write-Output "- Status: complete"
} else {
    Write-Output "- Status: INCOMPLETE ($($script:incompleteReason)). Findings may be missing; widen the bounds and rerun."
}
Write-Output "- Note: $($result.note)"
