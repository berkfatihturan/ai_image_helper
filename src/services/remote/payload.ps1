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

    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class User32 {
        [DllImport("user32.dll", SetLastError = true, CharSet=CharSet.Auto)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    }
"@

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

    function Get-NativeClassName ($hwnd) {
        if ($hwnd -eq [IntPtr]::Zero) { return "" }
        $sb = New-Object System.Text.StringBuilder(256)
        $res = [User32]::GetClassName($hwnd, $sb, $sb.Capacity)
        if ($res -gt 0) { return $sb.ToString() }
        return ""
    }

    # Sadece Window'lari degil, Taskbar (Gorev Cubugu) ve Masaustu (Desktop) gibi
    # sistem bilesenlerini de yakalamak icin filtreyi kaldiriyoruz
    $trueCondition = [System.Windows.Automation.Condition]::TrueCondition
    $topLevelWindows = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $trueCondition)

    $allElementsOutput = @()
    $currentZIndex = 10

    # UI elementleri icin detayli ControlType listesi
    $validChildTypes = @("Button", "CheckBox", "ComboBox", "Document", "Edit", "Hyperlink", "Image", "ListItem", "MenuItem", "RadioButton", "Slider", "Spinner", "TabItem", "Text", "TreeItem", "Thumb", "HeaderItem", "Pane", "Group", "Custom", "List")

    foreach ($window in $topLevelWindows) {
        try {
            if ($window.Current.IsOffscreen) { continue }
            
            $cTypeString = Get-ControlTypeString $window.Current.ControlType.Id
            $hwnd = [IntPtr]$window.Current.NativeWindowHandle
            $className = Get-NativeClassName $hwnd
            
            # Sadece Window olanlari, Taskbar'i ve Desktop'u kabul edelim. 
            if ($cTypeString -eq "Pane") {
                $validPanes = @("Shell_TrayWnd", "Progman", "WorkerW")
                if ($validPanes -notcontains $className) {
                    continue
                }
            } elseif ($cTypeString -ne "Window") {
                continue
            }
            
            $wRect = Get-BoundingRect $window
            if ($wRect -eq $null) { continue }
            
            $parentName = $window.Current.Name
            $isDesktop = ($className -eq "Progman" -or $className -eq "WorkerW")
            $isTaskbar = ($className -eq "Shell_TrayWnd")
            
            $myZIndex = $currentZIndex
            if ($isDesktop) { $myZIndex = 99990 }
            elseif ($isTaskbar) { $myZIndex = 1 }
            
            if ([string]::IsNullOrWhiteSpace($parentName)) { 
                if ($isTaskbar) { $parentName = "Windows Taskbar" }
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
            
            # Alt elementleri BFS/TreeWalker yerine tek seferde Get-Descendants ile al (Klasor listelerini kaybetmemek icin)
            $descendants = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $trueCondition)
            
            $elementCount = 0
            foreach ($node in $descendants) {
                if ($elementCount -ge 5000) { break }
                try {
                    $cRect = Get-BoundingRect $node
                    if ($cRect -eq $null -or $cRect.genislik -le 0 -or $cRect.yukseklik -le 0) { continue }
                    
                    $nodeType = Get-ControlTypeString $node.Current.ControlType.Id
                    if ($validChildTypes -notcontains $nodeType) { continue }
                    
                    $cName = if ([string]::IsNullOrWhiteSpace($node.Current.Name)) { "" } else { $node.Current.Name.Trim() }
                    
                    # Saydam, isimsiz arkaplan katmanlarini (Group, Pane) listeye eklemeyelim, 
                    # ama icerisindeki Butonlar/Ikonlar haritaya dahil edilsin diye onlari engellemiyoruz (FindAll-Descendants sayesinde).
                    if ($cName -eq "" -and ($nodeType -eq "Pane" -or $nodeType -eq "Group" -or $nodeType -eq "Custom" -or $nodeType -eq "List")) { continue }
                    
                    $centerX = [math]::Round($cRect.x + ($cRect.genislik / 2))
                    $centerY = [math]::Round($cRect.y + ($cRect.yukseklik / 2))
                    
                    $elData = @{
                        tip = $nodeType
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
            if (-not $isDesktop -and -not $isTaskbar) { $currentZIndex += 10 }
        } catch {
            # Pencere okuma hatasi
        }
    }

    # PowerShell'in kendi ConvertTo-Json cmdlet'i ile (PSMethod sorununu by-pass eder)
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
