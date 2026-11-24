#Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==============================================================================
# PastelPink Nautilus Bombs
# ==============================================================================
$script:ESC         = [char]27
$script:Pink        = "$script:ESC[38;2;255;183;197m" # #FFB7C5
$script:Lav         = "$script:ESC[38;2;203;166;247m" # #CBA6F7
$script:Mint        = "$script:ESC[38;2;166;227;161m" # #A6E3A1
$script:Peach       = "$script:ESC[38;2;250;179;135m" # #FAB387
$script:Rose        = "$script:ESC[38;2;243;139;168m" # #F38BA8
$script:Muted       = "$script:ESC[38;2;147;153;178m" # #9399B2
$script:White       = "$script:ESC[38;2;235;238;245m" # #EBEEF5
$script:Reset       = "$script:ESC[0m"
$script:TotalPhases = 15

# Runtime Unicode glyphs (strictly 7-bit ASCII source for PS 5.1 BOM safety)
$script:cDot        = [char]0x00B7
$script:cArrow      = [char]0x203A
$script:cOk         = [char]0x2713
$script:cErr        = [char]0x2717
$script:cTL         = [char]0x256D
$script:cTR         = [char]0x256E
$script:cBL         = [char]0x2570
$script:cBR         = [char]0x256F
$script:cH          = [char]0x2500
$script:cV          = [char]0x2502
$script:cLM         = [char]0x251C
$script:cRM         = [char]0x2524

function Write-Banner {
    $line = ([string]$script:cH) * 47
    Write-Host ""
    Write-Host "$script:Pink  $script:cTL$line$script:cTR$script:Reset"
    Write-Host "$script:Pink  $script:cV  PastelPink Nautilus  $script:cDot  Win10/11 & LTSC ISO  $script:cV$script:Reset"
    Write-Host "$script:Pink  $script:cBL$line$script:cBR$script:Reset"
    Write-Host ""
}

function Write-Phase([int]$Step, [string]$Title) {
    $tag = "{0:D2}/{1:D2}" -f $Step, $script:TotalPhases
    Write-Host ""
    Write-Host "$script:Pink[$tag]$script:Reset $script:Lav$Title$script:Reset"
}

function Write-StepInfo([string]$Msg) { Write-Host "  $script:Muted$script:cDot$script:Reset $script:Muted$Msg$script:Reset" }
function Write-StepSub([string]$Msg)  { Write-Host "  $script:Lav$script:cDot$script:Reset $script:White$Msg$script:Reset" }
function Write-StepOk([string]$Msg)   { Write-Host "  $script:Mint$script:cOk$script:Reset $Msg" }
function Write-StepWarn([string]$Msg) { Write-Host "  $script:Peach!$script:Reset $script:Peach$Msg$script:Reset" }
function Write-StepErr([string]$Msg)  { Write-Host "  $script:Rose$script:cErr$script:Reset $script:Rose$Msg$script:Reset" }

function Read-Input([string]$Label, [string]$Default = "") {
    $suffix = if ($Default) { " $script:Muted(Default: $Default)$script:Reset" } else { "" }
    Write-Host "$script:Pink$script:cArrow$script:Reset $Label${suffix}: " -NoNewline
    $val = Read-Host
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim().Trim('"')
}

# ==============================================================================
# Registry & Privilege Helpers
# ==============================================================================
function Ensure-HiveUnloaded([string]$HiveName) {
    $maxRetry = 5
    for ($i = 0; $i -lt $maxRetry; $i++) {
        reg query "HKLM\$HiveName" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        reg unload "HKLM\$HiveName" 2>$null | Out-Null
    }
    reg query "HKLM\$HiveName" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-StepWarn "Failed to unload HKLM\$HiveName after $maxRetry retries."
    }
}

function Set-RegistryValue([string]$Path, [string]$Name, [string]$Type, [string]$Data) {
    reg add "$Path" /v "$Name" /t "$Type" /d "$Data" /f 2>$null | Out-Null
}

function Remove-RegistryValue([string]$Path, [string]$Name = "") {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        reg delete "$Path" /f 2>$null | Out-Null
    } else {
        reg delete "$Path" /v "$Name" /f 2>$null | Out-Null
    }
}

function Remove-PathForce([string]$TargetPath) {
    if (-not (Test-Path -LiteralPath $TargetPath)) { return $false }
    if ((Get-Item -LiteralPath $TargetPath -Force) -is [System.IO.DirectoryInfo]) {
        takeown.exe /F "$TargetPath" /R /A /D Y 2>$null | Out-Null
        icacls.exe "$TargetPath" /grant "*S-1-5-32-544:(F)" /T /C /Q 2>$null | Out-Null
    } else {
        attrib.exe -H -S -R "$TargetPath" 2>$null | Out-Null
        takeown.exe /F "$TargetPath" /A 2>$null | Out-Null
        icacls.exe "$TargetPath" /grant "*S-1-5-32-544:(F)" /C /Q 2>$null | Out-Null
    }
    Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    return (-not (Test-Path -LiteralPath $TargetPath))
}

function Enable-ProcessPrivileges {
    $Definition = @"
    using System;
    using System.Runtime.InteropServices;
    public class TokenManipulator {
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern IntPtr GetCurrentProcess();
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
        [DllImport("advapi32.dll", SetLastError = true)]
        internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
        public static void AddPrivilege(string privilege) {
            IntPtr hproc = GetCurrentProcess();
            IntPtr htok = IntPtr.Zero;
            OpenProcessToken(hproc, 0x0028, ref htok);
            TokPriv1Luid tp = new TokPriv1Luid { Count = 1, Luid = 0, Attr = 0x00000002 };
            LookupPrivilegeValue(null, privilege, ref tp.Luid);
            AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }
"@
    if (-not ([System.Management.Automation.PSTypeName]'TokenManipulator').Type) {
        Add-Type -TypeDefinition $Definition
    }
    [TokenManipulator]::AddPrivilege("SeTakeOwnershipPrivilege")
    [TokenManipulator]::AddPrivilege("SeRestorePrivilege")
    [TokenManipulator]::AddPrivilege("SeBackupPrivilege")
}

function Unlock-OfflineCbsPackages {
    param (
        [string]$MountPath,
        [string[]]$TargetPatterns
    )
    Enable-ProcessPrivileges
    $AdminSID  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $AdminRule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $AdminSID, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )

    Ensure-HiveUnloaded "zSOFTWARE"
    reg load HKLM\zSOFTWARE "$MountPath\Windows\System32\config\SOFTWARE" 2>$null | Out-Null
    try {
        $CbsBaseKey  = "zSOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages"
        $AllPkgNames = @()

        $BaseHive = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($CbsBaseKey, $false)
        if (-not $BaseHive) { return }
        try {
            $AllPkgNames = $BaseHive.GetSubKeyNames()
        } finally {
            $BaseHive.Close()
            $BaseHive.Dispose()
        }

        $ProtectedPrefixes = @(
            "Package_for_RollupFix*",
            "Package_for_ServicingStack*",
            "Package_for_DotNetRollup*",
            "Package_for_KB*",
            "Package_*_for_KB*",
            "*Enablement*",
            "*Product-Data*EKB*",
            "*UpdateTargeting*EKB*"
        )

        $MatchedSet = New-Object System.Collections.Generic.HashSet[string]
        foreach ($PkgName in $AllPkgNames) {
            $IsProtected = $false
            foreach ($Prot in $ProtectedPrefixes) {
                if ($PkgName -like $Prot) { $IsProtected = $true; break }
            }
            if ($IsProtected) { continue }

            foreach ($Pattern in $TargetPatterns) {
                if ($PkgName -like $Pattern) {
                    [void]$MatchedSet.Add($PkgName)
                    break
                }
            }
        }

        foreach ($PkgName in $MatchedSet) {
            $PkgRelativePath = "$CbsBaseKey\$PkgName"

            # Unlock Staged (80 / 0x50) or Installed (112 / 0x70) packages to protect WinSxS integrity
            $StateOk  = $false
            $ProbeKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($PkgRelativePath, $false)
            if ($ProbeKey) {
                try {
                    $CurState = $ProbeKey.GetValue("CurrentState")
                    if ($null -ne $CurState -and ([int]$CurState -in @(80, 112))) {
                        $StateOk = $true
                    }
                } finally {
                    $ProbeKey.Close()
                    $ProbeKey.Dispose()
                }
            }
            if (-not $StateOk) { continue }

            $RegKey = $null
            try {
                $RegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    $PkgRelativePath,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::TakeOwnership
                )
                if ($RegKey) {
                    $Acl = $RegKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
                    $Acl.SetOwner($AdminSID)
                    $RegKey.SetAccessControl($Acl)
                }
            } finally {
                if ($RegKey) { $RegKey.Close(); $RegKey.Dispose(); $RegKey = $null }
            }

            try {
                $RegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    $PkgRelativePath,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions
                )
                if ($RegKey) {
                    $Acl = $RegKey.GetAccessControl()
                    $Acl.AddAccessRule($AdminRule)
                    $RegKey.SetAccessControl($Acl)
                }
            } finally {
                if ($RegKey) { $RegKey.Close(); $RegKey.Dispose(); $RegKey = $null }
            }

            try {
                $RegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($PkgRelativePath, $true)
                if ($RegKey) {
                    $RegKey.SetValue("Visibility", 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                    $RegKey.DeleteValue("DefVis", $false)

                    if ($RegKey.GetSubKeyNames() -contains "Owners") {
                        $OwnersKey = $null
                        try {
                            $OwnersKey = $RegKey.OpenSubKey(
                                "Owners",
                                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                                [System.Security.AccessControl.RegistryRights]::TakeOwnership
                            )
                            if ($OwnersKey) {
                                $OAcl = $OwnersKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
                                $OAcl.SetOwner($AdminSID)
                                $OwnersKey.SetAccessControl($OAcl)
                            }
                        } finally {
                            if ($OwnersKey) { $OwnersKey.Close(); $OwnersKey.Dispose(); $OwnersKey = $null }
                        }

                        try {
                            $OwnersKey = $RegKey.OpenSubKey(
                                "Owners",
                                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                                [System.Security.AccessControl.RegistryRights]::ChangePermissions
                            )
                            if ($OwnersKey) {
                                $OAcl = $OwnersKey.GetAccessControl()
                                $OAcl.AddAccessRule($AdminRule)
                                $OwnersKey.SetAccessControl($OAcl)
                            }
                        } finally {
                            if ($OwnersKey) { $OwnersKey.Close(); $OwnersKey.Dispose(); $OwnersKey = $null }
                        }

                        $RegKey.DeleteSubKeyTree("Owners", $false)
                    }
                }
            } finally {
                if ($RegKey) { $RegKey.Close(); $RegKey.Dispose(); $RegKey = $null }
            }
        }
    } finally {
        Ensure-HiveUnloaded "zSOFTWARE"
    }
}

function Get-OscdimgPath {
    $candidates = @(
        "$env:SystemRoot\System32\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command oscdimg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

# ==============================================================================
# Auto-LCU (Windows 11/10)
# ==============================================================================
function Invoke-AutoWindowsUpdate {
    param (
        [string]$MountPath,
        [int]$Build,
        [int]$UBR,
        [string]$DisplayVersion,
        [bool]$IsLTSC = $false,
        [bool]$IncludePreview = $false,
        [bool]$AllowWin10ESU = $false,
        [string]$CacheDir
    )

    $IsWin11     = ($Build -ge 22000)
    $OsName      = if ($IsWin11) { "Windows 11" } else { "Windows 10" }
    $EditionTag  = if ($IsLTSC) { "$OsName LTSC" } else { $OsName }
    $PreviewText = if ($IncludePreview) { "Stable + Preview" } else { "Stable LCU only" }

    Write-StepSub "Checking latest update for $EditionTag ($DisplayVersion) Build $Build.$UBR [$PreviewText]..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    # Windows 11 25H2 (26200) shares LCU servicing base with 24H2 (26100)
    $BuildRegex = if ($Build -eq 26200) { "26200|26100" } else { "$Build" }
    $ExcludePat = if ($IncludePreview) {
        'Server|ARM64|x86|Dynamic Update|\.NET|Hotpatch|Safe OS'
    } else {
        'Preview|Server|ARM64|x86|Dynamic Update|\.NET|Hotpatch|Safe OS'
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $seenGuids  = New-Object System.Collections.Generic.HashSet[string]

    $QueryCatalogBlock = {
        param([string]$SearchTerm)
        $SearchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=" + [Uri]::EscapeDataString($SearchTerm)
        Write-StepInfo "Querying Catalog: $SearchTerm"
        try {
            $req = Invoke-WebRequest -Uri $SearchUrl -UseBasicParsing -TimeoutSec 25
        } catch {
            Write-StepWarn "Microsoft Update Catalog unreachable: $($_.Exception.Message)"
            return
        }

        $rows = [regex]::Matches($req.Content, "(?is)<a[^>]+id=['""]([0-9a-f\-]{36})_link['""][^>]*>(.*?)</a>")
        foreach ($m in $rows) {
            $guid = $m.Groups[1].Value.ToLowerInvariant()
            if ($seenGuids.Contains($guid)) { continue }

            $title = ($m.Groups[2].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
            $um    = [regex]::Match($title, "\((?:$BuildRegex)\.(\d+)\)")
            $km    = [regex]::Match($title, "(KB\d+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $dm    = [regex]::Match($title, "\b(\d{4})-(\d{2})\b")

            # Filter ESU updates on non-LTSC Windows 10
            $isEsu = ($title -match '\bESU\b|Extended Security')
            if ($isEsu -and (-not $IsWin11) -and (-not $IsLTSC) -and (-not $AllowWin10ESU)) { continue }

            $matchesTarget = $um.Success -or (
                -not [string]::IsNullOrWhiteSpace($DisplayVersion) -and
                $title -match "$([regex]::Escape($OsName)).*version\s+$([regex]::Escape($DisplayVersion))\b"
            )

            $isLcuTitle = ($title -match '(Cumulative|Security|Preview|Out-of-band) Update')
            if ($matchesTarget -and $isLcuTitle -and ($title -notmatch $ExcludePat)) {
                [void]$seenGuids.Add($guid)
                $dateScore = if ($dm.Success) { [int]"$($dm.Groups[1].Value)$($dm.Groups[2].Value)" } else { 0 }
                $candidates.Add([PSCustomObject]@{
                    Guid      = $guid
                    Title     = $title
                    UBR       = if ($um.Success) { [int]$um.Groups[1].Value } else { -1 }
                    DateScore = $dateScore
                    KB        = if ($km.Success) { $km.Groups[1].Value.ToLowerInvariant() } else { "" }
                })
            }
        }
    }

    # Phase A: Narrow month-scoped queries for recent 3 months
    $Now = Get-Date
    for ($offset = 0; $offset -lt 3; $offset++) {
        $dt    = $Now.AddMonths(-$offset)
        $ym    = $dt.ToString("yyyy-MM")
        $ymInt = [int]$dt.ToString("yyyyMM")

        $monthQueries = New-Object System.Collections.Generic.List[string]
        if ($IsWin11) {
            $monthQueries.Add("$ym Security Update $Build")
            if ($IncludePreview) { $monthQueries.Add("$ym Preview Update $Build") }
            if ($Build -eq 26200) {
                $monthQueries.Add("$ym Security Update 26100")
                if ($IncludePreview) { $monthQueries.Add("$ym Preview Update 26100") }
            }
            if (-not [string]::IsNullOrWhiteSpace($DisplayVersion)) {
                $monthQueries.Add("$ym Cumulative Update $OsName $DisplayVersion x64")
            }
        } else {
            if (-not [string]::IsNullOrWhiteSpace($DisplayVersion)) {
                $monthQueries.Add("$ym Cumulative Update $OsName $DisplayVersion x64")
                if ($IncludePreview) { $monthQueries.Add("$ym Cumulative Update Preview $OsName $DisplayVersion x64") }
            }
            $monthQueries.Add("$ym $OsName $Build x64")
        }

        foreach ($q in $monthQueries) {
            & $QueryCatalogBlock $q
        }

        $monthHits = @($candidates | Where-Object { $_.DateScore -ge $ymInt })
        if ($monthHits.Count -gt 0) { break }
    }

    # Phase B: Fallback year queries (for EOL branches like non-ESU Windows 10 22H2 older than 3 months)
    if ($candidates.Count -eq 0) {
        $CurYear         = $Now.Year
        $PrevYear        = $CurYear - 1
        $fallbackQueries = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($DisplayVersion)) {
            $fallbackQueries.Add("$CurYear Cumulative Update for $OsName version $DisplayVersion x64")
            $fallbackQueries.Add("$PrevYear Cumulative Update for $OsName version $DisplayVersion x64")
        }
        $fallbackQueries.Add("$CurYear Security Update $Build")
        $fallbackQueries.Add("$PrevYear Security Update $Build")
        $fallbackQueries.Add("Cumulative Update $OsName $Build x64")

        foreach ($q in $fallbackQueries) {
            & $QueryCatalogBlock $q
        }
    }

    if ($candidates.Count -eq 0) {
        Write-StepWarn "No matching LCU found on Catalog for $EditionTag Build $Build. Skipping."
        return $false
    }

    # Rank strictly by DateScore DESC first
    $rankedCandidates = @(
        $candidates | Sort-Object -Property @(
            @{ Expression = { $_.DateScore }; Descending = $true },
            @{ Expression = { $_.UBR };       Descending = $true }
        )
    )

    # Snapshot installed packages
    $installedPkgNames = @(
        Get-WindowsPackage -Path $MountPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageState -eq "Installed" } |
        ForEach-Object { $_.PackageName }
    )

    Write-StepInfo "Resolving Microsoft CDN links for newest x64 candidate..."
    $latestLcu = $null
    $urls      = @()

    foreach ($cand in $rankedCandidates) {
        if ($cand.UBR -gt 0 -and $cand.UBR -le $UBR) {
            Write-StepInfo "Already at or above $($cand.Title) ($Build.$UBR >= $Build.$($cand.UBR))."
            break
        }

        if (-not [string]::IsNullOrWhiteSpace($cand.KB)) {
            $kbMatch = $installedPkgNames | Where-Object { $_ -like "*$($cand.KB)*" } | Select-Object -First 1
            if ($kbMatch) {
                Write-StepOk "Package $($cand.KB.ToUpperInvariant()) is already installed in image. Skipping."
                return $false
            }
        }

        $payload = ConvertTo-Json -InputObject @(@{ size = 0; updateID = $cand.Guid; uidInfo = $cand.Guid }) -Compress
        try {
            $dlg = Invoke-WebRequest -Uri "https://www.catalog.update.microsoft.com/DownloadDialog.aspx" -Method Post `
                                    -Body @{ updateIDs = $payload } `
                                    -ContentType "application/x-www-form-urlencoded" `
                                    -UseBasicParsing `
                                    -Headers @{ Referer = "https://www.catalog.update.microsoft.com/" } `
                                    -TimeoutSec 25
            $foundUrls = @(
                [regex]::Matches($dlg.Content, 'https?://[^\s<>''"]+?\.(?:msu|cab)') |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -notmatch 'arm64' -and $_ -notmatch '[-_]x86[-_.]' } |
                Select-Object -Unique
            )
            if ($foundUrls.Count -gt 0) {
                $latestLcu = $cand
                $urls      = $foundUrls
                break
            }
        } catch {
            continue
        }
    }

    if (-not $latestLcu) {
        Write-StepOk "Image ($Build.$UBR) is already up to date or no newer x64 LCU matched. Skipping."
        return $false
    }

    Write-StepInfo "Matched x64 LCU: $($latestLcu.Title)"
    if ($latestLcu.UBR -gt 0) {
        Write-StepOk "Update available: $Build.$UBR -> $Build.$($latestLcu.UBR)"
    } else {
        Write-StepOk "Update available: $($latestLcu.KB.ToUpperInvariant()) ($($latestLcu.DateScore))"
    }

    $FolderTag    = if ($latestLcu.UBR -gt 0) { "${Build}_$($latestLcu.UBR)" } elseif ($latestLcu.KB) { "${Build}_$($latestLcu.KB)" } else { "${Build}_$($latestLcu.DateScore)" }
    $TargetFolder = Join-Path $CacheDir $FolderTag
    if (-not (Test-Path $TargetFolder)) {
        New-Item -ItemType Directory -Force -Path $TargetFolder | Out-Null
    }

    $DownloadedCount = 0
    foreach ($url in $urls) {
        $fileName = [System.IO.Path]::GetFileName(([Uri]$url).LocalPath)
        $destPath = Join-Path $TargetFolder $fileName
        $tmpPath  = "$destPath.tmp"

        if ((Test-Path $destPath) -and ((Get-Item $destPath).Length -gt 102400)) {
            $sizeMb = [Math]::Round((Get-Item $destPath).Length / 1MB, 1)
            Write-StepOk "[Cache] $fileName ($sizeMb MB)"
            $DownloadedCount++
            continue
        }

        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
        Write-StepSub "Downloading $fileName..."

        $ok = $false
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -L --fail --retry 3 --retry-delay 5 --connect-timeout 30 -o "$tmpPath" "$url" | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpPath) -and ((Get-Item $tmpPath).Length -gt 102400)) {
                $ok = $true
            }
        }
        if (-not $ok) {
            Write-StepInfo "curl unavailable or failed - falling back to BITS/WebClient..."
            try {
                if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                    Start-BitsTransfer -Source $url -Destination $tmpPath -DisplayName "Nautilus Update: $fileName" -ErrorAction Stop | Out-Null
                } else {
                    $wc = New-Object System.Net.WebClient
                    $wc.DownloadFile($url, $tmpPath)
                }
                $ok = (Test-Path $tmpPath) -and ((Get-Item $tmpPath).Length -gt 102400)
            } catch {
                Write-StepErr "Download failed for ${fileName}: $($_.Exception.Message)"
            }
        }

        if ($ok) {
            Move-Item -Path $tmpPath -Destination $destPath -Force
            $sizeMb = [Math]::Round((Get-Item $destPath).Length / 1MB, 1)
            Write-StepOk "Downloaded $fileName ($sizeMb MB)"
            $DownloadedCount++
        } else {
            if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
        }
    }

    if ($DownloadedCount -lt $urls.Count) {
        Write-StepWarn "Incomplete update download ($DownloadedCount/$($urls.Count)). Skipping integration."
        return $false
    }

    Write-StepSub "Integrating update package(s) into install.wim (this may take a few minutes)..."

    $allPkgs = @(Get-ChildItem -Path $TargetFolder -File | Where-Object { $_.Extension -in @('.msu', '.cab') })
    $ssuPkgs = @($allPkgs | Where-Object { $_.Name -match 'ssu' })
    $mainMsu = $null
    if (-not [string]::IsNullOrWhiteSpace($latestLcu.KB)) {
        $mainMsu = $allPkgs | Where-Object { $_.Name -like "*$($latestLcu.KB)*.msu" -and $_.Name -notmatch 'ssu' } |
            Sort-Object Length -Descending | Select-Object -First 1
    }

    $exitCode = 0
    foreach ($ssu in $ssuPkgs) {
        Write-StepInfo "Applying Servicing Stack Update: $($ssu.Name)"
        dism.exe /Image:"$MountPath" /Add-Package /PackagePath:"$($ssu.FullName)" /Quiet /NoRestart | Out-Null
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { $exitCode = $LASTEXITCODE }
    }

    if ($mainMsu) {
        Write-StepInfo "Applying target LCU (checkpoints auto-resolved): $($mainMsu.Name)"
        dism.exe /Image:"$MountPath" /Add-Package /PackagePath:"$($mainMsu.FullName)" /Quiet /NoRestart | Out-Null
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { $exitCode = $LASTEXITCODE }
    } else {
        $restPkgs = $allPkgs | Where-Object { $_.Name -notmatch 'ssu' } | Sort-Object {
            $m = [regex]::Match($_.Name, 'kb(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) { [long]$m.Groups[1].Value } else { 0 }
        }
        foreach ($pkg in $restPkgs) {
            Write-StepInfo "Applying $($pkg.Name)..."
            dism.exe /Image:"$MountPath" /Add-Package /PackagePath:"$($pkg.FullName)" /Quiet /NoRestart | Out-Null
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { $exitCode = $LASTEXITCODE }
        }
    }

    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-StepOk "Windows Updates integrated cleanly."
        return $true
    } else {
        Write-StepWarn "DISM /Add-Package exited with code $exitCode. Continuing build."
        return $false
    }
}

# ==============================================================================
# Admin checking & Build configuration
# ==============================================================================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-StepErr "Please run PowerShell with Administrator privileges."
    Pause
    Exit 1
}

Clear-Host
Write-Banner

$Workspace  = Read-Input "Workspace directory" "C:\NautilusBuilder"
$MountDir   = Join-Path $Workspace "Mount"
$ExtractDir = Join-Path $Workspace "Extract"

$IsoPath = Read-Input "Windows 10/11 or LTSC ISO path (e.g. C:\Windows.iso)"
if (-not (Test-Path $IsoPath -PathType Leaf)) {
    Write-StepErr "ISO file not found at '$IsoPath'."
    Exit 1
}

$FinalISO = Read-Input "Output ISO path" "C:\Nautilus.iso"

$CompressionChoice = Read-Input "Image compression [1] WIM (Fast)  [2] ESD (Compact)" "1"
$CompressionLabel  = if ($CompressionChoice -eq "2") { "ESD (Recovery)" } else { "WIM (Max)" }

$UseDriverInjection = (Read-Input "Inject hardware drivers? [Y/N]" "N").ToUpperInvariant() -eq "Y"
$AutoScanDrivers    = $false
$DriverFolder       = ""

if ($UseDriverInjection) {
    $DriverInput = Read-Input "Driver folder (leave blank to export from current host)"
    if ([string]::IsNullOrWhiteSpace($DriverInput)) {
        $AutoScanDrivers = $true
        $DriverFolder    = Join-Path $Workspace "AutoDrivers"
    } elseif (Test-Path $DriverInput -PathType Container) {
        $FullWs  = [System.IO.Path]::GetFullPath($Workspace).TrimEnd('\')
        $FullDrv = [System.IO.Path]::GetFullPath($DriverInput).TrimEnd('\')
        if ($FullDrv -eq $FullWs -or $FullDrv.StartsWith("$FullWs\", [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-StepErr "Driver folder cannot be inside Workspace (it would be wiped during cleanup). Move it outside '$Workspace'."
            Exit 1
        }
        $DriverFolder = $DriverInput
    } else {
        Write-StepWarn "Driver folder not found - driver injection disabled."
        $UseDriverInjection = $false
    }
}

$UseNetFx3         = (Read-Input "Integrate .NET Framework 3.5 (offline SxS)? [Y/N]" "N").ToUpperInvariant() -eq "Y"
$UseHardwareBypass = (Read-Input "Enable Win11 hardware bypass (TPM/CPU/Secure Boot)? [Y/N]" "N").ToUpperInvariant() -eq "Y"
$UseAutoUpdate     = (Read-Input "Auto-download & integrate latest Windows Updates (LCU)? [Y/N]" "N").ToUpperInvariant() -eq "Y"
$IncludePreview    = $false
$AllowWin10ESU     = $false
if ($UseAutoUpdate) {
    $IncludePreview = (Read-Input "  Include optional Preview updates (newest C-week build)? [Y/N]" "N").ToUpperInvariant() -eq "Y"
    $AllowWin10ESU  = (Read-Input "  Allow Windows 10 22H2 ESU updates (post-Oct 2025)? (Answer if you're building Windows 10) [Y/N]" "N").ToUpperInvariant() -eq "Y"
}

$UseCustomWallpaper = (Read-Input "Apply PastelPink Nautilus wallpapers? [Y/N]" "Y").ToUpperInvariant() -eq "Y"
$UseVcRedist = (Read-Input "Bundle Visual C++ Redistributable (2015-2022 x64 & x86)? [Y/N]" "Y").ToUpperInvariant() -eq "Y"

Write-Host ""
Write-Host "$script:Pink$script:cArrow$script:Reset Post-install offline browser $script:Muted(Edge is removed)$script:Reset"
Write-Host "    $script:Muted[0] None   [1] Brave   [2] Firefox   [3] Chrome$script:Reset"
$BrowserChoice = Read-Input "Select browser [0-3]" "1"
$BrowserLabel  = switch ($BrowserChoice) {
    "1"     { "Brave (Standalone)" }
    "2"     { "Firefox (Offline)" }
    "3"     { "Chrome (Enterprise MSI)" }
    default { $BrowserChoice = "0"; "None" }
}

$OriginalIsoBytes = (Get-Item $IsoPath).Length
$DriverDisplay    = if (-not $UseDriverInjection) { "Disabled" } elseif ($AutoScanDrivers) { "Auto-export from host" } else { $DriverFolder }
$UpdateDisplay    = if (-not $UseAutoUpdate) {
    "Disabled"
} else {
    $flags = @()
    $flags += if ($IncludePreview) { "Stable+Preview" } else { "Stable" }
    if ($AllowWin10ESU) { $flags += "ESU" }
    "Auto-LCU (" + ($flags -join ", ") + ")"
}

$cfgLine = ([string]$script:cH) * 58
Write-Host ""
Write-Host "$script:Pink  $script:cTL$cfgLine$script:cTR$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  $script:Lav Build Configuration Summary$script:Reset"
Write-Host "$script:Pink  $script:cLM$cfgLine$script:cRM$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Workspace        : $script:Muted$Workspace$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Source ISO       : $script:Muted$IsoPath$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Output ISO       : $script:Muted$FinalISO$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Compression      : $script:White$CompressionLabel$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Drivers          : $script:White$DriverDisplay$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  .NET 3.5 (SxS)   : $script:White$(if ($UseNetFx3) {'Enabled'} else {'Disabled'})$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Hardware Bypass  : $script:White$(if ($UseHardwareBypass) {'Enabled (Win11 only)'} else {'Disabled'})$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Windows Updates  : $script:White$UpdateDisplay$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Wallpapers       : $script:White$(if ($UseCustomWallpaper) {'Nautilus Custom'} else {'Windows Default'})$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  Offline Browser  : $script:White$BrowserLabel$script:Reset"
Write-Host "$script:Pink  $script:cV$script:Reset  VC++ Redist      : $script:White$(if ($UseVcRedist) {'Enabled'} else {'Disabled'})$script:Reset"
Write-Host "$script:Pink  $script:cBL$cfgLine$script:cBR$script:Reset"
Write-Host ""

if ((Read-Input "Start build now? [Y/N]" "Y").ToUpperInvariant() -ne "Y") {
    Write-StepWarn "Build cancelled."
    Exit 0
}

$DefenderExcluded = $false
try {

# ==============================================================================
# [01/15] Workspace Cleanup & Driver Preparation
# ==============================================================================
Write-Phase 1 "Preparing workspace & driver staging"

foreach ($h in @("zCOMPONENTS", "zDEFAULT", "zNTUSER", "zSOFTWARE", "zUSRCLASS", "zSYSTEM")) {
    reg unload "HKLM\$h" 2>$null | Out-Null
}
if (Test-Path "$MountDir\Windows") {
    dism.exe /Unmount-Image /MountDir:"$MountDir" /Discard /Quiet | Out-Null
}
dism.exe /Cleanup-Wim /Quiet | Out-Null
dism.exe /Cleanup-Mountpoints /Quiet | Out-Null

if (Test-Path $Workspace) {
    Remove-Item -Path $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

New-Item -ItemType Directory -Force -Path $MountDir   | Out-Null
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

Add-MpPreference -ExclusionPath "$Workspace" -ErrorAction SilentlyContinue | Out-Null
$DefenderExcluded = $true
Write-StepOk "Workspace ready."

$BootDriverFolder = Join-Path $Workspace "BootDrivers"
if ($UseDriverInjection) {
    if ($AutoScanDrivers) {
        Write-StepInfo "Exporting third-party drivers from host system..."
        New-Item -ItemType Directory -Force -Path $DriverFolder | Out-Null
        try {
            Export-WindowsDriver -Online -Destination $DriverFolder -ErrorAction Stop | Out-Null
            Write-StepOk "Host drivers exported to $DriverFolder"
        } catch {
            Write-StepWarn "Driver export failed ($($_.Exception.Message)) - skipping driver injection."
            $UseDriverInjection = $false
        }
    }

    if ($UseDriverInjection) {
        New-Item -ItemType Directory -Force -Path $BootDriverFolder | Out-Null
        $BootCriticalClasses = @('SCSIAdapter', 'HDC', 'Volume', 'USB', 'Net', 'HIDClass', 'Mouse', 'Keyboard', 'System')
        Write-StepInfo "Filtering boot-critical drivers (NVMe/Storage/USB/Net) for boot.wim..."
        $AllInfs = Get-ChildItem -Path $DriverFolder -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue

        foreach ($Inf in $AllInfs) {
            $Header = Get-Content -Path $Inf.FullName -TotalCount 300 -ErrorAction SilentlyContinue
            $ClassMatch = $Header | Select-String -Pattern '^\s*Class\s*=\s*"?([a-zA-Z0-9_\-]+)"?' |
                Where-Object { $_.Line -notmatch 'ClassGuid' } | Select-Object -First 1
            if ($ClassMatch) {
                $DriverClass = $ClassMatch.Matches[0].Groups[1].Value.Trim()
                if ($BootCriticalClasses -contains $DriverClass) {
                    $FolderKey  = "$($Inf.BaseName)_$([Math]::Abs($Inf.Directory.FullName.GetHashCode()))"
                    $DestSubDir = Join-Path $BootDriverFolder $FolderKey
                    if (-not (Test-Path $DestSubDir)) {
                        Copy-Item -Path $Inf.Directory.FullName -Destination $DestSubDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        Write-StepOk "Boot-critical drivers staged."
    }
}

# ==============================================================================
# [02/15] Mounting ISO & Selecting SKUs
# ==============================================================================
Write-Phase 2 "Extracting source ISO & selecting Windows edition"

$IsoImage    = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
$DriveLetter = ($IsoImage | Get-Volume).DriveLetter
if (-not $DriveLetter) {
    Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    Write-StepErr "Failed to resolve drive letter from mounted ISO."
    Exit 1
}

Write-StepInfo "Copying ISO contents from ${DriveLetter}:\ to workspace..."
robocopy "${DriveLetter}:\" "$ExtractDir" /E /MT:8 /A-:R /NFL /NDL /NJH /NJS /nc /ns /np
$RoboCode = $LASTEXITCODE
Dismount-DiskImage -ImagePath $IsoPath | Out-Null

if ($RoboCode -ge 8) {
    Write-StepErr "robocopy failed (Exit code: $RoboCode)."
    Exit 1
}
Write-StepOk "Source ISO extracted."

$InstallSystem = if (Test-Path "$ExtractDir\sources\install.esd") { "esd" } else { "wim" }
Set-ItemProperty -Path "$ExtractDir\sources\install.$InstallSystem" -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
Set-ItemProperty -Path "$ExtractDir\sources\boot.wim" -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

Write-Host ""
dism.exe /Get-WimInfo /WimFile:"$ExtractDir\sources\install.$InstallSystem"
Write-Host ""
$WimIndex = Read-Input "Enter edition index to build (e.g. 1 or 6)" "1"

if ($InstallSystem -eq "esd") {
    Write-StepSub "Converting install.esd (Index $WimIndex) to writable install.wim..."
    $TempWim = "$ExtractDir\sources\install.wim"
    dism.exe /Export-Image /SourceImageFile:"$ExtractDir\sources\install.esd" /SourceIndex:$WimIndex /DestinationImageFile:"$TempWim" /Compress:fast
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $TempWim)) {
        Write-StepErr "Failed to convert install.esd to install.wim (Exit code: $LASTEXITCODE)."
        Exit 1
    }
    Remove-Item -Path "$ExtractDir\sources\install.esd" -Force
    $InstallSystem = "wim"
    $WimIndex      = "1"
    Write-StepOk "Converted to install.wim."
}

# ==============================================================================
# [03/15] Mounting install.wim, OS/LTSC Detection
# ==============================================================================
Write-Phase 3 "Mounting install.wim (Index $WimIndex) & integrating payloads"

dism.exe /Mount-Image /ImageFile:"$ExtractDir\sources\install.wim" /Index:$WimIndex /MountDir:"$MountDir" /Optimize
if ($LASTEXITCODE -ne 0) {
    Write-StepErr "Failed to mount install.wim (Exit code: $LASTEXITCODE)."
    Exit 1
}

# Detect OS Family (Windows 10/11), Edition (Pro/LTSC/IoT LTSC), Build, UBR & Version (incl. ReleaseId for LTSC 2019)
$CurBuild = 0; $CurUBR = 0; $CurDisp = ""; $CurEdition = ""
Ensure-HiveUnloaded "zSOFTWARE"
try {
    reg load HKLM\zSOFTWARE "$MountDir\Windows\System32\config\SOFTWARE" 2>$null | Out-Null
    $CurProp = Get-ItemProperty -Path "HKLM:\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    if ($CurProp.CurrentBuild)   { $CurBuild   = [int]$CurProp.CurrentBuild }
    if ($null -ne $CurProp.UBR)  { $CurUBR     = [int]$CurProp.UBR }
    if ($CurProp.DisplayVersion) { $CurDisp    = [string]$CurProp.DisplayVersion }
    elseif ($CurProp.ReleaseId)  { $CurDisp    = [string]$CurProp.ReleaseId }
    if ($CurProp.EditionID)      { $CurEdition = [string]$CurProp.EditionID }
} finally {
    Ensure-HiveUnloaded "zSOFTWARE"
}

$IsWin11     = ($CurBuild -ge 22000)
$IsLTSC      = ($CurEdition -like "*EnterpriseS*")
$OsFamily    = if ($IsWin11) { "Windows 11" } else { "Windows 10" }
$EditionDesc = if ([string]::IsNullOrWhiteSpace($CurEdition)) { $OsFamily } else { "$OsFamily $CurEdition" }
$OsVersionId = "$EditionDesc $CurDisp (Build $CurBuild.$CurUBR)"
Write-StepOk "Image mounted: $OsVersionId"

$NetFx3Succeeded = $false
if ($UseNetFx3) {
    $SxsDir    = "$ExtractDir\sources\sxs"
    $NetFx3Cab = Get-ChildItem -Path $SxsDir -Filter "*netfx3*.cab" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($NetFx3Cab) {
        $NetFx3State = (Get-WindowsOptionalFeature -Path $MountDir -FeatureName "NetFx3" -ErrorAction SilentlyContinue).State
        if ($NetFx3State -eq "Enabled") {
            Write-StepInfo ".NET Framework 3.5 is already enabled."
            $NetFx3Succeeded = $true
        } else {
            Write-StepSub "Integrating .NET Framework 3.5 from SxS..."
            dism.exe /Image:"$MountDir" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:"$SxsDir" /Quiet /NoRestart
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                Write-StepOk ".NET Framework 3.5 integrated."
                $NetFx3Succeeded = $true
            } else {
                Write-StepWarn ".NET 3.5 integration exited with code $LASTEXITCODE."
            }
        }
    } else {
        Write-StepWarn "NetFx3 .cab not found in '$SxsDir' - skipping."
    }
}

$UpdatesApplied = $false
if ($UseAutoUpdate) {
    $WorkspaceParent = Split-Path ($Workspace.TrimEnd('\')) -Parent
    if ([string]::IsNullOrWhiteSpace($WorkspaceParent)) { $WorkspaceParent = $Workspace }
    $UpdateCacheDir = Join-Path $WorkspaceParent "NautilusUpdatesCache"

    if ($CurBuild -gt 0) {
        $UpdatesApplied = [bool](Invoke-AutoWindowsUpdate -MountPath $MountDir `
            -Build $CurBuild -UBR $CurUBR -DisplayVersion $CurDisp `
            -IsLTSC $IsLTSC -IncludePreview $IncludePreview -AllowWin10ESU $AllowWin10ESU `
            -CacheDir $UpdateCacheDir)

        # Refresh Build/UBR for final build report if update succeeded
        if ($UpdatesApplied) {
            Ensure-HiveUnloaded "zSOFTWARE"
            try {
                reg load HKLM\zSOFTWARE "$MountDir\Windows\System32\config\SOFTWARE" 2>$null | Out-Null
                $NewProp = Get-ItemProperty -Path "HKLM:\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
                if ($null -ne $NewProp.UBR)  { $CurUBR  = [int]$NewProp.UBR }
                if ($NewProp.DisplayVersion) { $CurDisp = [string]$NewProp.DisplayVersion }
            } finally {
                Ensure-HiveUnloaded "zSOFTWARE"
            }
            $OsVersionId = "$EditionDesc $CurDisp (Build $CurBuild.$CurUBR)"
            Write-StepOk "Updated OS version: $OsVersionId"
        }
    } else {
        Write-StepWarn "Could not read OS build from mounted hive - skipping updates."
    }
}

Write-StepInfo "Saving pre-debloat inventory..."
$InstalledCapabilities = @(Get-WindowsCapability -Path $MountDir -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Installed" })
$InstalledFeatures     = @(Get-WindowsOptionalFeature -Path $MountDir -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" })
$PackageScan           = dism.exe /Image:"$MountDir" /Get-Packages /English
$PkgNames              = @($PackageScan | Select-String "Package Identity : " | ForEach-Object { $_.Line.Replace("Package Identity : ", "").Trim() })
$AppxScan              = @(Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue)

if ($InstalledCapabilities.Count -gt 0) { $InstalledCapabilities.Name | Out-File (Join-Path $Workspace "capabilities-before.txt") -Encoding UTF8 }
if ($InstalledFeatures.Count -gt 0)     { $InstalledFeatures.FeatureName | Out-File (Join-Path $Workspace "features-before.txt") -Encoding UTF8 }
$PackageScan | Out-File (Join-Path $Workspace "packages-before.txt") -Encoding UTF8
if ($AppxScan.Count -gt 0) {
    $AppxScan | ForEach-Object {
        $Fam = if ($_.PublisherId) { "$($_.DisplayName)_$($_.PublisherId)" } else { $_.DisplayName }
        "$($_.DisplayName) | $Fam | $($_.PackageName)"
    } | Out-File (Join-Path $Workspace "appx-before.txt") -Encoding UTF8
}

Ensure-HiveUnloaded "zSOFTWARE"
reg load HKLM\zSOFTWARE "$MountDir\Windows\System32\config\SOFTWARE" 2>$null | Out-Null
try {
    $BaseHive = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("zSOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages", $false)
    if ($BaseHive) {
        try {
            $FilteredPkgs = @($BaseHive.GetSubKeyNames() | Where-Object {
                $_ -notlike "Package_for_RollupFix*" -and
                $_ -notlike "Package_for_ServicingStack*" -and
                $_ -notlike "Package_for_KB*" -and
                $_ -notlike "Package_*_for_KB*"
            })
            $FilteredPkgs | Out-File (Join-Path $Workspace "hidden-packages-before.txt") -Encoding UTF8
        } finally {
            $BaseHive.Close()
            $BaseHive.Dispose()
        }
    }
} finally {
    Ensure-HiveUnloaded "zSOFTWARE"
}
Write-StepInfo "Inventory: $($AppxScan.Count) AppX $script:cDot $($InstalledFeatures.Count) Features $script:cDot $($InstalledCapabilities.Count) FOD $script:cDot $($PkgNames.Count) CBS"

# ==============================================================================
# [04/15] Removing Provisioned UWP/AppX Packages
# ==============================================================================
Write-Phase 4 "Debloating provisioned UWP/AppX apps"

$KeepApps = @(
    "Microsoft.DesktopAppInstaller",
    "Microsoft.NET.Native",
    "SecHealthUI",
    "Microsoft.WindowsStore",
    "Microsoft.Services.Store.Engagement",
    "Microsoft.StorePurchaseApp",
    "Microsoft.UI.Xaml",
    "Microsoft.VCLibs",
    "Microsoft.WindowsAppRuntime",
    "Microsoft.AV1VideoExtension",
    "Microsoft.AVCEncoderVideoExtension",
    "Microsoft.HEIFImageExtension",
    "Microsoft.HEVCVideoExtension",
    "Microsoft.MPEG2VideoExtension",
    "Microsoft.VP9VideoExtensions",
    "Microsoft.WebMediaExtensions",
    "Microsoft.WebpImageExtension"
)

$RemovedAppxCount = 0
foreach ($App in $AppxScan) {
    $IsKept = $false
    foreach ($Keep in $KeepApps) {
        if ($App.DisplayName -like "*$Keep*" -or $App.PackageName -like "*$Keep*") {
            $IsKept = $true
            break
        }
    }
    if (-not $IsKept) {
        Write-StepInfo "Removing $($App.DisplayName)"
        Remove-AppxProvisionedPackage -Path $MountDir -PackageName $App.PackageName -ErrorAction SilentlyContinue | Out-Null
        $RemovedAppxCount++
    } else {
        Write-StepOk "Keeping  $($App.DisplayName)"
    }
}
Write-StepOk "Removed $RemovedAppxCount provisioned AppX packages."

# ==============================================================================
# [05/15] Removing Optional Features/Capabilities (FOD)
# ==============================================================================
Write-Phase 5 "Removing Optional Features & Capabilities (FOD)"

$OptionalFeatures = @(
    "Recall",
    "Internet-Explorer-Optional-amd64",
    "Printing-Foundation-InternetPrinting-Client",
    "Printing-XPSServices-Features",
    "Printing-PrintToPDFServices-Features",
    "WorkFolders-Client",
    "SMB1Protocol",
    "SMB1Protocol-Client",
    "SMB1Protocol-Server",
    "WCF-Services45",
    "WCF-TCP-PortSharing45",
    "SmbDirect",
    "SMB1Protocol-Deprecation",
    "MicrosoftWindowsPowerShellV2",
    "MicrosoftWindowsPowerShellV2Root",
    "MSRDC-Infrastructure"
)

$AvailableFeatures = Get-WindowsOptionalFeature -Path $MountDir -ErrorAction SilentlyContinue |
    Where-Object { $_.State -ne "DisabledWithPayloadRemoved" }

if ($AvailableFeatures) {
    foreach ($FeatName in $OptionalFeatures) {
        if ($AvailableFeatures.FeatureName -contains $FeatName) {
            Write-StepInfo "Removing feature: $FeatName"
            Disable-WindowsOptionalFeature -Path $MountDir -FeatureName $FeatName -Remove -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

$CapabilityPatterns = @(
    "App.StepsRecorder*",
    "App.Support.QuickAssist*",
    "Browser.InternetExplorer*",
    "MathRecognizer*",
    "Microsoft.Wallpapers.Extended*",
    "Microsoft.Windows.PowerShell.ISE*",
    "Microsoft.Windows.WordPad*",
    "OneCoreUAP.OneSync*",
    "Print.Fax.Scan*",
    "Print.Management.Console*",
    "WMI-SNMP-Provider*",
    "Language.Handwriting*",
    "Language.OCR*",
    "Language.Speech*",
    "Language.TextToSpeech*",
    "Rsat.*",
    "VBSCRIPT*"
)

$CurrentCapabilities = Get-WindowsCapability -Path $MountDir -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq "Installed" -and $_.Name -notlike "*Language.Basic*" }

foreach ($Cap in $CurrentCapabilities) {
    foreach ($Pat in $CapabilityPatterns) {
        if ($Cap.Name -like $Pat) {
            Write-StepInfo "Removing capability: $($Cap.Name)"
            Remove-WindowsCapability -Path $MountDir -Name $Cap.Name -ErrorAction SilentlyContinue | Out-Null
            break
        }
    }
}
Write-StepOk "Optional Features & FOD cleanup finished."

# ==============================================================================
# [06/15] Component Store Cleanup & ResetBase ("BEFORE" CBS Unlock & Manual deletes)
# ==============================================================================
Write-Phase 6 "Running Component Store cleanup (ResetBase)"

if ($CurBuild -ge 18362) {
    Write-StepInfo "Disabling Reserved Storage..."
    dism.exe /Image:"$MountDir" /Set-ReservedStorageState /State:Disabled /Quiet | Out-Null
}

if (-not $UpdatesApplied) {
    Write-StepSub "Executing DISM /StartComponentCleanup /ResetBase (clean WinSxS state)..."
    dism.exe /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase
    if ($LASTEXITCODE -eq 0) {
        Write-StepOk "Component Store compacted with ResetBase."
    } else {
        Write-StepWarn "ResetBase returned code $LASTEXITCODE (likely Checkpoint LCU in base ISO) - falling back to standard cleanup..."
        dism.exe /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup
        if ($LASTEXITCODE -eq 0) {
            Write-StepOk "Standard Component Cleanup succeeded."
        } else {
            Write-StepWarn "Component Cleanup exited with code $LASTEXITCODE. Image remains intact."
        }
    }
} else {
    Write-StepInfo "Skipping ResetBase because pending Windows Updates were integrated."
}

# ==============================================================================
# [07/15] Unlocking & Removing Hidden CBS Packages (Windows 10/11 & LTSC)
# ==============================================================================
Write-Phase 7 "Unlocking & removing hidden CBS packages"

$CbsTargetPatterns = @(
    # Core bloat (Windows 10 & 11 as well)
    "*OneDrive-Setup*",
    "*Internet-Browser-Package*",
    "*Windows-Browser-Package*",
    "*NewTabPageHost*",
    "*InternetExplorer*",
    "*QuickAssist*",
    "*StepsRecorder*",
    "*TabletPCMath*",
    "*Wallpaper-Content-Extended*",
    "*WordPad*",
    "*RemoteAssistance*",
    "*Printing-XPSServices*",
    "*Printing-XpsDocumentWriter*",
    "*FaxServices*",
    "*ContactSupport*",
    "*WorkFolders*",
    "*RetailDemo*",
    "*Windows-AI-Copilot*",
    "*Microsoft-Copilot-Package*",
    "*UserExperience-AIX-Package*",
    "*UserExperience-Recall-Package*",
    "*FlipGridPWA*",
    "*OutlookPWA*",
    "*CEIPEnable*",
    "*Recall*",
    "*LanguageFeatures-Handwriting*",
    "*LanguageFeatures-OCR*",
    "*LanguageFeatures-Speech*",
    "*LanguageFeatures-TextToSpeech*",
    "*PowerShell-ISE*",
    "*OpenSSH-Server*",
    "*Customer-Experience-Improvement*",
    "*MicrosoftEdgeDevToolsClient*",
    "*SenseClient*",
    "*ScreenSavers-3D*",
    "*WinSATMediaFiles*",
    "*MultiPoint*",
    "*Windows-Embedded-*",
    "*Client-AssignedAccess*",
    "*Windows-PAW*",

    # "Deep" clean (Pro / Enterprise / LTSC leftovers & legacy components) for sure
    "*Holographic-Desktop*",
    "*ApplicationGuard*",
    "*Windows-HVSI*",
    "*WMPNetworkSharingService*",
    "*WindowsMediaPlayer-Troubleshooters*",
    "*MediaPlayer-Payload*",
    "*AppManagement-AppV*",
    "*AppManagement-UEV*",
    "*DirectoryServices-ADAM*",
    "*MSMQ*",
    "*IIS-WebServer*",
    "*DataCenterBridging*",
    "*PeerDist*",
    "*EnterpriseClientSync*",
    "*OfflineFiles*",
    "*Host-Guardian*",
    "*HgsClient*",
    "*Shielded-VM*",
    "*SimpleTCP*",
    "*Telnet-Client*",
    "*TFTP-Client*",
    "*NFS-*",
    "*ClientForNFS*",
    "*Client-ShellLauncher*",
    "*Client-EmbeddedExp*",
    "*Management-SecureAssessment*",
    "*IoTUAP*",
    "*WindowsIoT*",
    "*Help-ClientOOBE*",
    "*Help-ClientUA*",
    "*Server-Help-Package*"
)

Write-StepSub "Unlocking CBS visibility & ownership for active target packages..."
Unlock-OfflineCbsPackages -MountPath $MountDir -TargetPatterns $CbsTargetPatterns

$UnlockedPackages = Get-WindowsPackage -Path $MountDir -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PackageState -in @("Installed", "Staged") -and
        $_.PackageName -notlike "Package_for_RollupFix*" -and
        $_.PackageName -notlike "Package_for_ServicingStack*" -and
        $_.PackageName -notlike "Package_for_DotNetRollup*" -and
        $_.PackageName -notlike "Package_for_KB*" -and
        $_.PackageName -notlike "Package_*_for_KB*" -and
        $_.PackageName -notlike "*Enablement*" -and
        $_.PackageName -notlike "*Product-Data*EKB*" -and
        $_.PackageName -notlike "*UpdateTargeting*EKB*"
    }

$CbsRemoved = 0
foreach ($Pkg in $UnlockedPackages) {
    foreach ($Pattern in $CbsTargetPatterns) {
        if ($Pkg.PackageName -like $Pattern) {
            Write-StepInfo "Removing $($Pkg.PackageName)"
            dism.exe /Image:"$MountDir" /Remove-Package /PackageName:"$($Pkg.PackageName)" /Quiet /NoRestart | Out-Null
            $CbsRemoved++
            break
        }
    }
}

dism.exe /Image:"$MountDir" /Remove-Edge /Quiet /NoRestart 2>$null | Out-Null

Write-StepInfo "Cleaning orphaned Default App Associations..."
$AssocFile = Join-Path $Workspace "appassoc.xml"
dism.exe /Image:"$MountDir" /Export-DefaultAppAssociations:"$AssocFile" | Out-Null
if (Test-Path $AssocFile) {
    $CleanAssoc = Get-Content -Path $AssocFile | Where-Object { $_ -notmatch 'MicrosoftEdge|Zune|Bing|Xbox' }
    $CleanAssoc | Set-Content -Path $AssocFile -Encoding UTF8 -Force
    dism.exe /Image:"$MountDir" /Import-DefaultAppAssociations:"$AssocFile" | Out-Null
}
Write-StepOk "Processed $CbsRemoved CBS packages."

# ==============================================================================
# [08/15] Removing Edge, OneDrive, Dead SystemApps
# ==============================================================================
Write-Phase 8 "Removing Edge/OneDrive, dead SystemApps & unlocking DMA policy"

$ManualDeletePaths = @(
    "$MountDir\Program Files (x86)\Microsoft\Edge",
    "$MountDir\Program Files (x86)\Microsoft\EdgeUpdate",
    "$MountDir\Program Files (x86)\Microsoft\EdgeCore",
    "$MountDir\Windows\System32\Microsoft-Edge-Webview",
    "$MountDir\Windows\System32\OneDriveSetup.exe",
    "$MountDir\Windows\SysWOW64\OneDriveSetup.exe"
)

foreach ($Target in $ManualDeletePaths) {
    if (Test-Path -LiteralPath $Target) {
        if (Remove-PathForce $Target) {
            Write-StepInfo "Removed $($Target.Replace($MountDir, ''))"
        } else {
            Write-StepWarn "Could not fully remove $($Target.Replace($MountDir, ''))"
        }
    }
}

# Remove obsolete SystemApps
$SystemAppPatterns = @(
    "Microsoft.Windows.PeopleExperienceHost_*",
    "Microsoft.Windows.ParentalControls_*",
    "Microsoft.Windows.NarratorQuickStart_*",
    "Microsoft.Windows.CallingShellApp_*",
    "Microsoft.ECApp_*"
)
$SysAppsRoot = "$MountDir\Windows\SystemApps"
if (Test-Path $SysAppsRoot) {
    foreach ($Pat in $SystemAppPatterns) {
        Get-ChildItem -Path $SysAppsRoot -Directory -Filter $Pat -ErrorAction SilentlyContinue | ForEach-Object {
            if (Remove-PathForce $_.FullName) {
                Write-StepInfo "Removed SystemApp: $($_.Name)"
            }
        }
    }
}

$DmaPolicyJson = "$MountDir\Windows\System32\IntegratedServicesRegionPolicySet.json"
if (Test-Path $DmaPolicyJson) {
    takeown.exe /F "$DmaPolicyJson" /A 2>$null | Out-Null
    icacls.exe "$DmaPolicyJson" /grant "*S-1-5-32-544:(F)" /C /Q 2>$null | Out-Null
    $JsonRaw = Get-Content -Path $DmaPolicyJson -Raw -Encoding UTF8
    $JsonRaw = $JsonRaw -replace '"defaultState"\s*:\s*"disabled"', '"defaultState": "enabled"'
    [System.IO.File]::WriteAllText($DmaPolicyJson, $JsonRaw, (New-Object System.Text.UTF8Encoding $false))
    Write-StepOk "DMA Region Policy unlocked."
}

# ==============================================================================
# [09/15] Registry Hardening, IFEO Telemetry Block & Scheduled Task Cleanup
# ==============================================================================
Write-Phase 9 "Applying registry tweaks, IFEO blocks & scheduled task cleanup"

foreach ($h in @("zUSRCLASS", "zCOMPONENTS", "zDEFAULT", "zNTUSER", "zSOFTWARE", "zSYSTEM")) {
    Ensure-HiveUnloaded $h
}

try {
    reg load HKLM\zCOMPONENTS "$MountDir\Windows\System32\config\COMPONENTS" | Out-Null
    reg load HKLM\zDEFAULT    "$MountDir\Windows\System32\config\default"    | Out-Null
    reg load HKLM\zNTUSER     "$MountDir\Users\Default\ntuser.dat"           | Out-Null
    reg load HKLM\zSOFTWARE   "$MountDir\Windows\System32\config\SOFTWARE"   | Out-Null
    reg load HKLM\zSYSTEM     "$MountDir\Windows\System32\config\SYSTEM"     | Out-Null

    if ($UseHardwareBypass -and $IsWin11) {
        Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV1' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV2' 'REG_DWORD' '0'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck'        'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck'        'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck'    'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck'        'REG_DWORD' '1'
        Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup'   'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
    }

    # Content Delivery & Start Menu
    $cdm = 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($val in @(
        'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled',
        'SilentInstalledAppsEnabled', 'ContentDeliveryAllowed', 'FeatureManagementEnabled',
        'SoftLandingEnabled', 'SubscribedContentEnabled', 'SubscribedContent-310093Enabled',
        'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
        'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
        'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled', 'SystemPaneSuggestionsEnabled'
    )) {
        Set-RegistryValue $cdm $val 'REG_DWORD' '0'
    }
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures'     'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent'       'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall'        'DisablePushToInstall'               'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT'                  'DontOfferThroughWUAU'               'REG_DWORD' '1'
    Remove-RegistryValue "$cdm\Subscriptions"
    Remove-RegistryValue "$cdm\SuggestedApps"

    if ($IsWin11) {
        [Microsoft.Win32.Registry]::SetValue(
            'HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\PolicyManager\current\device\Start',
            'ConfigureStartPins',
            '{"pinnedList": []}',
            [Microsoft.Win32.RegistryValueKind]::String
        )
    }

    # Local accounts, Reserved Storage, BitLocker
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE'           'BypassNRO'               'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves'     'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker'                   'PreventDeviceEncryption' 'REG_DWORD' '1'

    # Disable unnecessary background services
    foreach ($svc in @(
        'SysMain', 'DiagTrack', 'TrkWks', 'MapsBroker', 'SDRSVC', 'wbengine', 'fhsvc',
        'wisvc', 'RemoteRegistry', 'PhoneSvc', 'RetailDemo', 'shpamsvc', 'dmwappushservice',
        'BcastDVRUserService', 'GameBarPresenceWriter', 'UCPD'
    )) {
        Set-RegistryValue "HKLM\zSYSTEM\ControlSet001\Services\$svc" 'Start' 'REG_DWORD' '4'
    }

    # IFEO silent block for telemetry runners (for "the" sfc/scannow)
    foreach ($exe in @('CompatTelRunner.exe', 'DeviceCensus.exe', 'wermgr.exe')) {
        Set-RegistryValue "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe" 'Debugger' 'REG_SZ' '%SystemRoot%\System32\systray.exe'
    }

    # Taskbar, Chat, Widgets, Background Apps & QOL
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat'                   'ChatIcon'                  'REG_DWORD' '3'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn'                 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa'                 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Control Panel\Accessibility\StickyKeys'                      'Flags'                     'REG_SZ'    '506'

    # Windows 10 Taskbar cleanup (harmless on Win11)
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds'             'ShellFeedsTaskbarViewMode' 'REG_DWORD' '2'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'            'SearchboxTaskbarMode'      'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCortanaButton'         'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'        'HideSCAMeetNow'            'REG_DWORD' '1'

    # Telemetry & Privacy
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection'  'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'

    # Block forced inbox apps
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate'      'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate'      'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams'                'DisableInstallation' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun'          'REG_DWORD' '1'

    # Disable Folder Auto-Discovery
    $UsrClassPath = "$MountDir\Users\Default\AppData\Local\Microsoft\Windows\UsrClass.dat"
    if (Test-Path $UsrClassPath) {
        reg load HKLM\zUSRCLASS "$UsrClassPath" 2>$null | Out-Null
        Set-RegistryValue 'HKLM\zUSRCLASS\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' 'FolderType' 'REG_SZ' 'NotSpecified'
    }

    # Search, Bing, Copilot, Recall, Delivery Optimization, OneDrive, GameDVR, Edge leftovers, Hibernation
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search'       'ConnectedSearchUseWeb'     'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search'       'DisableWebSearch'          'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'  'BingSearchEnabled'         'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'  'CortanaConsent'            'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh'                          'AllowNewsAndInterests'     'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Feeds'        'EnableFeeds'               'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'       'TurnOffWindowsCopilot'     'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge'                         'HubsSidebarEnabled'        'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer'             'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'            'DisableAIDataAnalysis'     'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'            'TurnOffSavingSnapshots'    'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode'            'REG_DWORD' '0'
    Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Active Setup\Installed Components\{8A69D345-D564-463c-AFF1-A69D9E530F96}'
    Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive'           'DisableFileSyncNGSC'           'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'           'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\GameDVR'            'AllowGameDVR'                  'REG_DWORD' '0'
    Remove-RegistryValue 'HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    Remove-RegistryValue 'HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\EdgeUpdate'                          'DoNotUpdateToEdgeWithChromium' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Power'                     'HibernateEnabledDefault'       'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Power'                     'HibernateEnabled'              'REG_DWORD' '0'

    # Expanded Telemetry, UCPD & Maintenance Scheduled Tasks
    $tasksPath = "$MountDir\Windows\System32\Tasks\Microsoft\Windows"
    $TasksToRemove = @(
        "Application Experience\Microsoft Compatibility Appraiser",
        "Application Experience\ProgramDataUpdater",
        "AppxDeploymentClient\UCPD velocity",
        "Autochk\Proxy",
        "Chkdsk\Proxy",
        "Customer Experience Improvement Program",
        "DiskDiagnostic",
        "Feedback\Siuf",
        "Maintenance\WinSAT",
        "Maps",
        "PI",
        "Power Efficiency Diagnostics",
        "Shell\FamilySafetyMonitor",
        "Shell\FamilySafetyRefreshTask",
        "Windows Error Reporting\QueueReporting"
    )
    foreach ($t in $TasksToRemove) {
        Remove-Item -Path (Join-Path $tasksPath $t) -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-StepOk "Offline registry tweaks, IFEO blocks & task cleanup applied."
} finally {
    foreach ($h in @("zUSRCLASS", "zCOMPONENTS", "zDEFAULT", "zNTUSER", "zSOFTWARE", "zSYSTEM")) {
        Ensure-HiveUnloaded $h
    }
}

# ==============================================================================
# [10/15] Driver Injection & Servicing/Cleanup
# ==============================================================================
Write-Phase 10 "Injecting OS drivers & clearing servicing caches & logs"

if ($UseDriverInjection) {
    $InfCount = (Get-ChildItem -Path $DriverFolder -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($InfCount -gt 0) {
        Write-StepSub "Injecting $InfCount driver package(s) into offline OS..."
        dism.exe /Image:"$MountDir" /Add-Driver /Driver:"$DriverFolder" /Recurse /ForceUnsigned | Out-Null
        Write-StepOk "OS driver injection completed."
    }
} else {
    Write-StepInfo "Driver injection skipped."
}

if (-not $UpdatesApplied) {
    Remove-Item -Path "$MountDir\Windows\WinSxS\Temp\*"        -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$MountDir\Windows\WinSxS\InstallTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item -Path "$MountDir\Windows\SoftwareDistribution\Download\*"  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$MountDir\Windows\SoftwareDistribution\DataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$MountDir\Windows\Logs\*"                           -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$MountDir\Windows\Panther\*"                        -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$MountDir\Windows\Temp\*"                           -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$MountDir\Windows\INF\setupapi.*.log"               -Force          -ErrorAction SilentlyContinue
Write-StepOk "Temporary servicing caches & build logs cleared."

# ==============================================================================
# [11/15] Custom Wallpapers & Post-Debloat Inventory
# ==============================================================================
Write-Phase 11 "Applying wallpapers & scanning post-debloat state"

if ($UseCustomWallpaper) {
    $HomeWallUrl = "https://raw.githubusercontent.com/epiphany-sudo/Nautilus_NZZT_Experimental/refs/heads/NZZT_Open/Wallpaper/NZZTHomeScreen.jpg"
    $LockWallUrl = "https://raw.githubusercontent.com/epiphany-sudo/Nautilus_NZZT_Experimental/refs/heads/NZZT_Open/Wallpaper/NZZTLockScreen.jpg"
    $TempHome    = Join-Path $Workspace "NZZTHomeScreen.jpg"
    $TempLock    = Join-Path $Workspace "NZZTLockScreen.jpg"
    $Wall4KDir   = "$MountDir\Windows\Web\4K\Wallpaper\Windows"
    $WallStdDir  = "$MountDir\Windows\Web\Wallpaper\Windows"
    $ScreenDir   = "$MountDir\Windows\Web\Screen"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    try {
        Invoke-WebRequest -Uri $HomeWallUrl -OutFile $TempHome -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        if ((Test-Path $TempHome) -and ((Get-Item $TempHome).Length -gt 10240)) {
            foreach ($Dir in @($Wall4KDir, $WallStdDir)) {
                if (Test-Path $Dir) {
                    takeown.exe /F "$Dir" /R /A /D Y 2>$null | Out-Null
                    icacls.exe "$Dir" /grant "*S-1-5-32-544:(F)" /T /C /Q 2>$null | Out-Null
                }
            }
            if (Test-Path $Wall4KDir) {
                Get-ChildItem -Path $Wall4KDir -Filter "*.jpg" -File | ForEach-Object {
                    Set-ItemProperty -Path $_.FullName -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    Copy-Item -Path $TempHome -Destination $_.FullName -Force
                }
            }
            if (Test-Path $WallStdDir) {
                foreach ($FileName in @("img0.jpg", "img19.jpg")) {
                    $TargetFile = Join-Path $WallStdDir $FileName
                    if (Test-Path $TargetFile) { Set-ItemProperty -Path $TargetFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue }
                    Copy-Item -Path $TempHome -Destination $TargetFile -Force
                }
            }
            Write-StepOk "Applied Nautilus desktop wallpapers (4K & standard)."
        }
    } catch {
        Write-StepWarn "Desktop wallpaper download failed ($($_.Exception.Message)) - keeping defaults."
    }

    try {
        Invoke-WebRequest -Uri $LockWallUrl -OutFile $TempLock -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        if ((Test-Path $TempLock) -and ((Get-Item $TempLock).Length -gt 10240) -and (Test-Path $ScreenDir)) {
            takeown.exe /F "$ScreenDir" /R /A /D Y 2>$null | Out-Null
            icacls.exe "$ScreenDir" /grant "*S-1-5-32-544:(F)" /T /C /Q 2>$null | Out-Null
            $LockTarget = Join-Path $ScreenDir "img100.jpg"
            if (Test-Path $LockTarget) { Set-ItemProperty -Path $LockTarget -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue }
            Copy-Item -Path $TempLock -Destination $LockTarget -Force
            Write-StepOk "Applied Nautilus lock screen wallpaper."
        }
    } catch {
        Write-StepWarn "Lock screen download failed ($($_.Exception.Message)) - keeping defaults."
    }
} else {
    Write-StepInfo "Keeping Windows default wallpapers."
}

$AfterCapabilities = @(Get-WindowsCapability -Path $MountDir -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Installed" })
$AfterFeatures     = @(Get-WindowsOptionalFeature -Path $MountDir -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" })
$AfterPkgScan      = dism.exe /Image:"$MountDir" /Get-Packages /English
$AfterPkgNames     = @($AfterPkgScan | Select-String "Package Identity : " | ForEach-Object { $_.Line.Replace("Package Identity : ", "").Trim() })
$AfterAppx         = @(Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue)
Write-StepInfo "Post-debloat: $($AfterAppx.Count) AppX $script:cDot $($AfterFeatures.Count) Features $script:cDot $($AfterCapabilities.Count) FOD $script:cDot $($AfterPkgNames.Count) CBS"

# ==============================================================================
# [12/15] Committing & Optimizing install.wim
# ==============================================================================
Write-Phase 12 "Committing & compressing install image ($CompressionLabel)"

foreach ($h in @("zUSRCLASS", "zCOMPONENTS", "zDEFAULT", "zNTUSER", "zSOFTWARE", "zSYSTEM")) {
    Ensure-HiveUnloaded $h
}
Set-Location -Path $env:SystemRoot
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
Start-Sleep -Seconds 3

$UnmountSuccess = $false
for ($try = 1; $try -le 3; $try++) {
    dism.exe /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -eq 0) { $UnmountSuccess = $true; break }
    Write-StepWarn "Unmount attempt $try failed (Code: $LASTEXITCODE) - releasing handles and retrying..."
    Get-Process -Name "DismHost" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 5
}
if (-not $UnmountSuccess) {
    Write-StepErr "Failed to commit install.wim after 3 attempts."
    Exit 1
}

$DestExt       = if ($CompressionChoice -eq '2') { "esd" } else { "wim" }
$CompressType  = if ($CompressionChoice -eq '2') { "recovery" } else { "max" }
$SourceFile    = "$ExtractDir\sources\install.$InstallSystem"
$OptimizedFile = "$ExtractDir\sources\install_optimized.$DestExt"

Write-StepSub "Exporting to install.$DestExt ($CompressType)..."
dism.exe /Export-Image /SourceImageFile:"$SourceFile" /SourceIndex:$WimIndex /DestinationImageFile:"$OptimizedFile" /Compress:$CompressType | Out-Null
if ($LASTEXITCODE -ne 0 -or !(Test-Path $OptimizedFile)) {
    Write-StepErr "Failed to export optimized image (Exit code: $LASTEXITCODE)."
    Exit 1
}

Remove-Item -Path $SourceFile -Force
Rename-Item -Path $OptimizedFile -NewName "install.$DestExt"
$InstallSystem = $DestExt
Write-StepOk "Exported optimized install.$DestExt."

# ==============================================================================
# [13/15] Patching & Re-exporting boot.wim
# ==============================================================================
Write-Phase 13 "Patching & compacting boot.wim (WinPE drivers & bypass)"

$NeedBootPatch = $UseDriverInjection -or ($UseHardwareBypass -and $IsWin11)
if ($NeedBootPatch) {
    Ensure-HiveUnloaded "zSYSTEM"
    dism.exe /Mount-Image /ImageFile:"$ExtractDir\sources\boot.wim" /Index:2 /MountDir:"$MountDir" /Optimize
    if ($LASTEXITCODE -ne 0) {
        Write-StepErr "Failed to mount boot.wim (Exit code: $LASTEXITCODE)."
        Exit 1
    }

    if ($UseDriverInjection -and (Test-Path $BootDriverFolder)) {
        $BootInfCount = (Get-ChildItem -Path $BootDriverFolder -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($BootInfCount -gt 0) {
            Write-StepSub "Injecting $BootInfCount boot-critical driver(s) into WinPE..."
            dism.exe /Image:"$MountDir" /Add-Driver /Driver:"$BootDriverFolder" /Recurse /ForceUnsigned | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-StepOk "WinPE drivers injected." }
            else { Write-StepWarn "Some WinPE drivers failed to inject (Code: $LASTEXITCODE)." }
        }
    }

    if ($UseHardwareBypass -and $IsWin11) {
        try {
            reg load HKLM\zSYSTEM "$MountDir\Windows\System32\config\SYSTEM" | Out-Null
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck'        'REG_DWORD' '1'
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck'        'REG_DWORD' '1'
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck'    'REG_DWORD' '1'
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck'        'REG_DWORD' '1'
            Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup'   'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'

            $AppraiserDll = "$ExtractDir\sources\appraiserres.dll"
            if (Test-Path $AppraiserDll) {
                Set-ItemProperty -Path $AppraiserDll -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                Clear-Content -Path $AppraiserDll -Force -ErrorAction SilentlyContinue
            }
            Write-StepOk "Hardware bypass patched in WinPE."
        } finally {
            Ensure-HiveUnloaded "zSYSTEM"
        }
    }

    dism.exe /Unmount-Image /MountDir:"$MountDir" /Commit
    if ($LASTEXITCODE -ne 0) {
        Write-StepErr "Failed to commit boot.wim (Exit code: $LASTEXITCODE)."
        Exit 1
    }

    Write-StepSub "Compacting boot.wim (max compression)..."
    $BootSrc     = "$ExtractDir\sources\boot.wim"
    $BootOpt     = "$ExtractDir\sources\boot_optimized.wim"
    $BootIndexes = @((Get-WindowsImage -ImagePath $BootSrc -ErrorAction SilentlyContinue).ImageIndex)
    if ($BootIndexes.Count -eq 0) { $BootIndexes = @(1, 2) }

    $BootExportOk = $true
    foreach ($idx in $BootIndexes) {
        dism.exe /Export-Image /SourceImageFile:"$BootSrc" /SourceIndex:$idx /DestinationImageFile:"$BootOpt" /Compress:max | Out-Null
        if ($LASTEXITCODE -ne 0) { $BootExportOk = $false; break }
    }
    if ($BootExportOk -and (Test-Path $BootOpt)) {
        Remove-Item -Path $BootSrc -Force
        Rename-Item -Path $BootOpt -NewName "boot.wim"
        Write-StepOk "boot.wim compacted."
    } else {
        if (Test-Path $BootOpt) { Remove-Item -Path $BootOpt -Force -ErrorAction SilentlyContinue }
        Write-StepWarn "boot.wim re-export skipped - keeping committed boot.wim."
    }
} else {
    Write-StepInfo "No boot.wim modifications required for $OsFamily - skipped."
}

# ==============================================================================
# [14/15] Integrating OS-Specific autounattend.xml & Offline Post-Install ($OEM$)
# ==============================================================================
Write-Phase 14 "Generating $OsFamily autounattend.xml & post-install bundle"

$XmlWin11 = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>Re-register Windows Security UI (SecHealthUI)</Description>
                    <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$pkgs = Get-AppxPackage -AllUsers *SecHealthUI*; if ($pkgs) { $pkgs | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register ($_.InstallLocation + '\AppXManifest.xml') -ErrorAction SilentlyContinue } } else { $appx = Get-ChildItem 'C:\Windows\System32\SecurityHealth' -Recurse -Filter '*SecHealthUI*.appx' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($appx) { Add-AppxPackage -Path $appx.FullName -ErrorAction SilentlyContinue } }; Start-Service SecurityHealthService -ErrorAction SilentlyContinue"</CommandLine>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Description>Run Nautilus Post-Install fallback (for OEM BIOS key devices)</Description>
                    <CommandLine>cmd.exe /c if not exist "C:\Windows\Setup\Scripts\nautilus.done" if exist "C:\Windows\Setup\Scripts\SetupComplete.cmd" call "C:\Windows\Setup\Scripts\SetupComplete.cmd"</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
            <ConfigureChatAutoInstall>false</ConfigureChatAutoInstall>
        </component>
    </settings>
    <settings pass="windowsPE">
        <component xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DynamicUpdate>
                <WillShowUI>OnError</WillShowUI>
            </DynamicUpdate>
            <ImageInstall>
                <OSImage>
                    <Compact>false</Compact>
                    <WillShowUI>OnError</WillShowUI>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>1</Value>
                        </MetaData>
                    </InstallFrom>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                    <Key/>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
            </UserData>
        </component>
    </settings>
</unattend>
'@

$XmlWin10 = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            name="Microsoft-Windows-Shell-Setup"
            processorArchitecture="amd64"
            publicKeyToken="31bf3856ad364e35"
            language="neutral"
            versionScope="nonSxS">
            <OOBE>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideEULAPage>true</HideEULAPage>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>Run Nautilus Post-Install fallback (for OEM BIOS key devices)</Description>
                    <CommandLine>cmd.exe /c if not exist "C:\Windows\Setup\Scripts\nautilus.done" if exist "C:\Windows\Setup\Scripts\SetupComplete.cmd" call "C:\Windows\Setup\Scripts\SetupComplete.cmd"</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
    <settings pass="windowsPE">
        <component
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            name="Microsoft-Windows-Setup"
            processorArchitecture="amd64"
            publicKeyToken="31bf3856ad364e35"
            language="neutral"
            versionScope="nonSxS">
            <DynamicUpdate>
                <WillShowUI>OnError</WillShowUI>
                <Enable>false</Enable>
            </DynamicUpdate>
            <ImageInstall>
                <OSImage>
                    <Compact>true</Compact>
                    <WillShowUI>OnError</WillShowUI>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>1</Value>
                        </MetaData>
                    </InstallFrom>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>
                    <Key/>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>
</unattend>
'@

$SelectedXml  = if ($IsWin11) { $XmlWin11 } else { $XmlWin10 }
$UnattendPath = "$ExtractDir\autounattend.xml"
if (Test-Path -LiteralPath $UnattendPath) {
    attrib.exe -R -H -S "$UnattendPath" 2>$null | Out-Null
    Set-ItemProperty -LiteralPath $UnattendPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
}
[System.IO.File]::WriteAllText($UnattendPath, $SelectedXml, (New-Object System.Text.UTF8Encoding $false))
Write-StepOk "Generated autounattend.xml ($OsFamily profile)."

if ($BrowserChoice -ne "0" -or $UseVcRedist) {
    $OemScriptsDir = Join-Path $ExtractDir 'sources\$OEM$\$$\Setup\Scripts'
    New-Item -ItemType Directory -Force -Path $OemScriptsDir | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    $SetupCmdLines = @(
        '@echo off',
        'title PastelPink Nautilus Post-Install',
        'cd /d "%~dp0"',
        'if exist "%~dp0nautilus.done" exit /b 0'
    )

    if ($UseVcRedist) {
        Write-StepSub "Downloading Visual C++ Redistributable (x64 & x86)..."
        $VcPackages = @(
            @{ Name = "vc_redist.x64.exe"; Url = "https://aka.ms/vs/17/release/vc_redist.x64.exe" },
            @{ Name = "vc_redist.x86.exe"; Url = "https://aka.ms/vs/17/release/vc_redist.x86.exe" }
        )
        foreach ($Vc in $VcPackages) {
            $VcDest = Join-Path $OemScriptsDir $Vc.Name
            try {
                Invoke-WebRequest -Uri $Vc.Url -OutFile $VcDest -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
                if ((Test-Path $VcDest) -and ((Get-Item $VcDest).Length -gt 1MB)) {
                    $SetupCmdLines += "if exist `"%~dp0$($Vc.Name)`" (start /wait `"`" `"%~dp0$($Vc.Name)`" /install /quiet /norestart & del /f /q `"%~dp0$($Vc.Name)`" >nul 2>&1)"
                    Write-StepOk "Bundled $($Vc.Name)"
                }
            } catch {
                Write-StepWarn "Failed to download $($Vc.Name): $($_.Exception.Message)"
            }
        }
    }

    if ($BrowserChoice -in @("1", "2", "3")) {
        $BrowserPkg = $null
        switch ($BrowserChoice) {
            "1" {
                # Query recent 25 releases to avoid /releases/latest hitting Android tags
                try {
                    $Rels  = Invoke-RestMethod -Uri "https://api.github.com/repos/brave/brave-browser/releases?per_page=25" -Headers @{ "User-Agent" = "NautilusBuilder" } -TimeoutSec 30
                    $Asset = $Rels | Where-Object { -not $_.prerelease } |
                        ForEach-Object { $_.assets } |
                        Where-Object { $_.name -eq "BraveBrowserStandaloneSilentSetup.exe" -or $_.name -eq "BraveBrowserStandaloneSetup.exe" } |
                        Select-Object -First 1
                    if ($Asset) {
                        $BrowserPkg = @{
                            Name = $Asset.name
                            Url  = $Asset.browser_download_url
                            Cmd  = "start /wait `"`" `"%~dp0$($Asset.name)`" --install --silent --system-level"
                        }
                    } else {
                        Write-StepWarn "Could not find Brave Windows standalone asset in latest GitHub releases."
                    }
                } catch {
                    Write-StepWarn "Could not resolve Brave offline release from GitHub: $($_.Exception.Message)"
                }
            }
            "2" {
                $BrowserPkg = @{
                    Name = "FirefoxSetup.exe"
                    Url  = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
                    Cmd  = "start /wait `"`" `"%~dp0FirefoxSetup.exe`" -ms"
                }
            }
            "3" {
                $BrowserPkg = @{
                    Name = "ChromeStandalone64.msi"
                    Url  = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
                    Cmd  = "start /wait msiexec.exe /i `"%~dp0ChromeStandalone64.msi`" /qn /norestart"
                }
            }
        }

        if ($BrowserPkg) {
            Write-StepSub "Downloading $BrowserLabel ($($BrowserPkg.Name))..."
            $BrowserDest = Join-Path $OemScriptsDir $BrowserPkg.Name
            try {
                if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                    & curl.exe -L --fail --retry 3 --connect-timeout 30 -o "$BrowserDest" "$($BrowserPkg.Url)" | Out-Null
                } else {
                    Invoke-WebRequest -Uri $BrowserPkg.Url -OutFile $BrowserDest -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
                }
                if ((Test-Path $BrowserDest) -and ((Get-Item $BrowserDest).Length -gt 20MB)) {
                    $sizeMb = [Math]::Round((Get-Item $BrowserDest).Length / 1MB, 1)
                    $SetupCmdLines += "if exist `"%~dp0$($BrowserPkg.Name)`" ($($BrowserPkg.Cmd) && del /f /q `"%~dp0$($BrowserPkg.Name)`" >nul 2>&1)"
                    Write-StepOk "Bundled $($BrowserPkg.Name) ($sizeMb MB - 100% offline)"
                } else {
                    Remove-Item -Path $BrowserDest -Force -ErrorAction SilentlyContinue
                    Write-StepWarn "Downloaded browser file looks incomplete - skipped."
                }
            } catch {
                Write-StepWarn "Failed to download ${BrowserLabel}: $($_.Exception.Message)"
            }
        }
    }

    $SetupCmdLines += 'echo done>"%~dp0nautilus.done"'
    $SetupCmdLines += 'exit /b 0'
    $SetupCompletePath = Join-Path $OemScriptsDir "SetupComplete.cmd"
    if (Test-Path -LiteralPath $SetupCompletePath) {
        attrib.exe -R -H -S "$SetupCompletePath" 2>$null | Out-Null
        Set-ItemProperty -LiteralPath $SetupCompletePath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }
    [System.IO.File]::WriteAllLines($SetupCompletePath, $SetupCmdLines, (New-Object System.Text.UTF8Encoding $false))
    Write-StepOk "SetupComplete.cmd staged in `$OEM` (with FirstLogon OEM-key fallback)."
}

# ==============================================================================
# [15/15] Trimming ISO Shell, Building Bootable ISO & Generating Summary Report
# ==============================================================================
Write-Phase 15 "Trimming ISO shell, packaging bootable ISO & generating report"

$IsoTrimFolders = @(
    "$ExtractDir\support",
    "$ExtractDir\sources\migwiz"
)
if ($NetFx3Succeeded) {
    $IsoTrimFolders += "$ExtractDir\sources\sxs"
}
foreach ($Dir in $IsoTrimFolders) {
    if (Test-Path $Dir) {
        Remove-Item -Path $Dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-StepInfo "Trimmed ISO folder: $($Dir.Replace($ExtractDir, ''))"
    }
}

$OscdimgPath  = Get-OscdimgPath
$MicrosoftUrl = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

if (-not $OscdimgPath) {
    $OscdimgPath = Join-Path $Workspace "oscdimg.exe"
    Write-StepInfo "oscdimg.exe not found locally - fetching from Microsoft Symbol Server..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $MicrosoftUrl -OutFile $OscdimgPath -UseBasicParsing `
                          -Headers @{ "User-Agent" = "Microsoft-Symbol-Server/10.0.0.0" } -ErrorAction Stop
        Write-StepOk "Downloaded oscdimg.exe."
    } catch {
        Write-StepErr "Could not download oscdimg.exe. Please install Windows ADK or check your connection."
        Exit 1
    }
} else {
    Write-StepInfo "Using oscdimg.exe at $OscdimgPath"
}

$FinalIsoDir = Split-Path -Path $FinalISO -Parent
if (-not [string]::IsNullOrWhiteSpace($FinalIsoDir) -and -not (Test-Path $FinalIsoDir)) {
    New-Item -ItemType Directory -Force -Path $FinalIsoDir | Out-Null
}

Write-StepSub "Building ISO image..."
$BuildArgs = "-m -o -u2 -udfver102 -bootdata:2#p0,e,bboot\etfsboot.com#pEF,e,befi\microsoft\boot\efisys.bin `"$ExtractDir`" `"$FinalISO`""
$Proc      = Start-Process -FilePath $OscdimgPath -ArgumentList $BuildArgs -WorkingDirectory $ExtractDir -Wait -NoNewWindow -PassThru

if ($Proc.ExitCode -eq 0 -and (Test-Path $FinalISO)) {
    $FinalIsoBytes = (Get-Item $FinalISO).Length
    $OrigGb        = [Math]::Round($OriginalIsoBytes / 1GB, 2)
    $FinalGb       = [Math]::Round($FinalIsoBytes / 1GB, 2)
    $SavedGb       = [Math]::Round(($OriginalIsoBytes - $FinalIsoBytes) / 1GB, 2)
    $Sha256Hash    = (Get-FileHash -Path $FinalISO -Algorithm SHA256).Hash.ToLowerInvariant()
    $IsoFileName   = Split-Path -Path $FinalISO -Leaf

    "$Sha256Hash  $IsoFileName" | Out-File -FilePath "$FinalISO.sha256" -Encoding ASCII -Force

    $RemovedAppx = [Math]::Max(0, $AppxScan.Count - $AfterAppx.Count)
    $RemovedFeat = [Math]::Max(0, $InstalledFeatures.Count - $AfterFeatures.Count)
    $RemovedCaps = [Math]::Max(0, $InstalledCapabilities.Count - $AfterCapabilities.Count)
    $RemovedPkgs = [Math]::Max(0, $PkgNames.Count - $AfterPkgNames.Count)

    $ReportLines = @(
        "====================================================",
        "  PastelPink Nautilus - Build Summary Report",
        "====================================================",
        "Build Date       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Target OS        : $OsVersionId",
        "Output ISO       : $FinalISO",
        "SHA256           : $Sha256Hash",
        "Original Size    : $OrigGb GB",
        "Final Size       : $FinalGb GB (Delta: -$SavedGb GB)",
        "Image Format     : $($InstallSystem.ToUpperInvariant())",
        "----------------------------------------------------",
        "Debloat Statistics:",
        "  - Provisioned AppX Removed   : $RemovedAppx ($($AppxScan.Count) -> $($AfterAppx.Count))",
        "  - Optional Features Purged   : $RemovedFeat ($($InstalledFeatures.Count) -> $($AfterFeatures.Count))",
        "  - Capabilities (FOD) Removed : $RemovedCaps ($($InstalledCapabilities.Count) -> $($AfterCapabilities.Count))",
        "  - CBS Packages Removed       : $RemovedPkgs ($($PkgNames.Count) -> $($AfterPkgNames.Count))",
        "----------------------------------------------------",
        "Included Features:",
        "  - Windows Updates            : $UpdatesApplied ($UpdateDisplay)",
        "  - Hardware Bypass            : $($UseHardwareBypass -and $IsWin11)",
        "  - Post-Install Browser       : $BrowserLabel",
        "  - Visual C++ Redistributable : $UseVcRedist",
        "===================================================="
    )
    $ReportPath = "$FinalISO.report.txt"
    $ReportLines | Out-File -FilePath $ReportPath -Encoding UTF8 -Force

    $doneLine = ([string]$script:cH) * 48
    Write-Host ""
    Write-Host "$script:Mint  $script:cTL$doneLine$script:cTR$script:Reset"
    Write-Host "$script:Mint  $script:cV   Build complete! Your Nautilus ISO is ready   $script:cV$script:Reset"
    Write-Host "$script:Mint  $script:cBL$doneLine$script:cBR$script:Reset"
    Write-StepOk   "OS     : $OsVersionId"
    Write-StepOk   "ISO    : $FinalISO"
    Write-StepInfo "Size   : $OrigGb GB -> $FinalGb GB (Saved $SavedGb GB)"
    Write-StepInfo "SHA256 : $Sha256Hash"
    Write-StepInfo "Report : $ReportPath"
} else {
    Write-StepErr "oscdimg failed (Exit code: $($Proc.ExitCode)). Extracted files preserved at: $ExtractDir"
    Exit 1
}

} finally {
    if ($DefenderExcluded) {
        Remove-MpPreference -ExclusionPath "$Workspace" -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host ""
if ((Read-Input "Delete workspace '$Workspace'? [Y/N]" "Y").ToUpperInvariant() -eq "Y") {
    attrib -R "$Workspace\*.*" /S /D 2>$null | Out-Null
    Remove-Item -Path $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    Write-StepOk "Workspace cleaned up."
}

Write-Host ""
Read-Host "Press Enter to exit"
