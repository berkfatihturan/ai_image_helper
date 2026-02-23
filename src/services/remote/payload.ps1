<#
.SYNOPSIS
    Görünmez Windows UI Otomasyon Tarayıcı (Native PowerShell) - Desktop/Taskbar + Desktop Icons FIX
.DESCRIPTION
    - UIAutomation ile açık pencereleri tarar, JSON üretir.
    - Taskbar (Shell_TrayWnd) ve Desktop (Progman/WorkerW) UIA’da görünmese bile
      EnumWindows + AutomationElement.FromHandle ile ZORLA ekler.
    - IsOffscreen filtresi Desktop/Taskbar için bypass edilir.
    - Desktop ikonlarını görebilmek için Desktop tarafında RawViewWalker ile dolaşır.
    - Desktop/WorkerW BoundingRectangle boş gelirse PrimaryScreen bounds ile doldurur.
IMPORTANT
    Bu script’i Desktop ikonlarını görmek için STA ile çalıştır:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File .\ui_scan.ps1 "C:\Temp"
#>

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Start-Sleep -Milliseconds 200

try {
    $rootElement = [System.Windows.Automation.AutomationElement]::RootElement
    if ($rootElement -eq $null) {
        Write-Error "Root element bulunamadi. UI Automation baslatilamadi."
        exit 1
    }

    # --- USER32: ENUMWINDOWS / GETCLASSNAME ---
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class User32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet=CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

    # --- HELPERS ---
    function Get-ControlTypeString ($controlTypeId) {
        $typeInfo = [System.Windows.Automation.ControlType]::LookupById($controlTypeId)
        if ($typeInfo) { return $typeInfo.ProgrammaticName.Replace("ControlType.", "") }
        return "Unknown"
    }

    function Get-NativeClassName ($hwnd) {
        if ($hwnd -eq [IntPtr]::Zero) { return "" }
        $sb = New-Object System.Text.StringBuilder(256)
        $res = [User32]::GetClassName($hwnd, $sb, $sb.Capacity)
        if ($res -gt 0) { return $sb.ToString() }
        return ""
    }

    function Get-BoundingRect ($element) {
        try {
            $rect = $element.Current.BoundingRectangle
            if ($rect.IsEmpty) { return $null }
            return @{
                x = [math]::Round($rect.Left)
                y = [math]::Round($rect.Top)
                genislik = [math]::Round($rect.Width)
                yukseklik = [math]::Round($rect.Height)
            }
        } catch {
            return $null
        }
    }

    function Get-PrimaryScreenRect {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        return @{
            x = $b.X
            y = $b.Y
            genislik = $b.Width
            yukseklik = $b.Height
        }
    }

    function Get-SystemHwnds {
        $targets = New-Object System.Collections.Generic.List[System.IntPtr]
        $wanted = @("Shell_TrayWnd", "Progman", "WorkerW")

        $cb = [User32+EnumWindowsProc]{
            param([IntPtr]$hWnd, [IntPtr]$lParam)

            $cls = Get-NativeClassName $hWnd
            if ($wanted -contains $cls) {
                $targets.Add($hWnd) | Out-Null
            }
            return $true
        }

        [User32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
        return $targets
    }

    # RawViewWalker ile descendants topla (Desktop ikonlarını görmek için)
    function Get-DescendantsRaw {
        param(
            [System.Windows.Automation.AutomationElement]$root,
            [int]$max = 20000
        )

        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $q = New-Object System.Collections.Queue
        $out = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]

        $q.Enqueue($root)

        while ($q.Count -gt 0 -and $out.Count -lt $max) {
            $cur = $q.Dequeue()

            $child = $null
            try { $child = $walker.GetFirstChild($cur) } catch { $child = $null }

            while ($child -ne $null) {
                $out.Add($child) | Out-Null
                $q.Enqueue($child)

                $next = $null
                try { $next = $walker.GetNextSibling($child) } catch { $next = $null }
                $child = $next
            }
        }

        return $out
    }

    # Desktop içinde FolderView katmanını bul (oraya in)
    function Get-DesktopRootNode {
        param([System.Windows.Automation.AutomationElement]$desktopWindow)

        $nodes = Get-DescendantsRaw -root $desktopWindow -max 8000

        foreach ($n in $nodes) {
            try {
                $name = $n.Current.Name
                if ($name -eq "FolderView") { return $n }

                $ct = Get-ControlTypeString $n.Current.ControlType.Id
                if (($ct -eq "List" -or $ct -eq "Pane") -and $name -match "FolderView") { return $n }
            } catch {}
        }

        return $desktopWindow
    }

    # Top level windows (UIA) + System HWND forced
    $trueCondition = [System.Windows.Automation.Condition]::TrueCondition
    $topLevelWindows = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $trueCondition)

    $systemHwnds = Get-SystemHwnds
    $extraElements = @()
    foreach ($h in $systemHwnds) {
        try {
            $ae = [System.Windows.Automation.AutomationElement]::FromHandle($h)
            if ($ae -ne $null) { $extraElements += $ae }
        } catch {}
    }

    # uniq by hwnd
    $seen = @{}
    $merged = New-Object System.Collections.ArrayList

    foreach ($w in $topLevelWindows) {
        try {
            $hw = [int64]([IntPtr]$w.Current.NativeWindowHandle)
            if (-not $seen.ContainsKey($hw)) { $seen[$hw] = $true; [void]$merged.Add($w) }
        } catch {}
    }
    foreach ($w in $extraElements) {
        try {
            $hw = [int64]([IntPtr]$w.Current.NativeWindowHandle)
            if (-not $seen.ContainsKey($hw)) { $seen[$hw] = $true; [void]$merged.Add($w) }
        } catch {}
    }
    $topLevelWindows = $merged

    $allElementsOutput = @()
    $currentZIndex = 10

    $validChildTypes = @(
        "Button","CheckBox","ComboBox","Document","Edit","Hyperlink","Image",
        "ListItem","MenuItem","RadioButton","Slider","Spinner","TabItem","Text",
        "TreeItem","Thumb","HeaderItem","Pane","Group","Custom","List",
        "DataItem","Item"
    )

    $systemClasses = @("Shell_TrayWnd","Progman","WorkerW")

    foreach ($window in $topLevelWindows) {
        try {
            $hwnd = [IntPtr]$window.Current.NativeWindowHandle
            $className = Get-NativeClassName $hwnd

            # IsOffscreen Desktop/Taskbar için bypass
            if ($window.Current.IsOffscreen -and ($systemClasses -notcontains $className)) {
                continue
            }

            $cTypeString = Get-ControlTypeString $window.Current.ControlType.Id

            # Window/Panes filtre
            if ($cTypeString -eq "Pane") {
                if ($systemClasses -notcontains $className) { continue }
            } elseif ($cTypeString -ne "Window") {
                if ($systemClasses -notcontains $className) { continue }
            }

            $isDesktop = ($className -eq "Progman" -or $className -eq "WorkerW")
            $isTaskbar = ($className -eq "Shell_TrayWnd")

            $wRect = Get-BoundingRect $window
            if ($wRect -eq $null) {
                if ($isDesktop) { $wRect = Get-PrimaryScreenRect }
                else { continue }
            }

            $parentName = $window.Current.Name
            if ([string]::IsNullOrWhiteSpace($parentName)) {
                if ($isTaskbar) { $parentName = "Windows Taskbar" }
                elseif ($isDesktop) { $parentName = "Windows Desktop" }
                else { $parentName = "Bilinmeyen Pencere" }
            }

            $myZIndex = $currentZIndex
            if ($isDesktop) { $myZIndex = 99990 }
            elseif ($isTaskbar) { $myZIndex = 1 }

            $color = @(
                (Get-Random -Minimum 50 -Maximum 250),
                (Get-Random -Minimum 50 -Maximum 250),
                (Get-Random -Minimum 50 -Maximum 250)
            )

            $pBorder = @($wRect.x, $wRect.y, ($wRect.x + $wRect.genislik), ($wRect.y + $wRect.yukseklik))

            $windowGroup = @{
                pencere  = $parentName
                z_index  = $myZIndex
                class    = $className
                hwnd     = [int64]$hwnd
                renk     = $color
                kutu     = $pBorder
                elmanlar = [System.Collections.ArrayList]::new()
            }

            # --- DESCENDANTS ---
            if ($isDesktop) {
                # Desktop ikonları için RawView
                $desktopRoot = Get-DesktopRootNode $window
                $descendants = Get-DescendantsRaw -root $desktopRoot -max 25000
            } else {
                $descendants = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $trueCondition)
            }

            $elementCount = 0
            foreach ($node in $descendants) {
                if ($elementCount -ge 12000) { break }
                try {
                    $cRect = Get-BoundingRect $node
                    if ($cRect -eq $null) { continue }

                    # Boyut filtreleri
                    if ($cRect.genislik -le 0 -or $cRect.yukseklik -le 0) { continue }
                    if ($cRect.genislik -lt 4 -or $cRect.yukseklik -lt 4) { continue }
                    if ($cRect.genislik -gt 4000 -or $cRect.yukseklik -gt 4000) { continue }

                    $nodeType = Get-ControlTypeString $node.Current.ControlType.Id
                    if ($validChildTypes -notcontains $nodeType) { continue }

                    $cName = if ([string]::IsNullOrWhiteSpace($node.Current.Name)) { "" } else { $node.Current.Name.Trim() }

                    # Desktop için bu filtreyi gevşet (ikonlarda Name bazen boş/garip olabilir)
                    if (-not $isDesktop) {
                        if ($cName -eq "" -and ($nodeType -eq "Pane" -or $nodeType -eq "Group" -or $nodeType -eq "Custom" -or $nodeType -eq "List")) {
                            continue
                        }
                    }

                    $centerX = [math]::Round($cRect.x + ($cRect.genislik / 2))
                    $centerY = [math]::Round($cRect.y + ($cRect.yukseklik / 2))

                    $elData = @{
                        tip = $nodeType
                        isim = $cName
                        koordinat = $cRect
                        merkez_koordinat = @{ x = $centerX; y = $centerY }
                    }

                    [void]$windowGroup.elmanlar.Add($elData)
                    $elementCount++
                } catch {}
            }

            $windowGroup.elmanlar = $windowGroup.elmanlar.ToArray()
            $allElementsOutput += $windowGroup

            if (-not $isDesktop -and -not $isTaskbar) { $currentZIndex += 10 }
        } catch {
            # ignore per-window errors
        }
    }

    # Output
    $allJson = $allElementsOutput | ConvertTo-Json -Depth 10 -Compress

    $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

    [System.IO.File]::WriteAllText((Join-Path $outDir "ui_output_all.json"), $allJson, [System.Text.Encoding]::UTF8)

    # Desktop ikonlarını ayrıca debug olarak çıkar (isteğe bağlı ama işe yarıyor)
    $desktop = $allElementsOutput | Where-Object { $_.pencere -eq "Windows Desktop" } | Select-Object -First 1
    if ($desktop -ne $null) {
        $icons = @($desktop.elmanlar | Where-Object { $_.tip -eq "ListItem" -or $_.tip -eq "Item" -or $_.tip -eq "DataItem" })
        $iconsJson = $icons | ConvertTo-Json -Depth 6 -Compress
        [System.IO.File]::WriteAllText((Join-Path $outDir "desktop_icons.json"), $iconsJson, [System.Text.Encoding]::UTF8)
    }

} catch {
    $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $errMsg = $_.Exception.Message + "`n" + $_.ScriptStackTrace
    [System.IO.File]::WriteAllText((Join-Path $outDir "psexec_error.log"), $errMsg, [System.Text.Encoding]::UTF8)
}