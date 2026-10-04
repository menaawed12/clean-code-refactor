<#
.SYNOPSIS
    Regenerates the data blocks in scripts/install.sh from integrations/registry.json.

.DESCRIPTION
    The bash installer cannot parse JSON without extra dependencies, so it carries a copy of
    the registry: PKG_VERSION, TOOL_SOURCES, known_ids, and the PROJECT_TARGETS / USER_TARGETS
    tables.
    This script owns those blocks. Edit the registry, then run this script; never edit the
    blocks by hand.

    With -Check, nothing is written and the script exits 1 when install.sh is out of date.
    scripts/validate-skill.ps1 runs that check.

.PARAMETER RepositoryRoot
    Package root (defaults to the parent of this script's folder).

.PARAMETER Check
    Report drift instead of rewriting install.sh.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
if (-not $RepositoryRoot) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$registryPath = Join-Path $RepositoryRoot 'integrations/registry.json'
$installerPath = Join-Path $RepositoryRoot 'scripts/install.sh'

function Get-Prop { param($Object, [string]$Name) if ($null -eq $Object) { return $null }; $p = $Object.PSObject.Properties[$Name]; if ($p) { $p.Value } else { $null } }
function Get-OrDash { param($Value) if ($null -eq $Value -or "$Value" -eq '') { '-' } else { "$Value" } }

$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$package = Get-Prop $registry 'package'

function Get-TargetRow {
    param([string]$Id, $Definition, $ScopeDef)
    $kind = Get-Prop $ScopeDef 'kind'
    if (-not $kind) { $kind = Get-Prop $Definition 'kind' }
    $format = '-'
    if ($kind -eq 'rule-file') { $format = Get-Prop $ScopeDef 'format'; if (-not $format) { $format = 'plain' } }
    $pointer = Get-Prop $ScopeDef 'pointer'
    $config = Get-Prop $ScopeDef 'config'
    $hints = @(Get-Prop $ScopeDef 'detect' | ForEach-Object { "$(Get-Prop $_ 'root'):$(Get-Prop $_ 'path')" }) -join ','
    $columns = @(
        $Id, $kind, (Get-Prop $ScopeDef 'root'), (Get-Prop $ScopeDef 'path'), $format,
        (Get-OrDash (Get-Prop $pointer 'file')), (Get-OrDash (Get-Prop $pointer 'skillLink')),
        (Get-OrDash (Get-Prop $config 'file')), (Get-OrDash (Get-Prop $config 'entry')),
        (Get-OrDash $hints), (Get-OrDash (Get-Prop $ScopeDef 'verification'))
    )
    foreach ($column in $columns) {
        if ("$column" -match '[|\r\n]') { throw "Registry value for '$Id' contains a character the bash table cannot hold: $column" }
    }
    return $columns -join '|'
}

$projectRows = [System.Collections.Generic.List[string]]::new()
$userRows = [System.Collections.Generic.List[string]]::new()
foreach ($property in (Get-Prop $registry 'editors').PSObject.Properties) {
    $scopes = Get-Prop $property.Value 'scopes'
    $projectScope = Get-Prop $scopes 'project'
    $userScope = Get-Prop $scopes 'user'
    if ($null -ne $projectScope) { $projectRows.Add((Get-TargetRow -Id $property.Name -Definition $property.Value -ScopeDef $projectScope)) }
    if ($null -ne $userScope) { $userRows.Add((Get-TargetRow -Id $property.Name -Definition $property.Value -ScopeDef $userScope)) }
}

$toolList = (@(Get-Prop $package 'toolSources') | ForEach-Object { "'$_'" }) -join ' '
$knownIds = @((Get-Prop $registry 'editors').PSObject.Properties.Name) -join ' '
$original = [System.IO.File]::ReadAllText($installerPath)
$updated = $original
$replacements = @(
    @{ Pattern = "(?m)^PKG_VERSION='[^']*'"; Value = "PKG_VERSION='$(Get-Prop $package 'version')'" },
    @{ Pattern = '(?m)^TOOL_SOURCES=\([^)]*\)'; Value = "TOOL_SOURCES=($toolList)" },
    @{ Pattern = '(?m)^known_ids="[^"]*"'; Value = "known_ids=`"$knownIds`"" },
    @{ Pattern = "(?s)(PROJECT_TARGETS=\`$\(cat <<'PROJECT_TARGETS_EOF'\n).*?(\nPROJECT_TARGETS_EOF)"; Value = "`${1}$($projectRows -join "`n")`${2}" },
    @{ Pattern = "(?s)(USER_TARGETS=\`$\(cat <<'USER_TARGETS_EOF'\n).*?(\nUSER_TARGETS_EOF)"; Value = "`${1}$($userRows -join "`n")`${2}" }
)
foreach ($replacement in $replacements) {
    if (-not [regex]::IsMatch($updated, $replacement.Pattern)) { throw "scripts/install.sh is missing the block matched by: $($replacement.Pattern)" }
    $updated = [regex]::Replace($updated, $replacement.Pattern, $replacement.Value.Replace('$', '$$').Replace('$${1}', '${1}').Replace('$${2}', '${2}'))
}

if ($updated -eq $original) {
    Write-Output 'scripts/install.sh is in sync with integrations/registry.json.'
    exit 0
}
if ($Check) {
    Write-Output 'scripts/install.sh is out of sync with integrations/registry.json. Run: pwsh ./scripts/sync-bash-installer.ps1'
    exit 1
}
[System.IO.File]::WriteAllText($installerPath, $updated, [System.Text.UTF8Encoding]::new($false))
Write-Output 'Updated scripts/install.sh from integrations/registry.json.'
