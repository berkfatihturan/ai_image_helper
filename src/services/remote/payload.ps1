<#
.SYNOPSIS
    Görünmez Windows UI Otomasyon Tarayıcı (Native PowerShell)
.DESCRIPTION
    Bu script, hedef Windows makinesinde "Sıfır Kurulum" mantığıyla çalışarak 
    açık pencereleri (.NET UIAutomationClient) ile tarar ve JSON çıktısı üretir.
#>

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Web.Extensions # JSON Serializer icin (eski sistemler dahil)

# -WindowStyle Hidden komutuyla baslasa bile pencerenin ekrandan tamamen
# kaybolmasina (flush) firsat vermek icin minik bir gecikme ekliyoruz
Start-Sleep -Milliseconds 200

try {
    $rootElement = [System.Windows.Automation.AutomationElement]::RootElement

    if ($rootElement -eq $null) {
        Write-Error "Root element bulunamadi. UI Automation baslatilamadi."
        exit 1
    }

    # --- YARDIMCI FOKSIYONLAR ---
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

    function Get-ControlTypeString ($controlTypeId) {
        $typeInfo = [System.Windows.Automation.ControlType]::LookupById($controlTypeId)
        if ($typeInfo) {
            return $typeInfo.ProgrammaticName.Replace("ControlType.", "")
        }
        return "Unknown"
    }

    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class User32 {
        [DllImport("user32.dll", SetLastError = true, CharSet=CharSet.Auto)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    }
"@

    function Get-NativeClassName ($hwnd) {
        if ($hwnd -eq [IntPtr]::Zero) { return "" }
        $sb = New-Object System.Text.StringBuilder(256)
        $res = [User32]::GetClassName($hwnd, $sb, $sb.Capacity)
        if ($res -gt 0) { return $sb.ToString() }
        return ""
    }

    # Z-Order hiyerarsisi (en ust pencere -> en alt zemin) sirasi korumak icin ControlViewWalker kullanilir.
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($rootElement)
    $topLevelWindows = @()
    while ($child -ne $null) {
        $topLevelWindows += $child
        $child = $walker.GetNextSibling($child)
    }

    $allElementsOutput = @()
    $currentZIndex = 0

    $meaningfulTypes = @(
        "Button", "Edit", "Hyperlink", "MenuItem", "Text", "CheckBox",
        "ComboBox", "ListItem", "TabItem", "Document", "Image", "Pane",
        "TreeItem", "DataItem", "Custom", "Group", "SplitButton", 
        "StatusBar", "Tab", "Table", "TitleBar", "Window"
    )

    foreach ($window in $topLevelWindows) {
        try {
            if ($window.Current.IsOffscreen) { continue }
            
            $cTypeString = Get-ControlTypeString $window.Current.ControlType.Id
            
            # Sadece Window olanlari, Taskbar'i ve Desktop'u kabul edelim. 
            # Diger abuk subuk gorunmez Pane'leri reddedelim.
            $hwnd = [IntPtr]$window.Current.NativeWindowHandle
            $className = Get-NativeClassName $hwnd
            
            if ($cTypeString -eq "Pane") {
                # Eger bir Pane ise, sadece Taskbar veya Desktop ise kabul et
                $validPanes = @("Shell_TrayWnd", "Progman", "WorkerW")
                if ($validPanes -notcontains $className) {
                    continue
                }
            } elseif ($cTypeString -ne "Window") {
                # Pane de degil, Window da degilse (ornek: ToolTip) ana kapsayici olarak reddet
                continue
            }
            
            $wRect = Get-BoundingRect $window
            if ($wRect -eq $null) { continue }
            
            $parentName = $window.Current.Name
            $isDesktop = ($className -eq "Progman" -or $className -eq "WorkerW")
            $myZIndex = $currentZIndex
            
            if ([string]::IsNullOrWhiteSpace($parentName)) { 
                if ($className -eq "Shell_TrayWnd") { $parentName = "Windows Taskbar" }
                elseif ($isDesktop) { $parentName = "Windows Desktop" }
                else { $parentName = "Bilinmeyen Pencere" }
            }
            
            $color = @( (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250) )
            $pBorder = @($wRect.x, $wRect.y, ($wRect.x + $wRect.genislik), ($wRect.y + $wRect.yukseklik))
            
            $windowGroup = @{
                pencere = $parentName
                z_index = $myZIndex
                renk = $color
                kutu = $pBorder
                elmanlar = [System.Collections.ArrayList]::new()
            }
            
            # Elementleri toplamak icin agaci gezelim
            $treeWalker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
            
            # C# tarzi queue implementasyonu kullanarak BFS
            $queue = New-Object System.Collections.Queue
            $queue.Enqueue($window)
            $elementCount = 0
            
            while ($queue.Count -gt 0 -and $elementCount -lt 4000) {
                $node = $queue.Dequeue()
                
                # Cocuklari siraya ekle
                try {
                    $child = $treeWalker.GetFirstChild($node)
                    while ($child -ne $null) {
                        $queue.Enqueue($child)
                        $child = $treeWalker.GetNextSibling($child)
                    }
                } catch {}
                
                # Su anki dugumu isleyelim
                try {
                    $cRect = Get-BoundingRect $node
                    # Coken UI ve cok kucuk sacma elementleri engelle
                    if ($cRect -eq $null -or $cRect.genislik -le 0 -or $cRect.yukseklik -le 0) { continue }
                    
                    $cType = Get-ControlTypeString $node.Current.ControlType.Id
                    $cName = if ([string]::IsNullOrWhiteSpace($node.Current.Name)) { "" } else { $node.Current.Name.Trim() }
                    
                    # Temel filtresiz izleme: sadece gozukmeyen hayalet pencerelerin devasa zeminlerini ele (ornegin bos Group/Pane ve devasa)
                    # Masaustu ikonlarini ve gorev cubugu dugmelerini ASLA KESMEYIZ.
                    if ($cName -eq "" -and ($cType -eq "Pane" -or $cType -eq "Group" -or $cType -eq "Custom") -and ($cRect.genislik -ge ($wRect.genislik - 10) -and $cRect.yukseklik -ge ($wRect.yukseklik - 10))) {
                        continue
                    }
                    
                    $centerX = [math]::Round($cRect.x + ($cRect.genislik / 2))
                    $centerY = [math]::Round($cRect.y + ($cRect.yukseklik / 2))
                    
                    $elData = @{
                        tip = $cType
                        isim = $cName
                        koordinat = $cRect
                        merkez_koordinat = @{
                            x = $centerX
                            y = $centerY
                        }
                    }
                    
                    [void]$windowGroup.elmanlar.Add($elData)
                    $elementCount++
                } catch {}
            }
            
            $windowGroup.elmanlar = $windowGroup.elmanlar.ToArray()
            $allElementsOutput += $windowGroup
            $currentZIndex++
        } catch {
            # Pencere okuma hatasi
        }
    }

    # PowerShell'in kendi ConvertTo-Json cmdlet'i ile (PSMethod sorununu by-pass eder)
    # Eger veri buyukse Depth'i arttirmak hayat kurtarir
    $allJson = $allElementsOutput | ConvertTo-Json -Depth 10 -Compress

    $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

    [System.IO.File]::WriteAllText((Join-Path $outDir "ui_output_all.json"), $allJson, [System.Text.Encoding]::UTF8)

} catch {
    $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $errMsg = $_.Exception.Message + "`n" + $_.ScriptStackTrace
    [System.IO.File]::WriteAllText((Join-Path $outDir "psexec_error.log"), $errMsg, [System.Text.Encoding]::UTF8)
}
