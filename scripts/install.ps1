<#
.SYNOPSIS
    Installs the clean-code-refactor skill into editor/agent targets.

.DESCRIPTION
    Registry-driven, preflighted installer (see integrations/registry.json):
      - One path transformation for rule files; every generated local link is validated (no double prefixes).
      - Upgrades are receipt/hash-based: owned files are updated, stale owned files are removed,
        unrelated files are preserved. User modifications are detected and not overwritten without -Force.
      - Preflight containment: destinations must resolve inside their declared root and must not
        traverse reparse points (symlinks/junctions). Preflight failures abort before any write.

.PARAMETER Editor
    Target id, or 'all' (every target for the scope), or 'detected'
    (targets whose editor configuration directory already exists).

.PARAMETER Scope
    'project' (default) or 'user' (per-user global install where the registry declares it).

.PARAMETER TargetPath
    Project directory for project-scope targets.

.PARAMETER CodexHome
    Codex home directory (default $env:CODEX_HOME or ~/.codex).

.PARAMETER UserHome
    User home directory for user-scope targets (default $HOME). Override for tests/portable installs.

.PARAMETER DryRun
    Print the plan without writing anything. Alias: -WhatIf.

.PARAMETER Force
    Replace this skill's previously installed files, including user-modified owned files.

.PARAMETER List
    List registry targets and exit.

.PARAMETER PolicyFile
    Organization policy (JSON) to install next to the skill as policy.json. It is validated with
    scripts/check-policy.ps1 first. Later runs without -PolicyFile keep the installed policy.

.PARAMETER OutputFormat
    'Text' (default) or 'Json' (machine-readable plan/result).

.EXITCODES
    0 = all requested targets installed/updated or intentionally skipped.
    1 = one or more targets failed during execution.
    2 = usage error, missing source, or preflight abort (nothing was written).
#>
[CmdletBinding()]
param(
    # Validated dynamically against the registry (comma lists arrive as a single
    # string under powershell.exe -File, so a static ValidateSet would reject them).
    [string[]]$Editor = @('all'),

    [ValidateSet('project', 'user')]
    [string]$Scope = 'project',

    [string]$TargetPath = (Get-Location).Path,

    [string]$CodexHome = $( if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' } ),

    [string]$UserHome = $HOME,

    [Alias('WhatIf')]
    [switch]$DryRun,

    [switch]$Force,

    [switch]$List,

    [string]$PolicyFile,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

$ErrorActionPreference = 'Stop'
$script:HadFailure = $false
$isWindowsOs = ($env:OS -eq 'Windows_NT')

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-Info {
    # Human-readable progress; suppressed in Json mode so stdout stays parseable.
    param([string]$Message)
    if ($OutputFormat -eq 'Text') { Write-Host $Message }
}

function Write-Notice {
    # Human-readable warning; suppressed in Json mode so stdout stays parseable.
    param([string]$Message)
    if ($OutputFormat -eq 'Text') { Write-Warning $Message }
}

function Install-PointerFile {
    param([string]$PointerPath, [string]$SkillLink)
    $marker = '<!-- clean-code-refactor-skill -->'
    $pointerText = "`n`n$marker`n## Clean Code Refactor`n`nFor refactoring, lint remediation, duplicate detection, code hardening, and code-quality reviews, load and follow ``$SkillLink``.`n<!-- /clean-code-refactor-skill -->`n"
    if (-not (Test-Path -LiteralPath $PointerPath)) {
        $parent = Split-Path -Parent $PointerPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Set-Content -LiteralPath $PointerPath -Value $pointerText.TrimStart() -NoNewline
        Write-Info "Created pointer: $PointerPath"
    } elseif ((Get-Content -LiteralPath $PointerPath -Raw) -notmatch [regex]::Escape($marker)) {
        Add-Content -LiteralPath $PointerPath -Value $pointerText
        Write-Info "Appended pointer section: $PointerPath"
    }
}

function Set-EditorConfigEntry {
    param([string]$ConfigPath, [string]$Entry)
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $configText = "{`n  `"instructions`": [`n    `"$Entry`"`n  ]`n}`n"
        Set-Content -LiteralPath $ConfigPath -Value $configText -NoNewline
        Write-Info "Created configuration: $ConfigPath"
    } elseif ((Get-Content -LiteralPath $ConfigPath -Raw) -notmatch [regex]::Escape($Entry)) {
        Write-Notice "Add `"$Entry`" to the instructions array in $ConfigPath to enable this rule."
    }
}

function Install-AdditiveExtra {
    # Pointer sections and config entries are additive and marked; re-check them even
    # when the owned unit itself is already up to date (a user may have removed them).
    param([string]$Kind, [string]$Root, $ScopeDef)
    if ($DryRun) { return }
    $pointer = Get-Prop $ScopeDef 'pointer'
    if ($Kind -eq 'skill-folder' -and $null -ne $pointer) {
        Install-PointerFile -PointerPath (Join-UnderRoot -Root $Root -RelativePath (Get-Prop $pointer 'file')) -SkillLink (Get-Prop $pointer 'skillLink')
    }
    $config = Get-Prop $ScopeDef 'config'
    if ($Kind -eq 'rule-file' -and $null -ne $config) {
        Set-EditorConfigEntry -ConfigPath (Join-UnderRoot -Root $Root -RelativePath (Get-Prop $config 'file')) -Entry (Get-Prop $config 'entry')
    }
}

function Resolve-FullDirectoryPath {
    param([string]$PathValue)
    return [System.IO.Path]::GetFullPath($PathValue).TrimEnd('\', '/')
}

function Join-UnderRoot {
    param([string]$Root, [string]$RelativePath)
    $segments = $RelativePath -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' }
    if ($segments -contains '..') { throw "Registry path must not contain '..': $RelativePath" }
    $current = $Root
    foreach ($segment in $segments) { $current = Join-Path $current $segment }
    return $current
}

function Test-PathUnderRoot {
    param([string]$Candidate, [string]$Root)
    $prefix = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($isWindowsOs) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    return $Candidate.StartsWith($prefix, $comparison) -and $Candidate.Length -gt $prefix.Length
}

function Get-ReparseViolation {
    # Returns the first path component between root and destination that is a reparse point, or $null.
    param([string]$Destination, [string]$Root)
    if (-not (Test-PathUnderRoot -Candidate $Destination -Root $Root)) { return $Destination }
    $relative = $Destination.Substring($Root.Length).TrimStart('\', '/')
    $segments = $relative -split '[\\/]+' | Where-Object { $_ }
    $current = $Root
    foreach ($segment in $segments) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $current }
        }
    }
    return $null
}

function Get-FileSha256 {
    param([string]$PathValue)
    return (Get-FileHash -LiteralPath $PathValue -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DirectoryFileMap {
    # Relative path (slash-separated) -> sha256, for every file under a directory.
    param([string]$Directory)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $map }
    foreach ($file in (Get-ChildItem -LiteralPath $Directory -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($Directory.Length).TrimStart('\', '/').Replace('\', '/')
        $map[$relative] = Get-FileSha256 -PathValue $file.FullName
    }
    return $map
}

function Get-SourceFileMap {
    # Canonical owned files: [relative path] -> sha256, computed from the package sources.
    param($Package, [string]$SkillSource, [string]$ReferenceDir, [string]$RepositoryRoot)
    $map = @{}
    $map[(Get-Prop $Package 'canonicalSkillFile')] = Get-FileSha256 -PathValue $SkillSource
    foreach ($entry in (Get-DirectoryFileMap -Directory $ReferenceDir).GetEnumerator()) {
        $map["$((Get-Prop $Package 'referenceDir'))/$($entry.Key)"] = $entry.Value
    }
    foreach ($toolSource in @(Get-Prop $Package 'toolSources')) {
        $map[$toolSource] = Get-FileSha256 -PathValue (Join-UnderRoot -Root $RepositoryRoot -RelativePath $toolSource)
    }
    return $map
}

function New-ReceiptObject {
    param([string]$Version, [string]$EditorId, [string]$ScopeName, [string]$Kind, $Files)
    return [ordered]@{
        package     = 'clean-code-refactor'
        version     = $Version
        installedAt = (Get-Date).ToUniversalTime().ToString('o')
        editor      = $EditorId
        scope       = $ScopeName
        kind        = $Kind
        files       = $Files
    }
}

function Write-FileIfChanged {
    param([string]$Destination, [string]$Content)
    if ((Test-Path -LiteralPath $Destination) -and ((Get-Content -LiteralPath $Destination -Raw) -eq $Content)) { return $false }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    # -NoNewline writes the exact bytes (LF endings preserved); no CRLF translation.
    Set-Content -LiteralPath $Destination -Value $Content -NoNewline
    return $true
}

function Copy-FileVerified {
    param([string]$Source, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-FileSha256 -PathValue $Source) -ne (Get-FileSha256 -PathValue $Destination)) {
        throw "Post-copy verification failed for $Destination"
    }
}

function Sync-MirroredDirectory {
    <#
        Mirror a source directory into an owned destination directory:
        copy new/changed files, remove stale owned files (files inside the owned
        references directory that the package no longer ships). Unrelated files
        OUTSIDE owned paths are never touched. Per-file writes mean an
        interrupted run leaves previous content for not-yet-written files.
        Returns a hashtable with Copied / Removed / Failed.
    #>
    param([string]$Source, [string]$Destination, [switch]$DryRun)
    $result = @{ Copied = 0; Removed = 0; Failed = $false }
    $sourceMap = Get-DirectoryFileMap -Directory $Source
    $destinationMap = Get-DirectoryFileMap -Directory $Destination

    if ($DryRun) {
        foreach ($relative in $sourceMap.Keys) {
            if (-not $destinationMap.ContainsKey($relative) -or $destinationMap[$relative] -ne $sourceMap[$relative]) { $result.Copied++ }
        }
        foreach ($relative in $destinationMap.Keys) {
            if (-not $sourceMap.ContainsKey($relative)) { $result.Removed++ }
        }
        return $result
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    foreach ($relative in ($sourceMap.Keys | Sort-Object)) {
        try {
            $target = Join-Path $Destination ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            $sourceFile = Join-Path $Source ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not $destinationMap.ContainsKey($relative) -or $destinationMap[$relative] -ne $sourceMap[$relative]) {
                Copy-FileVerified -Source $sourceFile -Destination $target
                $result.Copied++
            }
        } catch {
            Write-Warning "Failed to sync reference file '$relative': $($_.Exception.Message)"
            $result.Failed = $true
        }
    }
    foreach ($relative in ($destinationMap.Keys | Sort-Object)) {
        if (-not $sourceMap.ContainsKey($relative)) {
            $target = Join-Path $Destination ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            try {
                Remove-Item -LiteralPath $target -Force
                $result.Removed++
            } catch {
                Write-Warning "Failed to remove stale file '$relative': $($_.Exception.Message)"
                $result.Failed = $true
            }
        }
    }
    if (-not $DryRun) {
        # Prune directories that became empty after stale-file removal (deepest first).
        $directories = @(Get-ChildItem -LiteralPath $Destination -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($directory in $directories) {
            if (@(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                try { Remove-Item -LiteralPath $directory.FullName -Force } catch { Write-Verbose "Could not prune $($directory.FullName): $_" }
            }
        }
    }
    return $result
}

function Get-RuleBody {
    <#
        Single-pass transformation of the canonical skill body (fixes the double-prefix bug):
        'references/' is rewritten exactly once, then each tool path. Generated local links
        are validated against the package sources before anything is written.
    #>
    param($Registry, [string]$SkillText, [string]$ReferenceDir, [string]$RepositoryRoot)
    $layout = Get-Prop $Registry 'ruleFileLayout'
    $referencesDirName = Get-Prop $layout 'referencesDirName'
    $toolsDirName = Get-Prop $layout 'toolsDirName'

    $body = $SkillText -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
    $body = $body.Replace('references/', "$referencesDirName/")
    foreach ($toolSource in @(Get-Prop (Get-Prop $Registry 'package') 'toolSources')) {
        $toolLink = "$toolsDirName/$(Split-Path -Leaf $toolSource)"
        $body = $body.Replace($toolSource, $toolLink)
        if ($body.Contains($toolLink) -and -not (Test-Path -LiteralPath (Join-UnderRoot -Root $RepositoryRoot -RelativePath $toolSource) -PathType Leaf)) {
            throw "Generated rule references missing package file: $toolLink"
        }
    }

    # Validate every generated local link resolves to a real package file.
    foreach ($match in [regex]::Matches($body, [regex]::Escape("$referencesDirName/") + '([A-Za-z0-9][A-Za-z0-9._/-]*)')) {
        $candidate = Join-Path $ReferenceDir ($match.Groups[1].Value.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Generated rule references missing package file: $referencesDirName/$($match.Groups[1].Value)"
        }
    }
    return $body
}

function Get-FormattedRuleContent {
    param([string]$Body, [string]$Format, [string]$Version, [string]$ReferencesDirName)
    $marker = "<!-- clean-code-refactor $Version; generated by the package installer; edits here are overwritten on upgrade -->"
    switch ($Format) {
        'cursor' {
            return "---`n" +
                "description: Apply clean-code refactoring, hardening, lint remediation, and duplicate detection.`n" +
                "globs:`n" +
                "alwaysApply: false`n" +
                "---`n`n" +
                "$marker`n`n" +
                $Body.TrimEnd("`n") +
                "`n`n@$ReferencesDirName/language-hardening.md`n" +
                "@$ReferencesDirName/static-quality-rules.md`n"
        }
        'continue' {
            return "---`n" +
                "name: Clean Code Refactor`n" +
                "description: Refactor, review, and harden changed code.`n" +
                "alwaysApply: false`n" +
                "---`n`n" +
                "$marker`n`n" +
                $Body
        }
        'plain' {
            return "$marker`n`n" + $Body
        }
        default { throw "Unsupported rule format: $Format" }
    }
}

function Get-Receipt {
    param([string]$ReceiptPath)
    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Test-UnitUserModified {
    # True when a receipt exists but an owned file's current hash no longer matches it.
    param($Receipt)
    if ($null -eq $Receipt) { return $false }
    $recorded = Get-Prop $Receipt 'files'
    if ($null -eq $recorded) { return $false }
    foreach ($entry in $recorded.PSObject.Properties) {
        $fullPath = Join-UnderRoot -Root $script:UnitBase -RelativePath $entry.Name
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $true }
        if ((Get-FileSha256 -PathValue $fullPath) -ne ([string]$entry.Value)) { return $true }
    }
    return $false
}

function Get-PolicyKey {
    # Where an organization policy lives inside an installed unit (check-policy.ps1 looks there).
    param([string]$Kind, [string]$ToolsDirName)
    if ($Kind -eq 'rule-file') { return "$ToolsDirName/policy.json" }
    return 'policy.json'
}

function Test-PolicyCurrent {
    # True when no policy was requested, or the installed policy already matches it.
    param([string]$UnitBase, [string]$PolicyKey, [string]$PolicyHash)
    if (-not $PolicyHash) { return $true }
    $installed = Join-UnderRoot -Root $UnitBase -RelativePath $PolicyKey
    return (Test-Path -LiteralPath $installed -PathType Leaf) -and ((Get-FileSha256 -PathValue $installed) -eq $PolicyHash)
}

function Test-UnitUpToDate {
    <#
        True when the receipt version matches and every installed file matches the package.
        Rule-file units hold a generated rule instead of SKILL.md, and references and tools in
        renamed folders, so their paths are mapped and the rule is compared with what this run
        would write.
    #>
    param($Receipt, [string]$Version, $SourceMap, [string]$Kind, [string]$RuleFilePath, [string]$ExpectedRuleContent, $Package, $Layout)
    if ($null -eq $Receipt) { return $false }
    if ((Get-Prop $Receipt 'version') -ne $Version) { return $false }
    if ($null -eq (Get-Prop $Receipt 'files')) { return $false }
    $skillFile = Get-Prop $Package 'canonicalSkillFile'
    $referenceDir = Get-Prop $Package 'referenceDir'
    foreach ($entry in $SourceMap.GetEnumerator()) {
        $relative = $entry.Key
        if ($Kind -eq 'rule-file') {
            if ($relative -eq $skillFile) {
                if (-not (Test-Path -LiteralPath $RuleFilePath -PathType Leaf)) { return $false }
                if ((Get-Content -LiteralPath $RuleFilePath -Raw) -ne $ExpectedRuleContent) { return $false }
                continue
            }
            if ($relative.StartsWith("$referenceDir/")) { $relative = "$(Get-Prop $Layout 'referencesDirName')/$($relative.Substring($referenceDir.Length + 1))" }
            elseif ($relative.StartsWith('scripts/')) { $relative = "$(Get-Prop $Layout 'toolsDirName')/$($relative.Substring(8))" }
        }
        $fullPath = Join-UnderRoot -Root $script:UnitBase -RelativePath $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $false }
        if ((Get-FileSha256 -PathValue $fullPath) -ne $entry.Value) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $registryPath = Join-Path $repositoryRoot 'integrations/registry.json'
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw "Editor registry is missing: $registryPath" }
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $package = Get-Prop $registry 'package'
    $layout = Get-Prop $registry 'ruleFileLayout'
    $version = Get-Prop $package 'version'

    $skillSource = Join-Path $repositoryRoot (Get-Prop $package 'canonicalSkillFile')
    $referenceSource = Join-Path $repositoryRoot (Get-Prop $package 'referenceDir')
    $toolSources = @(Get-Prop $package 'toolSources')
    $toolSourcePaths = @($toolSources | ForEach-Object { Join-UnderRoot -Root $repositoryRoot -RelativePath $_ })
    foreach ($path in @($skillSource, $referenceSource) + $toolSourcePaths) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Required source is missing: $path" }
    }

    # Organization policy: validated before anything is written.
    $policySource = $null
    $policyHash = $null
    if ($PolicyFile) {
        if (-not (Test-Path -LiteralPath $PolicyFile -PathType Leaf)) { throw "Policy file not found: $PolicyFile" }
        $policyItem = Get-Item -LiteralPath $PolicyFile -Force
        if (($policyItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Policy file must not be a symlink: $PolicyFile" }
        if ($policyItem.Length -gt 65536) { throw "Policy file is larger than 65536 bytes: $PolicyFile" }
        $policySource = $policyItem.FullName
        $policyCheck = & (Join-Path $repositoryRoot 'scripts/check-policy.ps1') -PolicyFile $policySource
        if ($LASTEXITCODE -ne 0) { throw "Policy file is invalid: $(($policyCheck | Out-String).Trim())" }
        $policyHash = Get-FileSha256 -PathValue $policySource
    }

    $editorIds = @((Get-Prop $registry 'editors').PSObject.Properties.Name | Sort-Object)

    if ($List) {
        if ($OutputFormat -eq 'Json') {
            $registry | ConvertTo-Json -Depth 8
        } else {
            Write-Output "Registered targets (package version $version):"
            foreach ($id in $editorIds) {
                $definition = Get-Prop (Get-Prop $registry 'editors') $id
                foreach ($scopeName in @('project', 'user')) {
                    $scopeDef = Get-Prop (Get-Prop $definition 'scopes') $scopeName
                    if ($null -eq $scopeDef) { continue }
                    $verification = Get-Prop $scopeDef 'verification'
                    $suffix = if ($verification) { " [$verification]" } else { '' }
                    Write-Output ("  {0,-10} {1,-7} {2,-12} {3}{4}" -f $id, $scopeName, (Get-Prop $definition 'kind'), (Get-Prop $scopeDef 'path'), $suffix)
                }
            }
        }
        exit 0
    }

    if ($Scope -eq 'project') {
        if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) { throw "Target project directory does not exist: $TargetPath" }
        $projectRoot = Resolve-FullDirectoryPath -PathValue (Resolve-Path -LiteralPath $TargetPath).Path
    } else {
        $projectRoot = $null
    }

    $roots = @{
        'project'    = $projectRoot
        'codex-home' = Resolve-FullDirectoryPath -PathValue $CodexHome
        'home'       = Resolve-FullDirectoryPath -PathValue $UserHome
        'xdg-config' = Resolve-FullDirectoryPath -PathValue $( if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $UserHome '.config' } )
    }

    # Resolve requested editor ids.
    $requested = @()
    foreach ($item in $Editor) {
        $requested += ($item -split '[,;\s]+' | Where-Object { $_ })
    }
    $requested = @($requested | Select-Object -Unique)
    if (($requested -contains 'all') -and ($requested.Count -gt 1)) { throw "Cannot combine 'all' with other editor selections." }
    if (($requested -contains 'detected') -and $requested.Count -gt 1) { throw "Cannot combine 'detected' with other editor selections." }

    if ($requested -contains 'all') {
        $selected = $editorIds
    } elseif ($requested -contains 'detected') {
        $selected = @()
        foreach ($id in $editorIds) {
            $definition = Get-Prop (Get-Prop $registry 'editors') $id
            $scopeDef = Get-Prop (Get-Prop $definition 'scopes') $Scope
            if ($null -eq $scopeDef) { continue }
            $rootPath = $roots[(Get-Prop $scopeDef 'root')]
            $destination = Join-UnderRoot -Root $rootPath -RelativePath (Get-Prop $scopeDef 'path')
            $matched = (Test-Path -LiteralPath $destination)
            if (-not $matched) {
                foreach ($hint in @(Get-Prop $scopeDef 'detect')) {
                    if ($null -eq $hint) { continue }
                    $hintRoot = $roots[(Get-Prop $hint 'root')]
                    if ($null -ne $hintRoot -and (Test-Path -LiteralPath (Join-UnderRoot -Root $hintRoot -RelativePath (Get-Prop $hint 'path')))) { $matched = $true; break }
                }
            }
            if ($matched) { $selected += $id }
        }
        if ($selected.Count -eq 0) {
            Write-Output "No installed editors detected for scope '$Scope'. Nothing to do."
            exit 0
        }
    } else {
        foreach ($id in $requested) {
            if ($editorIds -notcontains $id) { throw "Unknown editor target: '$id'. Known targets: $($editorIds -join ', ')" }
        }
        $selected = $requested
    }

    $skillText = Get-Content -LiteralPath $skillSource -Raw
    $sourceMap = Get-SourceFileMap -Package $package -SkillSource $skillSource -ReferenceDir $referenceSource -RepositoryRoot $repositoryRoot
    $referencesDirName = Get-Prop $layout 'referencesDirName'
    $toolsDirName = Get-Prop $layout 'toolsDirName'
    $receiptFileName = Get-Prop $package 'receiptFileName'

    function Get-ExpectedRuleContent {
        # The rule file this run would write for a rule-file scope; $null for skill folders.
        param([string]$Kind, $ScopeDef)
        if ($Kind -ne 'rule-file') { return $null }
        $ruleFormat = Get-Prop $ScopeDef 'format'
        if (-not $ruleFormat) { $ruleFormat = 'plain' }
        $ruleBody = Get-RuleBody -Registry $registry -SkillText $skillText -ReferenceDir $referenceSource -RepositoryRoot $repositoryRoot
        return Get-FormattedRuleContent -Body $ruleBody -Format $ruleFormat -Version $version -ReferencesDirName $referencesDirName
    }

    # ------------------------------- Plan ---------------------------------
    $plan = @()
    foreach ($id in $selected) {
        $definition = Get-Prop (Get-Prop $registry 'editors') $id
        $scopeDef = Get-Prop (Get-Prop $definition 'scopes') $Scope
        if ($null -eq $scopeDef) {
            $plan += [pscustomobject]@{ Editor = $id; Scope = $Scope; Kind = $null; Destination = $null; UnitBase = $null; ReceiptPath = $null; Status = 'skipped'; Reason = "scope '$Scope' is not declared for this editor (see docs/ide-compatibility.md)"; Verification = $null; ScopeDef = $null }
            continue
        }

        $rootPath = $roots[(Get-Prop $scopeDef 'root')]
        if ($null -eq $rootPath) {
            $plan += [pscustomobject]@{ Editor = $id; Scope = $Scope; Kind = $null; Destination = $null; UnitBase = $null; ReceiptPath = $null; Status = 'failed'; Reason = "root '$(Get-Prop $scopeDef 'root')' is unavailable"; Verification = $null; ScopeDef = $null }
            $script:HadFailure = $true
            continue
        }
        $kind = Get-Prop $scopeDef 'kind'
        if (-not $kind) { $kind = Get-Prop $definition 'kind' }
        $destination = Join-UnderRoot -Root $rootPath -RelativePath (Get-Prop $scopeDef 'path')

        # Containment and reparse-point preflight (no write may escape the declared root).
        if (-not (Test-PathUnderRoot -Candidate $destination -Root $rootPath)) {
            $plan += [pscustomobject]@{ Editor = $id; Scope = $Scope; Kind = $kind; Destination = $destination; UnitBase = $null; ReceiptPath = $null; Status = 'failed'; Reason = "destination escapes its root: $destination"; Verification = $null; ScopeDef = $scopeDef }
            $script:HadFailure = $true
            continue
        }
        $reparse = Get-ReparseViolation -Destination $destination -Root $rootPath
        if ($null -ne $reparse) {
            $plan += [pscustomobject]@{ Editor = $id; Scope = $Scope; Kind = $kind; Destination = $destination; UnitBase = $null; ReceiptPath = $null; Status = 'failed'; Reason = "refusing to traverse reparse point: $reparse"; Verification = $null; ScopeDef = $scopeDef }
            $script:HadFailure = $true
            continue
        }

        $verification = Get-Prop $scopeDef 'verification'
        $unitBase = if ($kind -eq 'rule-file') { Split-Path -Parent $destination } else { $destination }
        $script:UnitBase = $unitBase
        $receiptPath = if ($kind -eq 'rule-file') {
            Join-UnderRoot -Root $unitBase -RelativePath "$toolsDirName/$receiptFileName"
        } else {
            Join-UnderRoot -Root $unitBase -RelativePath $receiptFileName
        }

        $unitExists = if ($kind -eq 'rule-file') {
            (Test-Path -LiteralPath $destination -PathType Leaf)
        } else {
            (Test-Path -LiteralPath $destination -PathType Container)
        }
        $receipt = Get-Receipt -ReceiptPath $receiptPath

        $status = $null; $reason = $null
        if (-not $unitExists) {
            $status = 'install'
        } elseif ($null -eq $receipt) {
            if ($Force) { $status = 'update'; $reason = 'existing unmanaged install; replacing because -Force was given' }
            else { $status = 'skipped'; $reason = 'existing install has no package receipt (unmanaged); use -Force to replace' }
        } elseif (Test-UnitUserModified -Receipt $receipt) {
            if ($Force) { $status = 'update'; $reason = 'user modifications detected; replacing because -Force was given' }
            else { $status = 'skipped'; $reason = 'user modifications detected; use -Force to overwrite' }
        } elseif ((Test-UnitUpToDate -Receipt $receipt -Version $version -SourceMap $sourceMap -Kind $kind -RuleFilePath $destination -ExpectedRuleContent (Get-ExpectedRuleContent -Kind $kind -ScopeDef $scopeDef) -Package $package -Layout $layout) -and
            (Test-PolicyCurrent -UnitBase $unitBase -PolicyKey (Get-PolicyKey -Kind $kind -ToolsDirName $toolsDirName) -PolicyHash $policyHash)) {
            $status = 'up-to-date'
        } else {
            $status = 'update'
            $receiptVersion = Get-Prop $receipt 'version'
            if ($receiptVersion -and $receiptVersion -ne $version) { $reason = "upgrading receipt version $receiptVersion -> $version" }
        }

        $plan += [pscustomobject]@{
            Editor = $id; Scope = $Scope; Kind = $kind; Destination = $destination; UnitBase = $unitBase
            ReceiptPath = $receiptPath; Status = $status; Reason = $reason; Verification = $verification
            ScopeDef = $scopeDef
        }
    }

    $blocked = @($plan | Where-Object { $_.Status -eq 'failed' })
    if ($blocked.Count -gt 0 -and -not $DryRun) {
        # Preflight failures abort the whole run: no partial installation.
        foreach ($item in $blocked) { Write-Notice "Preflight failed for $($item.Editor): $($item.Reason)" }
        throw 'Preflight failed for one or more targets; nothing was written.'
    }

    # ----------------------------- Execute --------------------------------
    $results = @()
    foreach ($item in $plan) {
        if ($item.Status -in @('skipped', 'failed')) {
            $results += [pscustomobject]@{
                editor = $item.Editor; scope = $item.Scope; status = $item.Status
                destination = $item.Destination; reason = $item.Reason
                filesWritten = 0; filesRemoved = 0
            }
            continue
        }

        if ($item.Status -eq 'up-to-date') {
            # Owned files already match the package; still re-check additive pointer/config extras.
            $upToDateRoot = $roots[(Get-Prop $item.ScopeDef 'root')]
            Install-AdditiveExtra -Kind $item.Kind -Root $upToDateRoot -ScopeDef $item.ScopeDef
            $results += [pscustomobject]@{
                editor = $item.Editor; scope = $item.Scope; status = $item.Status
                destination = $item.Destination; reason = $item.Reason
                filesWritten = 0; filesRemoved = 0
            }
            continue
        }

        $scopeDef = $item.ScopeDef
        $kind = $item.Kind
        $destination = $item.Destination
        $unitBase = $item.UnitBase
        $filesWritten = 0
        $filesRemoved = 0
        $referenceResult = $null
        $rootPath = $roots[(Get-Prop $scopeDef 'root')]

        try {
            if ($kind -eq 'skill-folder') {
                # --- canonical folder: SKILL.md, references/ (mirrored), scripts/ tools ---
                $skillDestination = Join-UnderRoot -Root $unitBase -RelativePath (Get-Prop $package 'canonicalSkillFile')
                if (-not $DryRun) {
                    if (Write-FileIfChanged -Destination $skillDestination -Content $skillText) { $filesWritten++ }
                }
                $referenceDestination = Join-UnderRoot -Root $unitBase -RelativePath (Get-Prop $package 'referenceDir')
                $referenceResult = Sync-MirroredDirectory -Source $referenceSource -Destination $referenceDestination -DryRun:$DryRun
                if ($referenceResult.Failed) { throw "reference sync failed for $referenceDestination" }
                $filesWritten += $referenceResult.Copied
                $filesRemoved += $referenceResult.Removed

                foreach ($toolSource in $toolSources) {
                    $toolDestination = Join-UnderRoot -Root $unitBase -RelativePath $toolSource
                    if (-not $DryRun) { Copy-FileVerified -Source (Join-UnderRoot -Root $repositoryRoot -RelativePath $toolSource) -Destination $toolDestination }
                    $filesWritten++
                }
            } else {
                # --- rule file + mirrored references + tools ---
                $format = Get-Prop $scopeDef 'format'
                if (-not $format) { $format = 'plain' }
                $body = Get-RuleBody -Registry $registry -SkillText $skillText -ReferenceDir $referenceSource -RepositoryRoot $repositoryRoot
                $content = Get-FormattedRuleContent -Body $body -Format $format -Version $version -ReferencesDirName $referencesDirName

                if (-not $DryRun) {
                    if (Write-FileIfChanged -Destination $destination -Content $content) { $filesWritten++ }
                }

                $referenceDestination = Join-UnderRoot -Root $unitBase -RelativePath $referencesDirName
                $referenceResult = Sync-MirroredDirectory -Source $referenceSource -Destination $referenceDestination -DryRun:$DryRun
                if ($referenceResult.Failed) { throw "reference sync failed for $referenceDestination" }
                $filesWritten += $referenceResult.Copied
                $filesRemoved += $referenceResult.Removed

                foreach ($toolSource in $toolSources) {
                    $toolDestination = Join-UnderRoot -Root $unitBase -RelativePath "$toolsDirName/$(Split-Path -Leaf $toolSource)"
                    if (-not $DryRun) { Copy-FileVerified -Source (Join-UnderRoot -Root $repositoryRoot -RelativePath $toolSource) -Destination $toolDestination }
                    $filesWritten++
                }
            }

            $policyKey = Get-PolicyKey -Kind $kind -ToolsDirName $toolsDirName
            if ($policySource) {
                if (-not $DryRun) { Copy-FileVerified -Source $policySource -Destination (Join-UnderRoot -Root $unitBase -RelativePath $policyKey) }
                $filesWritten++
            }

            # Additive, marked extras (pointer sections, config entries).
            Install-AdditiveExtra -Kind $kind -Root $rootPath -ScopeDef $scopeDef

            # ----------------------------- Receipt ----------------------------
            if (-not $DryRun) {
                $previousReceipt = Get-Receipt -ReceiptPath $item.ReceiptPath
                $ownedFiles = [ordered]@{}
                if ($kind -eq 'skill-folder') {
                    $ownedFiles[(Get-Prop $package 'canonicalSkillFile')] = $sourceMap[(Get-Prop $package 'canonicalSkillFile')]
                    foreach ($toolSource in $toolSources) { $ownedFiles[$toolSource] = $sourceMap[$toolSource] }
                    foreach ($entry in (Get-DirectoryFileMap -Directory (Join-UnderRoot -Root $unitBase -RelativePath (Get-Prop $package 'referenceDir'))).GetEnumerator()) {
                        $ownedFiles["$((Get-Prop $package 'referenceDir'))/$($entry.Key)"] = $entry.Value
                    }
                } else {
                    $ownedFiles[(Split-Path -Leaf $destination)] = Get-FileSha256 -PathValue $destination
                    foreach ($toolSource in $toolSources) { $ownedFiles["$toolsDirName/$(Split-Path -Leaf $toolSource)"] = $sourceMap[$toolSource] }
                    foreach ($entry in (Get-DirectoryFileMap -Directory (Join-UnderRoot -Root $unitBase -RelativePath $referencesDirName)).GetEnumerator()) {
                        $ownedFiles["$referencesDirName/$($entry.Key)"] = $entry.Value
                    }
                }
                # An installed organization policy stays owned until it is replaced.
                $installedPolicy = Join-UnderRoot -Root $unitBase -RelativePath $policyKey
                $previouslyOwned = $null -ne (Get-Prop (Get-Prop $previousReceipt 'files') $policyKey)
                if (($policySource -or $previouslyOwned) -and (Test-Path -LiteralPath $installedPolicy -PathType Leaf)) {
                    $ownedFiles[$policyKey] = Get-FileSha256 -PathValue $installedPolicy
                }
                $receiptObject = New-ReceiptObject -Version $version -EditorId $item.Editor -ScopeName $Scope -Kind $kind -Files $ownedFiles
                $receiptTarget = $item.ReceiptPath
                $receiptParent = Split-Path -Parent $receiptTarget
                if (-not (Test-Path -LiteralPath $receiptParent)) { New-Item -ItemType Directory -Path $receiptParent -Force | Out-Null }
                $receiptText = (($receiptObject | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"
                Set-Content -LiteralPath $receiptTarget -Value $receiptText -NoNewline
            }

            $finalStatus = if ($item.Status -eq 'install') { 'installed' } else { 'updated' }
            $results += [pscustomobject]@{
                editor = $item.Editor; scope = $Scope; status = $finalStatus
                destination = $destination; reason = $item.Reason
                filesWritten = $filesWritten; filesRemoved = $filesRemoved
            }
            if ($item.Verification) {
                Write-Notice "Target '$($item.Editor)' user scope is marked '$($item.Verification)': confirm the destination against your installed editor's documentation."
            }
        } catch {
            $script:HadFailure = $true
            $results += [pscustomobject]@{
                editor = $item.Editor; scope = $Scope; status = 'failed'
                destination = $destination; reason = $_.Exception.Message
                filesWritten = $filesWritten; filesRemoved = $filesRemoved
            }
        }
    }

    $summary = [ordered]@{
        installed = @($results | Where-Object { $_.status -eq 'installed' }).Count
        updated   = @($results | Where-Object { $_.status -eq 'updated' }).Count
        upToDate  = @($results | Where-Object { $_.status -eq 'up-to-date' }).Count
        skipped   = @($results | Where-Object { $_.status -eq 'skipped' }).Count
        failed    = @($results | Where-Object { $_.status -eq 'failed' }).Count
    }

    if ($OutputFormat -eq 'Json') {
        [ordered]@{
            package = $version
            scope = $Scope
            dryRun = [bool]$DryRun
            results = $results
            summary = $summary
        } | ConvertTo-Json -Depth 6
    } else {
        foreach ($result in $results) {
            $line = "[$($result.status)] $($result.editor) ($($result.scope)) -> $($result.destination)"
            if ($result.reason) { $line += " - $($result.reason)" }
            if ($result.filesWritten -gt 0) { $line += " [files written: $($result.filesWritten)]" }
            if ($result.filesRemoved -gt 0) { $line += " [stale removed: $($result.filesRemoved)]" }
            Write-Output $line
        }
        Write-Output ("Summary: installed {0}, updated {1}, up-to-date {2}, skipped {3}, failed {4}." -f $summary['installed'], $summary['updated'], $summary['upToDate'], $summary['skipped'], $summary['failed'])
        if ($DryRun) { Write-Output 'Dry run: no files were written.' }
    }

    if ($script:HadFailure -or $summary['failed'] -gt 0) { exit 1 }
    exit 0
} catch {
    # Write directly to stderr: Write-Error would rethrow under $ErrorActionPreference = 'Stop'.
    $message = $_.Exception.Message
    if ($OutputFormat -eq 'Json') {
        [ordered]@{ error = $message; results = @(); summary = [ordered]@{ installed = 0; updated = 0; upToDate = 0; skipped = 0; failed = 1 } } | ConvertTo-Json -Depth 4
    } else {
        [Console]::Error.WriteLine("Error: $message")
    }
    exit 2
}
