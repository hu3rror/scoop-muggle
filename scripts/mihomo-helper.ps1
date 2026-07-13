param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('pre_install', 'post_install', 'uninstall')]
    [string]$Phase,

    [string]$Dir,
    [string]$PersistDir
)

switch ($Phase) {
    'pre_install' {
        # 1. 重命名程序与服务包装器
        # 用 -First 1 兜底，避免 mihomo*.exe 意外匹配多个文件时 Rename-Item 因目标名重复而报错中止
        $mihomoExe = Get-ChildItem "$Dir\mihomo*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mihomoExe) {
            Rename-Item $mihomoExe.FullName -NewName 'mihomo.exe'
        }
        if (Test-Path "$Dir\shawl.exe") {
            Rename-Item "$Dir\shawl.exe" -NewName 'mihomo-service.exe'
        }

        # 2. 预创建需要持久化的文件/文件夹以防止 Scoop 报错
        if (!(Test-Path "$PersistDir")) {
            New-Item -Path "$PersistDir" -ItemType Directory | Out-Null
        }
        if (!(Test-Path "$PersistDir\cache.db")) {
            New-Item -Path "$PersistDir\cache.db" -ItemType File | Out-Null
        }
        if (!(Test-Path "$PersistDir\config.yaml")) {
            New-Item -Path "$PersistDir\config.yaml" -ItemType File | Out-Null
        }
    }

    'post_install' {
        # 注意：此处 $Dir 是本次安装/更新对应的版本目录（apps\<app>\<version>），
        # 而不是 "current" 符号链接路径。由于每次安装/更新都会重新执行 post_install
        # 并重建服务注册，因此服务路径会在每次更新后自动刷新，不会因为旧版本目录被
        # `scoop cleanup` 清理而失效。
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $servicePath = "$Dir\mihomo-service.exe"
        $logDir = "$Dir\logs"

        $argsList = @(
            'add',
            '--name', 'mihomo-shawl',
            '--cwd', "$Dir",
            '--log-dir', "$logDir",
            '--log-rotate', 'bytes=10485760',
            '--log-retain', '8',
            '--stop-timeout', '5000',
            '--',
            "$Dir\mihomo.exe",
            '-d', '.',
            '-f', 'config.yaml'
        )

        if ($isAdmin) {
            sc.exe delete mihomo-shawl | Out-Null
            & "$servicePath" $argsList | Out-Null
            sc.exe config mihomo-shawl start= auto | Out-Null
            Remove-NetFirewallRule -DisplayName 'Mihomo-In-TCP', 'Mihomo-In-UDP', 'Mihomo-Out' -ErrorAction SilentlyContinue | Out-Null
            New-NetFirewallRule -DisplayName 'Mihomo-In-TCP' -Direction Inbound -Program "$Dir\mihomo.exe" -Action Allow -Profile Any -Protocol TCP -ErrorAction SilentlyContinue | Out-Null
            New-NetFirewallRule -DisplayName 'Mihomo-In-UDP' -Direction Inbound -Program "$Dir\mihomo.exe" -Action Allow -Profile Any -Protocol UDP -ErrorAction SilentlyContinue | Out-Null
            Write-Host 'Mihomo Windows service registered and firewall rules configured successfully.' -ForegroundColor Green
        } else {
            Write-Host 'Not running as Administrator. Requesting UAC elevation to configure Windows service and firewall rules...' -ForegroundColor Yellow

            # 修复点：原代码写作
            #   $cmdString = "..." + ($argsList | ForEach-Object {"'$_'"}) -join ' ' + "..."
            # PowerShell 中二元 -join 的优先级低于 +（详见 about_Operator_Precedence），
            # 上面这行会被解析成 (A + B) -join (' ' + C)，导致 "; sc.exe config ... start= auto"
            # 及后面所有防火墙规则命令被静默丢弃，且不会报任何错误。
            # 这里先把 -join 单独算出来，再用 + 拼接，避免优先级陷阱。
            $joinedArgs = ($argsList | ForEach-Object { "'$_'" }) -join ' '
            $cmdString = "sc.exe delete mihomo-shawl | Out-Null; & '$servicePath' " + $joinedArgs + `
                "; sc.exe config mihomo-shawl start= auto | Out-Null" + `
                "; Remove-NetFirewallRule -DisplayName 'Mihomo-In-TCP','Mihomo-In-UDP','Mihomo-Out' -ErrorAction SilentlyContinue" + `
                "; New-NetFirewallRule -DisplayName 'Mihomo-In-TCP' -Direction Inbound -Program '$Dir\mihomo.exe' -Action Allow -Profile Any -Protocol TCP -ErrorAction SilentlyContinue | Out-Null" + `
                "; New-NetFirewallRule -DisplayName 'Mihomo-In-UDP' -Direction Inbound -Program '$Dir\mihomo.exe' -Action Allow -Profile Any -Protocol UDP -ErrorAction SilentlyContinue | Out-Null"

            try {
                Start-Process powershell -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmdString -Verb RunAs -Wait -ErrorAction Stop
                Write-Host 'Mihomo Windows service registered and firewall rules configured successfully.' -ForegroundColor Green
            } catch {
                Write-Warning 'UAC elevation denied. Service was not registered and firewall rules were not added.'
            }
        }
        Write-Host ''
        Write-Host 'INFO: If your TUN/Mixed mode requires outbound rule, run PowerShell as Administrator and execute:' -ForegroundColor Cyan
        Write-Host "New-NetFirewallRule -DisplayName 'Mihomo-Out' -Direction Outbound -Program '$Dir\mihomo.exe' -Action Allow -Profile Any" -ForegroundColor Gray
        Write-Host ''
    }

    'uninstall' {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $services = @('mihomo', 'mihomo-shawl') | Get-Service -ErrorAction SilentlyContinue

        if ($isAdmin) {
            if ($services) {
                foreach ($service in $services) {
                    if ($service.Status -eq 'Running') {
                        Write-Host "Stopping '$($service.Name)' service..." -ForegroundColor Yellow
                        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Host "Uninstalling '$($service.Name)' service..." -ForegroundColor Yellow
                    sc.exe delete $service.Name | Out-Null
                }
            }
            Write-Host 'Stopping any remaining Mihomo processes...' -ForegroundColor Yellow
            Stop-Process -Name 'mihomo', 'mihomo-service' -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-NetFirewallRule -DisplayName 'Mihomo-In-TCP', 'Mihomo-In-UDP', 'Mihomo-Out' -ErrorAction SilentlyContinue | Out-Null
        } else {
            Write-Host 'Not running as Administrator. Requesting elevation via UAC to stop/uninstall service, terminate processes, and remove firewall rules...' -ForegroundColor Yellow
            $elevatedCmds = @()
            if ($services) {
                foreach ($service in $services) {
                    if ($service.Status -eq 'Running') {
                        $elevatedCmds += "Stop-Service -Name '$($service.Name)' -Force -ErrorAction SilentlyContinue"
                    }
                    $elevatedCmds += "sc.exe delete '$($service.Name)'"
                }
            }
            $elevatedCmds += "Stop-Process -Name 'mihomo','mihomo-service' -Force -ErrorAction SilentlyContinue"
            $elevatedCmds += "Remove-NetFirewallRule -DisplayName 'Mihomo-In-TCP','Mihomo-In-UDP','Mihomo-Out' -ErrorAction SilentlyContinue"
            $cmdString = $elevatedCmds -join '; '
            try {
                Start-Process powershell -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmdString -Verb RunAs -Wait -ErrorAction Stop
            } catch {
                Write-Warning 'UAC elevation denied. Failed to stop/uninstall service, terminate processes, and remove firewall rules.'
            }
        }
    }
}
