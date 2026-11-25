[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Profile, [switch]$CheckOnly)

. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
try {
    if ($CheckOnly) {
        $account = Resolve-AuthProfile $Profile
        [PSCustomObject]@{ Email=$account.email; Alias=$account.alias; Mode=$account.auth_method; Project=$account.project_id; Region=$account.region }
        return
    }
    $account = Switch-AuthProfile $Profile
} catch {
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Antigravity 切号', 'OK', 'Warning')
    exit 1
}
