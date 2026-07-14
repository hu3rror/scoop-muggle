[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'enable', 'disable', 'log', 'edit', 'help')]
    [string]$Action = 'status',

    [Parameter()]
    [switch]$Tail
)

$ServiceName = 'mihomo-shawl'

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Help {
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor DarkGray
    Write-Host "  mihomo-helper [<Action>] [-Tail]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available Actions:" -ForegroundColor DarkGray
    Write-Host "  status   " -NoNewline; Write-Host "- Show service registration and status (Default)" -ForegroundColor Gray
    Write-Host "  start    " -NoNewline; Write-Host "- Start the service (Requires Admin)" -ForegroundColor Gray
    Write-Host "  stop     " -NoNewline; Write-Host "- Stop the service (Requires Admin)" -ForegroundColor Gray
    Write-Host "  restart  " -NoNewline; Write-Host "- Restart the service (Requires Admin)" -ForegroundColor Gray
    Write-Host "  enable   " -NoNewline; Write-Host "- Set service to start automatically on boot (Requires Admin)" -ForegroundColor Gray
    Write-Host "  disable  " -NoNewline; Write-Host "- Set service to manual start (Requires Admin)" -ForegroundColor Gray
    Write-Host "  log      " -NoNewline; Write-Host "- View log files" -ForegroundColor Gray
    Write-Host "  edit     " -NoNewline; Write-Host "- Open config.yaml with the best available editor" -ForegroundColor Gray
    Write-Host "  help     " -NoNewline; Write-Host "- Show this help message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Options:" -ForegroundColor DarkGray
    Write-Host "  -Tail    " -NoNewline; Write-Host "- Tail the log dynamically (only works with 'log' action)" -ForegroundColor Gray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Helpers for the 'edit' action: locate a usable editor for config.yaml
# ---------------------------------------------------------------------------

# Reads the user's explicitly-configured default app for a given file
# extension (e.g. '.yaml') from the registry, and returns the raw
# "shell\open\command" string (e.g. '"C:\Path\App.exe" "%1"').
# Returns $null if no explicit association is found or it can't be resolved.
function Get-FileAssociationCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    try {
        $userChoiceKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
        if (!(Test-Path -Path $userChoiceKeyPath)) {
            return $null
        }

        $progId = (Get-ItemProperty -Path $userChoiceKeyPath -ErrorAction Stop).ProgId
        if ([string]::IsNullOrWhiteSpace($progId)) {
            return $null
        }

        $commandKeyPath = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
        if (!(Test-Path -Path $commandKeyPath)) {
            return $null
        }

        $commandKey = Get-Item -Path $commandKeyPath -ErrorAction Stop
        $command = $commandKey.GetValue('')
        if ([string]::IsNullOrWhiteSpace($command)) {
            return $null
        }

        return $command
    } catch {
        return $null
    }
}

# Parses a "shell\open\command" style string, verifies the target
# executable actually exists, and launches it with the given file.
# Returns $true on successful launch, $false otherwise.
function Invoke-AssociatedEditor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandTemplate,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $CommandTemplate = [Environment]::ExpandEnvironmentVariables($CommandTemplate)

    $exe = $null
    $argTemplate = ''

    if ($CommandTemplate -match '^\s*"([^"]+)"(.*)$') {
        $exe = $Matches[1]
        $argTemplate = $Matches[2]
    } elseif ($CommandTemplate -match '^\s*(\S+)(.*)$') {
        $exe = $Matches[1]
        $argTemplate = $Matches[2]
    } else {
        return $false
    }

    if (!(Test-Path -Path $exe -PathType Leaf)) {
        return $false
    }

    if ($argTemplate -match '%1') {
        $argString = $argTemplate -replace '%1', "`"$FilePath`""
    } elseif ([string]::IsNullOrWhiteSpace($argTemplate)) {
        $argString = "`"$FilePath`""
    } else {
        $argString = "$argTemplate `"$FilePath`""
    }

    try {
        Start-Process -FilePath $exe -ArgumentList $argString -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Attempts to open $FilePath with, in order:
#   1) the user's explicit default app for .yaml / .yml
#   2) VS Code (PATH, then common install locations)
#   3) notepad.exe
function Open-ConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (!(Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "Config file not found: $FilePath" -ForegroundColor Red
        return $false
    }

    # 1) User's explicit default association for .yaml / .yml
    foreach ($ext in @('.yaml', '.yml')) {
        $cmdTemplate = Get-FileAssociationCommand -Extension $ext
        if ($cmdTemplate) {
            if (Invoke-AssociatedEditor -CommandTemplate $cmdTemplate -FilePath $FilePath) {
                Write-Host "Opened with system default ($ext) association." -ForegroundColor Green
                return $true
            }
        }
    }

    # 2) VS Code via PATH
    $codeCmd = Get-Command 'code' -ErrorAction SilentlyContinue
    if ($codeCmd) {
        try {
            Start-Process -FilePath $codeCmd.Source -ArgumentList "`"$FilePath`"" -ErrorAction Stop | Out-Null
            Write-Host "Opened with VS Code." -ForegroundColor Green
            return $true
        } catch {
            # fall through to next strategy
        }
    }

    # 2b) VS Code via common install locations (in case it's not on PATH)
    $vscodeCandidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
    )
    foreach ($candidate in $vscodeCandidates) {
        if ($candidate -and (Test-Path -Path $candidate -PathType Leaf)) {
            try {
                Start-Process -FilePath $candidate -ArgumentList "`"$FilePath`"" -ErrorAction Stop | Out-Null
                Write-Host "Opened with VS Code." -ForegroundColor Green
                return $true
            } catch {
                continue
            }
        }
    }

    # 3) notepad.exe fallback
    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$FilePath`"" -ErrorAction Stop | Out-Null
        Write-Host "Opened with Notepad (fallback)." -ForegroundColor Yellow
        return $true
    } catch {
        Write-Host "Failed to open config file with any known editor." -ForegroundColor Red
        return $false
    }
}

# 需要管理员权限的动作队列
$ElevatedActions = @('start', 'stop', 'restart', 'enable', 'disable')

# 自提权机制（Self-Elevation）
if ($Action -in $ElevatedActions -and -not (Test-Admin)) {
    Write-Host "Action '$Action' requires Administrator privileges. Requesting UAC elevation..." -ForegroundColor Yellow
    try {
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", $Action)
        if ($Tail) { $arguments += "-Tail" }
        $psExe = (Get-Process -Id $PID).Path
        Start-Process $psExe -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop
    } catch {
        Write-Error "UAC elevation denied or failed."
    }
    return
}

switch ($Action) {
    'status' {
        if ($PSBoundParameters.Count -eq 0) {
            Show-Help
            Write-Host "-----------------------" -ForegroundColor DarkGray
            Write-Host "Current Service Status:" -ForegroundColor DarkGray
            Write-Host "-----------------------" -ForegroundColor DarkGray
        }

        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (!$service) {
            Write-Host "Service '$ServiceName' is not registered." -ForegroundColor Red
            return
        }
        $statusColor = if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "Service Name: " -NoNewline; Write-Host $service.Name -ForegroundColor Cyan
        Write-Host "Status:       " -NoNewline; Write-Host $service.Status -ForegroundColor $statusColor
        Write-Host "Start Type:   " -NoNewline; Write-Host $service.StartType -ForegroundColor Cyan
    }
    'start' {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }
    'stop' {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
    }
    'restart' {
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
    }
    'enable' {
        sc.exe config $ServiceName start= auto | Out-Null
        Write-Host "Service configured to start automatically on boot." -ForegroundColor Green
    }
    'disable' {
        sc.exe config $ServiceName start= demand | Out-Null
        Write-Host "Service configured to manual start." -ForegroundColor Yellow
    }
    'log' {
        $logDir = Join-Path $PSScriptRoot "logs"
        $logPath = $null

        if (Test-Path $logDir) {
            $latestLog = Get-ChildItem -Path $logDir -Filter "*mihomo-shawl*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
            if ($latestLog) {
                $logPath = $latestLog.FullName
            }
        }

        if (!$logPath -or !(Test-Path $logPath)) {
            Write-Host "No log file found under logs directory. Ensure the service has been started at least once." -ForegroundColor Red
            return
        }

        if ($Tail) {
            Get-Content -Path $logPath -Tail 50 -Wait
        } else {
            Get-Content -Path $logPath -Tail 100
        }
    }
    'edit' {
        $configPath = Join-Path $PSScriptRoot 'config.yaml'
        Write-Host "Target config file: $configPath" -ForegroundColor DarkGray
        Open-ConfigFile -FilePath $configPath | Out-Null
    }
    'help' {
        Show-Help
    }
}
