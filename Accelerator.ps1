$PSModuleAutoloadingPreference = 'None'

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$here = Split-Path $script:MyInvocation.MyCommand.Path -Parent

$positionalArgs = @('CommandName')

Write-Verbose "Parsing unbound arguments..."
$parsedArgs = $Args | & "$($here)\Scripts\ConvertTo-ParameterHash.ps1" -PositionalParameters $positionalArgs -ErrorAction Stop

Write-Verbose "Args:`r`n$(($parsedArgs.Keys | foreach { (' ' * 11) + $_ + '=' + $parsedArgs[$_] }) -join "`r`n")"

$parameters = @{}

$parameters['CommandParameters'] = $parsedArgs

if ($parsedArgs.ContainsKey('CommandName')) {
    $parameters['CommandName'] = $parsedArgs['CommandName']
    $parsedArgs.Remove('CommandName') | Out-Null
}

& "$($here)\Scripts\Move-HashtableKey.ps1" -Source $parsedArgs -SourceKeys 'y','yes','Confirm' -Target $parameters -TargetKey 'Confirm'
& "$($here)\Scripts\Move-HashtableKey.ps1" -Source $parsedArgs -SourceKeys 'Verbose','v' -Target $parameters -TargetKey 'Verbose'
& "$($here)\Scripts\Move-HashtableKey.ps1" -Source $parsedArgs -SourceKeys 'WorkingDirectory' -Target $parameters -TargetKey 'WorkingDirectory' -DefaultValue "$((Get-Location).Path)"
& "$($here)\Scripts\Move-HashtableKey.ps1" -Source $parsedArgs -SourceKeys 'log','LogFile','LogFilePath' -Target $parameters -TargetKey 'LogFilePath'
& "$($here)\Scripts\Move-HashtableKey.ps1" -Source $parsedArgs -SourceKeys 'Interactive' -Target $parameters -TargetKey 'Interactive'

$useStart = $parsedArgs | & "$($here)\Scripts\Extract-HashtableKey.ps1" -Keys 'UseStart' -DefaultValue $false
$runAsAdmin = $parsedArgs | & "$($here)\Scripts\Extract-HashtableKey.ps1" -Keys 'RunAsAdmin' -DefaultValue $false
$windowTitle = $parsedArgs | & "$($here)\Scripts\Extract-HashtableKey.ps1" -Keys 'WindowTitle' -DefaultValue "$(if ($parameters['Interactive']) { 'Accelerator' })"
$powershellVersion = $parsedArgs | & "$($here)\Scripts\Extract-HashtableKey.ps1" -Keys 'PowerShellVersion'

if ($windowTitle) {
    $host.ui.RawUI.WindowTitle = $windowTitle
}

if ($useStart) {
    $tmpPath = "$([System.IO.Path]::GetTempFileName()).xml"

    Write-Host "Writing parameters to file '$($tmpPath)'..."
    $parameters | Export-Clixml -Path $tmpPath

    $commandString = "
        try {
            `$ErrorActionPreference = 'Stop' ;
            `$InformationPreference = 'Continue' ;
            `$env:AcceleratorPath = '$($env:AcceleratorPath)' ;
            if ('$($windowTitle)') {
                `$host.ui.RawUI.WindowTitle = '$($windowTitle)' ;
            }
            `$global:PSModulesRoot = '$($PSModulesRoot)' ;
            Set-Location '$($PWD.Path)' ;
            `$parameters = Import-Clixml -Path '$($tmpPath)' ;
            & '$($here)\Scripts\Start-Accelerator.ps1' @parameters ;
        } catch {
            `$e = `$_.Exception

            do {
                Write-Host `$e.Message -ForegroundColor Red
                Write-Host `$e.StackTrace -ForegroundColor Red

                `$e = `$e.InnerException
            } while (`$e)

            Read-Host 'Press any key to continue...'
        }
    "

    $arguments = ""

    if ($powershellVersion) {
        $arguments += " -Version $($powershellVersion)"
    }

    $arguments += " -NoProfile"
    $arguments += " -ExecutionPolicy Bypass"
    $arguments += " -Command ""$($commandString)"""

    Write-Host "Starting Accelerator in a new process..."

    if ($runAsAdmin) {
        Start-Process -FilePath 'powershell' -ArgumentList $arguments -Verb RunAs
    } else {
        Start-Process -FilePath 'powershell' -ArgumentList $arguments
    }
} else {
    if ($powershellVersion) {
        Write-Error "Can't force a particular PowerShell version unless the '-UseStart' flag is used."
        return
    }

    if ($runAsAdmin) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
        if ($principal.IsInRole($adminRole)) {
            Write-Verbose "Script is already running with elevated privileges."
        } else {
            Write-Error "Can't force run as admin unless the '-UseStart' flag is used."
            return
        }
    }

    try {
        $global:AcceleratorCommandSuccess = $null

        & "$($here)\Scripts\Start-Accelerator.ps1" @parameters
    } catch {
        if ($global:AcceleratorCommandSuccess -eq $null) {
            if ($parameters['Interactive']) {
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                if ($_.Exception.StackTrace) {
                    Write-Host "$($_.Exception.StackTrace)" -ForegroundColor Red
                }
            } elseif ($parameters['LogFilePath']) {
                "Error: $($_.Exception.Message)" | Out-File $parameters['LogFilePath'] -Append
                if ($_.Exception.StackTrace) {
                    "$($_.Exception.StackTrace)" | Out-File $parameters['LogFilePath'] -Append
                }
            }
        }

        throw
    } finally {
        if ($parameters['Interactive'] -and -not($global:AcceleratorCommandSuccess)) {
            Read-Host 'Press any key to continue...'
        }

        $global:AcceleratorCommandSuccess = $null
    }
}
