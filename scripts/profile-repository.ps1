[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,

    [ValidateSet('Markdown', 'Json')]
    [string]$OutputFormat = 'Markdown',

    [ValidateRange(100, 100000)]
    [int]$MaxFiles = 20000
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Path).Path

$signals = [ordered]@{
    Languages = [System.Collections.Generic.List[string]]::new()
    Frameworks = [System.Collections.Generic.List[string]]::new()
    Checks = [System.Collections.Generic.List[string]]::new()
    Delivery = [System.Collections.Generic.List[string]]::new()
    Risks = [System.Collections.Generic.List[string]]::new()
}

function Add-Signal {
    param([System.Collections.Generic.List[string]]$Collection, [string]$Value)
    if (-not $Collection.Contains($Value)) { $Collection.Add($Value) }
}

$rootNames = Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop | ForEach-Object Name
$rootTextFiles = @('package.json', 'pyproject.toml', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'Cargo.toml', 'go.mod', 'Gemfile', 'composer.json', 'pubspec.yaml')
$rootText = @{}
foreach ($name in $rootTextFiles) {
    $candidate = Join-Path $root $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $rootText[$name] = Get-Content -LiteralPath $candidate -Raw -ErrorAction SilentlyContinue
    }
}

$indicators = @{
    'TypeScript/JavaScript' = @('package.json', 'tsconfig.json', 'jsconfig.json')
    'Python' = @('pyproject.toml', 'requirements.txt', 'Pipfile', 'setup.py')
    'Java/Kotlin/Scala' = @('pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts')
    '.NET' = @('global.json', 'Directory.Build.props')
    'Go' = @('go.mod')
    'Rust' = @('Cargo.toml')
    'PHP' = @('composer.json')
    'Ruby' = @('Gemfile')
    'Dart/Flutter' = @('pubspec.yaml')
    'Infrastructure' = @('terraform', 'kustomization.yaml', 'Chart.yaml', 'Dockerfile')
}
foreach ($entry in $indicators.GetEnumerator()) {
    if ($entry.Value | Where-Object { $rootNames -contains $_ }) {
        Add-Signal $signals.Languages $entry.Key
    }
}
if ((Get-ChildItem -LiteralPath $root -Filter '*.sln' -File -ErrorAction SilentlyContinue) -or (Get-ChildItem -LiteralPath $root -Filter '*.csproj' -File -ErrorAction SilentlyContinue)) { Add-Signal $signals.Languages '.NET' }

$package = $rootText['package.json']
if ($package) {
    foreach ($framework in @{ 'React/Next.js' = '"(?:react|next)"'; 'Angular' = '"@angular/'; 'Vue/Nuxt' = '"(?:vue|nuxt)"'; 'Node/NestJS' = '"(?:express|nestjs|@nestjs)"' }.GetEnumerator()) {
        if ($package -match $framework.Value) { Add-Signal $signals.Frameworks $framework.Key }
    }
}
if (($rootText['pyproject.toml'] -match '(?i)django') -or (Test-Path -LiteralPath (Join-Path $root 'manage.py'))) { Add-Signal $signals.Frameworks 'Django' }
if ($rootText['pyproject.toml'] -match '(?i)fastapi') { Add-Signal $signals.Frameworks 'FastAPI' }
if ($rootText['composer.json'] -match '(?i)laravel') { Add-Signal $signals.Frameworks 'Laravel' }
if ($rootText['Gemfile'] -match '(?i)rails') { Add-Signal $signals.Frameworks 'Rails' }
if ($rootText['pubspec.yaml'] -match '(?i)flutter') { Add-Signal $signals.Frameworks 'Flutter' }

foreach ($check in @{ 'ESLint' = @('.eslintrc', 'eslint.config.js', 'eslint.config.mjs'); 'Prettier' = @('.prettierrc', 'prettier.config.js'); 'Pytest' = @('pytest.ini', 'tox.ini'); 'GitHub Actions' = @('.github'); 'Pre-commit' = @('.pre-commit-config.yaml'); 'Docker' = @('Dockerfile', 'docker-compose.yml'); 'Terraform' = @('terraform') }.GetEnumerator()) {
    if ($check.Value | Where-Object { $rootNames -contains $_ }) { Add-Signal $signals.Checks $check.Key }
}
if ($rootNames -contains '.github') { Add-Signal $signals.Delivery 'GitHub Actions or repository automation' }
if ($rootNames -contains 'k8s' -or $rootNames -contains 'helm') { Add-Signal $signals.Delivery 'Kubernetes delivery assets' }
if ($rootNames -contains 'terraform') { Add-Signal $signals.Delivery 'Terraform infrastructure' }

$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|vendor|bin|obj|dist|build)\\' } |
    Select-Object -First $MaxFiles
$fileNames = $files.Name
if ($fileNames | Where-Object { $_ -match '(?i)(migration|schema|seed)' }) { Add-Signal $signals.Risks 'Database schema or migration files detected' }
if ($fileNames | Where-Object { $_ -match '(?i)(auth|identity|permission|policy)' }) { Add-Signal $signals.Risks 'Authentication or authorization code detected' }
if ($fileNames | Where-Object { $_ -match '(?i)(payment|billing|invoice)' }) { Add-Signal $signals.Risks 'Payment or billing code detected' }
if ($fileNames | Where-Object { $_ -match '(?i)(terraform|deployment|pipeline|workflow)' }) { Add-Signal $signals.Risks 'Delivery or infrastructure files detected' }

$profile = if ($signals.Risks.Count -gt 0) { 'strict' } elseif ($signals.Languages -contains 'Infrastructure') { 'infrastructure' } elseif ($signals.Frameworks.Count -gt 0) { 'api-service or frontend (select by changed surface)' } else { 'legacy-safe or strict (select by change risk)' }
$result = [ordered]@{
    repository = $root
    suggestedProfile = $profile
    languages = @($signals.Languages)
    frameworks = @($signals.Frameworks)
    configuredChecks = @($signals.Checks)
    deliverySignals = @($signals.Delivery)
    riskSignals = @($signals.Risks)
    scannedFiles = @($files).Count
    note = 'Read-only discovery only. Confirm actual commands and project conventions before changing code.'
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 4
    exit 0
}

Write-Output "# Repository Profile"
Write-Output ""
Write-Output "- Repository: $($result.repository)"
Write-Output "- Suggested profile: $($result.suggestedProfile)"
foreach ($property in @('languages', 'frameworks', 'configuredChecks', 'deliverySignals', 'riskSignals')) {
    $label = ($property -creplace '([A-Z])', ' $1').Trim()
    $values = $result[$property]
    Write-Output "- ${label}: $(if ($values.Count) { $values -join ', ' } else { 'none detected' })"
}
Write-Output "- Files sampled: $($result.scannedFiles)"
Write-Output "- Note: $($result.note)"
