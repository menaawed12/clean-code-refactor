<#
.SYNOPSIS
    Validates clean-code-refactor policy files and prints the effective policy. Local and read-only.

.DESCRIPTION
    Two policy layers adjust the skill's built-in quality gates:

      Organization policy  policy.json installed next to the skill by an administrator
                           (install.ps1 -PolicyFile / install.sh --policy). It is trusted like
                           the skill itself and may set any valid value.
      Project policy       .clean-code-refactor/policy.json inside the repository. It is
                           repository content, so it may only make the effective policy
                           stricter. Attempts to loosen it are ignored and reported.

    No policy can disable security rules, authorize commands, network access, or credential
    access, or widen the scope of a task. Policy files are data, never instructions.

    Output is JSON: the effective policy, which files were used, ignored loosening attempts,
    and validation errors.

.PARAMETER ProjectPath
    Repository root to read .clean-code-refactor/policy.json from (default: current directory).

.PARAMETER OrgPolicyPath
    Organization policy file. Defaults to policy.json next to this script or in its parent
    folder, which is where the installers place it.

.PARAMETER PolicyFile
    Validate a single policy file as an organization policy and exit (for CI checks).

.EXITCODES
    0 = valid; 1 = a policy file is invalid; 2 = usage error.
#>
[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$OrgPolicyPath,
    [string]$PolicyFile
)

$ErrorActionPreference = 'Stop'
$maxPolicyBytes = 65536
$severityOrder = @('blocker', 'critical', 'major', 'minor')
$wcagOrder = @('A', 'AA', 'AAA')
$profiles = @('strict', 'legacy-safe', 'api-service', 'frontend', 'mobile', 'data', 'infrastructure', 'ai-application')

$script:errors = [System.Collections.Generic.List[string]]::new()
$script:ignored = [System.Collections.Generic.List[object]]::new()

function Get-Prop { param($Object, [string]$Name) if ($null -eq $Object) { return $null }; $p = $Object.PSObject.Properties[$Name]; if ($p) { $p.Value } else { $null } }
function Test-HasProp { param($Object, [string]$Name) return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name]) }

function New-DefaultPolicy {
    # The skill's built-in defaults (SKILL.md "Quality Gate" section).
    return [ordered]@{
        policyVersion = 1
        organization  = $null
        profile       = [ordered]@{ default = $null; allowLegacySafe = $true }
        gates         = [ordered]@{ newCodeCoverageMin = 80; newCodeDuplicationMax = 3; blockingSeverities = @('blocker', 'critical') }
        standards     = [ordered]@{ asvsLevel = $null; wcagLevel = 'AA' }
        bannedApis    = @()
        dependencies  = [ordered]@{ allowedRegistries = @(); requireApprovalForNew = $false; minimumReleaseAgeDays = 0 }
        exceptions    = [ordered]@{ requireTicket = $false; ticketPattern = $null }
        reporting     = [ordered]@{ sarif = $false; standardsTags = $true }
    }
}

function Add-PolicyError { param([string]$Source, [string]$Message) $script:errors.Add("${Source}: $Message") }

function Read-PolicyFile {
    param([string]$Path, [string]$Source)
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { Add-PolicyError $Source 'is a symlink; refusing to read it'; return $null }
    if ($item.Length -gt $maxPolicyBytes) { Add-PolicyError $Source "is larger than $maxPolicyBytes bytes"; return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json
    } catch {
        Add-PolicyError $Source "is not valid JSON ($($_.Exception.Message))"
        return $null
    }
}

function Test-AllowedKey {
    param($Object, [string[]]$Allowed, [string]$Source, [string]$Where)
    if ($null -eq $Object) { return }
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { Add-PolicyError $Source "$Where must be an object"; return }
    foreach ($name in $Object.PSObject.Properties.Name) {
        if ($Allowed -notcontains $name) { Add-PolicyError $Source "$Where has unknown field '$name'" }
    }
}

function Test-Bool { param($Value, [string]$Source, [string]$Where) if ($Value -isnot [bool]) { Add-PolicyError $Source "$Where must be true or false" } }
function Test-IntRange {
    param($Value, [int]$Min, [int]$Max, [string]$Source, [string]$Where)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Min -or $Value -gt $Max) { Add-PolicyError $Source "$Where must be a whole number from $Min to $Max" }
}

function Test-Policy {
    # Structural validation; returns $true when the policy can be applied.
    param($Policy, [string]$Source)
    $before = $script:errors.Count
    if ($Policy -isnot [System.Management.Automation.PSCustomObject]) { Add-PolicyError $Source 'must be a JSON object'; return $false }
    Test-AllowedKey $Policy @('$schema', 'policyVersion', 'organization', 'profile', 'gates', 'standards', 'bannedApis', 'dependencies', 'exceptions', 'reporting') $Source 'policy'
    if ((Get-Prop $Policy 'policyVersion') -ne 1) { Add-PolicyError $Source 'policyVersion must be 1' }
    if ((Test-HasProp $Policy 'organization') -and (Get-Prop $Policy 'organization') -isnot [string]) { Add-PolicyError $Source 'organization must be a string' }

    $profileSection = Get-Prop $Policy 'profile'
    Test-AllowedKey $profileSection @('default', 'allowLegacySafe') $Source 'profile'
    if ((Test-HasProp $profileSection 'default') -and $profiles -notcontains (Get-Prop $profileSection 'default')) { Add-PolicyError $Source "profile.default must be one of: $($profiles -join ', ')" }
    if (Test-HasProp $profileSection 'allowLegacySafe') { Test-Bool (Get-Prop $profileSection 'allowLegacySafe') $Source 'profile.allowLegacySafe' }

    $gates = Get-Prop $Policy 'gates'
    Test-AllowedKey $gates @('newCodeCoverageMin', 'newCodeDuplicationMax', 'blockingSeverities') $Source 'gates'
    if (Test-HasProp $gates 'newCodeCoverageMin') { Test-IntRange (Get-Prop $gates 'newCodeCoverageMin') 0 100 $Source 'gates.newCodeCoverageMin' }
    if (Test-HasProp $gates 'newCodeDuplicationMax') { Test-IntRange (Get-Prop $gates 'newCodeDuplicationMax') 0 100 $Source 'gates.newCodeDuplicationMax' }
    if (Test-HasProp $gates 'blockingSeverities') {
        $severities = @(Get-Prop $gates 'blockingSeverities')
        if ($severities.Count -eq 0 -or @($severities | Where-Object { $severityOrder -notcontains $_ }).Count -gt 0) { Add-PolicyError $Source "gates.blockingSeverities must list one or more of: $($severityOrder -join ', ')" }
        elseif ($severities -notcontains 'blocker') { Add-PolicyError $Source 'gates.blockingSeverities must include blocker' }
    }

    $standards = Get-Prop $Policy 'standards'
    Test-AllowedKey $standards @('asvsLevel', 'wcagLevel') $Source 'standards'
    if (Test-HasProp $standards 'asvsLevel') { Test-IntRange (Get-Prop $standards 'asvsLevel') 1 3 $Source 'standards.asvsLevel' }
    if ((Test-HasProp $standards 'wcagLevel') -and $wcagOrder -cnotcontains (Get-Prop $standards 'wcagLevel')) { Add-PolicyError $Source 'standards.wcagLevel must be A, AA, or AAA' }

    if (Test-HasProp $Policy 'bannedApis') {
        $ids = @{}
        foreach ($entry in @(Get-Prop $Policy 'bannedApis')) {
            Test-AllowedKey $entry @('id', 'text', 'languages', 'reason') $Source 'bannedApis entry'
            $id = Get-Prop $entry 'id'
            if ($id -isnot [string] -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { Add-PolicyError $Source 'bannedApis entries need an id of letters, digits, dot, underscore, or hyphen'; continue }
            if ($ids.ContainsKey($id)) { Add-PolicyError $Source "bannedApis id '$id' is duplicated" }
            $ids[$id] = $true
            $text = Get-Prop $entry 'text'
            if ($text -isnot [string] -or $text.Length -lt 2 -or $text.Length -gt 200) { Add-PolicyError $Source "bannedApis '$id' needs literal text of 2 to 200 characters" }
            if ((Get-Prop $entry 'reason') -isnot [string]) { Add-PolicyError $Source "bannedApis '$id' needs a reason" }
            if ((Test-HasProp $entry 'languages') -and @(Get-Prop $entry 'languages' | Where-Object { $_ -isnot [string] }).Count -gt 0) { Add-PolicyError $Source "bannedApis '$id' languages must be strings" }
        }
    }

    $dependencies = Get-Prop $Policy 'dependencies'
    Test-AllowedKey $dependencies @('allowedRegistries', 'requireApprovalForNew', 'minimumReleaseAgeDays') $Source 'dependencies'
    if (Test-HasProp $dependencies 'allowedRegistries') {
        foreach ($registry in @(Get-Prop $dependencies 'allowedRegistries')) {
            if ($registry -isnot [string] -or $registry -notmatch '^https://[^\s/]+(/\S*)?$') { Add-PolicyError $Source "dependencies.allowedRegistries entries must be https URLs ($registry)" }
        }
    }
    if (Test-HasProp $dependencies 'requireApprovalForNew') { Test-Bool (Get-Prop $dependencies 'requireApprovalForNew') $Source 'dependencies.requireApprovalForNew' }
    if (Test-HasProp $dependencies 'minimumReleaseAgeDays') { Test-IntRange (Get-Prop $dependencies 'minimumReleaseAgeDays') 0 365 $Source 'dependencies.minimumReleaseAgeDays' }

    $exceptions = Get-Prop $Policy 'exceptions'
    Test-AllowedKey $exceptions @('requireTicket', 'ticketPattern') $Source 'exceptions'
    if (Test-HasProp $exceptions 'requireTicket') { Test-Bool (Get-Prop $exceptions 'requireTicket') $Source 'exceptions.requireTicket' }
    if (Test-HasProp $exceptions 'ticketPattern') {
        $pattern = Get-Prop $exceptions 'ticketPattern'
        if ($pattern -isnot [string] -or $pattern.Length -gt 200) { Add-PolicyError $Source 'exceptions.ticketPattern must be a regular expression of at most 200 characters' }
        else { try { [void][regex]::new($pattern) } catch { Add-PolicyError $Source 'exceptions.ticketPattern is not a valid regular expression' } }
    }

    $reporting = Get-Prop $Policy 'reporting'
    Test-AllowedKey $reporting @('sarif', 'standardsTags') $Source 'reporting'
    foreach ($name in @('sarif', 'standardsTags')) { if (Test-HasProp $reporting $name) { Test-Bool (Get-Prop $reporting $name) $Source "reporting.$name" } }

    return $script:errors.Count -eq $before
}

function Set-OrgPolicy {
    # A trusted organization policy replaces any default it sets.
    param($Effective, $Policy)
    if (Test-HasProp $Policy 'organization') { $Effective.organization = Get-Prop $Policy 'organization' }
    foreach ($section in @('profile', 'gates', 'standards', 'dependencies', 'exceptions', 'reporting')) {
        $values = Get-Prop $Policy $section
        if ($null -eq $values) { continue }
        foreach ($name in $values.PSObject.Properties.Name) { $Effective[$section][$name] = $values.$name }
    }
    if (Test-HasProp $Policy 'bannedApis') { $Effective.bannedApis = @(Get-Prop $Policy 'bannedApis') }
    $Effective.gates.blockingSeverities = @($severityOrder | Where-Object { @($Effective.gates.blockingSeverities) -contains $_ })
}

function Add-Ignored { param([string]$Field, $Value, [string]$Reason) $script:ignored.Add([ordered]@{ field = $Field; value = $Value; reason = $Reason }) }

function Merge-ProjectPolicy {
    # Repository content may only tighten: each rule below keeps the stricter value.
    param($Effective, $Policy)
    $gates = Get-Prop $Policy 'gates'
    if (Test-HasProp $gates 'newCodeCoverageMin') {
        $value = Get-Prop $gates 'newCodeCoverageMin'
        if ($value -ge $Effective.gates.newCodeCoverageMin) { $Effective.gates.newCodeCoverageMin = $value } else { Add-Ignored 'gates.newCodeCoverageMin' $value 'lower than the organization or default minimum' }
    }
    if (Test-HasProp $gates 'newCodeDuplicationMax') {
        $value = Get-Prop $gates 'newCodeDuplicationMax'
        if ($value -le $Effective.gates.newCodeDuplicationMax) { $Effective.gates.newCodeDuplicationMax = $value } else { Add-Ignored 'gates.newCodeDuplicationMax' $value 'higher than the organization or default maximum' }
    }
    if (Test-HasProp $gates 'blockingSeverities') {
        $union = @($Effective.gates.blockingSeverities) + @(Get-Prop $gates 'blockingSeverities')
        $Effective.gates.blockingSeverities = @($severityOrder | Where-Object { $union -contains $_ })
    }

    $standards = Get-Prop $Policy 'standards'
    if (Test-HasProp $standards 'asvsLevel') {
        $value = Get-Prop $standards 'asvsLevel'
        if ($null -eq $Effective.standards.asvsLevel -or $value -ge $Effective.standards.asvsLevel) { $Effective.standards.asvsLevel = $value } else { Add-Ignored 'standards.asvsLevel' $value 'lower than the organization level' }
    }
    if (Test-HasProp $standards 'wcagLevel') {
        $value = Get-Prop $standards 'wcagLevel'
        if ($wcagOrder.IndexOf($value) -ge $wcagOrder.IndexOf($Effective.standards.wcagLevel)) { $Effective.standards.wcagLevel = $value } else { Add-Ignored 'standards.wcagLevel' $value 'lower than the organization or default level' }
    }

    if (Test-HasProp $Policy 'bannedApis') {
        $known = @($Effective.bannedApis | ForEach-Object { Get-Prop $_ 'id' })
        foreach ($entry in @(Get-Prop $Policy 'bannedApis')) {
            if ($known -contains (Get-Prop $entry 'id')) { Add-Ignored "bannedApis.$(Get-Prop $entry 'id')" (Get-Prop $entry 'text') 'the organization policy already defines this id' }
            else { $Effective.bannedApis = @($Effective.bannedApis) + $entry }
        }
    }

    $dependencies = Get-Prop $Policy 'dependencies'
    if (Test-HasProp $dependencies 'allowedRegistries') {
        $requested = @(Get-Prop $dependencies 'allowedRegistries')
        $current = @($Effective.dependencies.allowedRegistries)
        if ($current.Count -eq 0) {
            $Effective.dependencies.allowedRegistries = $requested
        } else {
            $narrowed = @($requested | Where-Object { $current -contains $_ })
            foreach ($registry in @($requested | Where-Object { $current -notcontains $_ })) { Add-Ignored 'dependencies.allowedRegistries' $registry 'not in the organization allowlist' }
            if ($narrowed.Count -gt 0) { $Effective.dependencies.allowedRegistries = $narrowed }
        }
    }
    if ((Get-Prop $dependencies 'requireApprovalForNew') -eq $true) { $Effective.dependencies.requireApprovalForNew = $true }
    elseif ((Get-Prop $dependencies 'requireApprovalForNew') -eq $false -and $Effective.dependencies.requireApprovalForNew) { Add-Ignored 'dependencies.requireApprovalForNew' $false 'cannot be switched off by a project policy' }
    if (Test-HasProp $dependencies 'minimumReleaseAgeDays') {
        $value = Get-Prop $dependencies 'minimumReleaseAgeDays'
        if ($value -ge $Effective.dependencies.minimumReleaseAgeDays) { $Effective.dependencies.minimumReleaseAgeDays = $value } else { Add-Ignored 'dependencies.minimumReleaseAgeDays' $value 'shorter than the organization minimum' }
    }

    $exceptions = Get-Prop $Policy 'exceptions'
    if ((Get-Prop $exceptions 'requireTicket') -eq $true) { $Effective.exceptions.requireTicket = $true }
    elseif ((Get-Prop $exceptions 'requireTicket') -eq $false -and $Effective.exceptions.requireTicket) { Add-Ignored 'exceptions.requireTicket' $false 'cannot be switched off by a project policy' }
    if (Test-HasProp $exceptions 'ticketPattern') { Add-Ignored 'exceptions.ticketPattern' (Get-Prop $exceptions 'ticketPattern') 'only an organization policy may define the ticket pattern' }

    $reporting = Get-Prop $Policy 'reporting'
    foreach ($name in @('sarif', 'standardsTags')) {
        if ((Get-Prop $reporting $name) -eq $true) { $Effective.reporting[$name] = $true }
        elseif ((Get-Prop $reporting $name) -eq $false -and $Effective.reporting[$name]) { Add-Ignored "reporting.$name" $false 'cannot be switched off by a project policy' }
    }

    $profileSection = Get-Prop $Policy 'profile'
    if ((Get-Prop $profileSection 'allowLegacySafe') -eq $false) { $Effective.profile.allowLegacySafe = $false }
    elseif ((Get-Prop $profileSection 'allowLegacySafe') -eq $true -and -not $Effective.profile.allowLegacySafe) { Add-Ignored 'profile.allowLegacySafe' $true 'the organization policy forbids legacy-safe' }
    if (Test-HasProp $profileSection 'default') {
        $value = Get-Prop $profileSection 'default'
        if ($value -eq 'legacy-safe' -and -not $Effective.profile.allowLegacySafe) { Add-Ignored 'profile.default' $value 'the organization policy forbids legacy-safe' }
        else { $Effective.profile.default = $value }
    }
    if (Test-HasProp $Policy 'organization') { Add-Ignored 'organization' (Get-Prop $Policy 'organization') 'only an organization policy may name the organization' }
}

# ------------------------------------------------------------------ main

if ($PolicyFile) {
    if (-not (Test-Path -LiteralPath $PolicyFile -PathType Leaf)) { Write-Error "Policy file not found: $PolicyFile" -ErrorAction Continue; exit 2 }
    $policy = Read-PolicyFile -Path $PolicyFile -Source $PolicyFile
    if ($null -ne $policy) { [void](Test-Policy -Policy $policy -Source $PolicyFile) }
    [ordered]@{ file = $PolicyFile; valid = ($script:errors.Count -eq 0); errors = @($script:errors) } | ConvertTo-Json -Depth 4
    if ($script:errors.Count -gt 0) { exit 1 }
    exit 0
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { Write-Error "Project path is not a directory: $ProjectPath" -ErrorAction Continue; exit 2 }

if (-not $OrgPolicyPath) {
    foreach ($candidate in @((Join-Path $PSScriptRoot 'policy.json'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.json'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $OrgPolicyPath = $candidate; break }
    }
} elseif (-not (Test-Path -LiteralPath $OrgPolicyPath -PathType Leaf)) {
    Write-Error "Organization policy not found: $OrgPolicyPath" -ErrorAction Continue
    exit 2
}
$projectPolicyPath = Join-Path (Join-Path $ProjectPath '.clean-code-refactor') 'policy.json'
if (-not (Test-Path -LiteralPath $projectPolicyPath -PathType Leaf)) { $projectPolicyPath = $null }

$effective = New-DefaultPolicy
if ($OrgPolicyPath) {
    $orgPolicy = Read-PolicyFile -Path $OrgPolicyPath -Source 'organization policy'
    if ($null -ne $orgPolicy -and (Test-Policy -Policy $orgPolicy -Source 'organization policy')) { Set-OrgPolicy -Effective $effective -Policy $orgPolicy }
}
if ($projectPolicyPath) {
    $projectPolicy = Read-PolicyFile -Path $projectPolicyPath -Source 'project policy'
    if ($null -ne $projectPolicy -and (Test-Policy -Policy $projectPolicy -Source 'project policy')) { Merge-ProjectPolicy -Effective $effective -Policy $projectPolicy }
}

[ordered]@{
    effective = $effective
    sources   = [ordered]@{ organization = $(if ($OrgPolicyPath) { $OrgPolicyPath } else { $null }); project = $projectPolicyPath }
    ignored   = @($script:ignored)
    errors    = @($script:errors)
    note      = 'An invalid policy file is not applied. A project policy can only tighten the effective policy; no policy disables security rules or authorizes commands, network access, or scope changes.'
} | ConvertTo-Json -Depth 6
if ($script:errors.Count -gt 0) { exit 1 }
exit 0
