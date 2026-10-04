# PSScriptAnalyzer settings used by CI and picked up automatically by editors.
# Every exclusion below is deliberate; prefer fixing code or a scoped
# SuppressMessageAttribute with a justification over adding a rule here.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # These are interactive console tools; their human-readable progress output is
        # meant for the host, and machine-readable output goes through -OutputFormat Json.
        'PSAvoidUsingWriteHost',
        # Internal helpers are not user-facing cmdlets. The installer previews changes
        # through its script-level -DryRun (alias -WhatIf) instead of per-function ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
