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

    # Masaustu (Desktop) ve Gorev Cubugu (Taskbar) gibi ozel sistem pencerelerini kacirmamak icin
    # Root element'in altindaki "TUM" (TrueCondition) elementleri top-level pencere kabul ediyoruz.
    $windowCondition = [System.Windows.Automation.Condition]::TrueCondition
    $topLevelWindowsCollection = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $windowCondition)
    
    # UIAutomation (RootElement.FindAll) uzak PsExec oturumlarinda Taskbar/Desktop gibi
    # temel Shell bilesenlerini filtreleyip GIZLEYEBILIR. 
    # Mukkemmel bir bypass icin Win32 API EnumWindows ile donanımsal tum elementleri toplayacagiz.
    $signature = @'
    using System;
    using System.Runtime.InteropServices;
    using System.Collections.Generic;

    public class Win32Helper {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        public static List<IntPtr> GetAllTopLevelWindows() {
            List<IntPtr> windows = new List<IntPtr>();
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (IsWindowVisible(hWnd)) {
                    windows.Add(hWnd);
                }
                return true;
            }, IntPtr.Zero);
            return windows;
        }
    }
'@
    Add-Type -TypeDefinition $signature -ReferencedAssemblies "System.Collections" | Out-Null
    
    $topLevelWindows = New-Object System.Collections.ArrayList
    
    # 1. STANDART YONTEM: UIAutomation Agaci (Guvenli olanlari alir)
    foreach ($win in $topLevelWindowsCollection) {
        [void]$topLevelWindows.Add($win)
    }
    
    # 2. HACK YONTEMI: Win32 HWND Agaci (Gizlenenleri/Taskbar/Desktop zorla alir)
    $allHwnds = [Win32Helper]::GetAllTopLevelWindows()
    foreach ($hwnd in $allHwnds) {
        try {
            $el = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
            if ($el -ne $null) {
                # UIAutomation zaten bulmussa (Duplicate) gormezden gel
                $isDuplicate = $false
                foreach ($existing in $topLevelWindows) {
                    if ($existing.Current.NativeWindowHandle -eq $el.Current.NativeWindowHandle) {
                        $isDuplicate = $true
                        break
                    }
                }
                if (-not $isDuplicate) {
                    [void]$topLevelWindows.Add($el)
                }
            }
        } catch {}
    }

    $allElementsOutput = @()
    $currentZIndex = 0

    $meaningfulTypes = @(
        "Button", "Edit", "Hyperlink", "MenuItem", "Text", "CheckBox",
        "ComboBox", "ListItem", "TabItem", "Document", "Image", "Pane",
        "TreeItem", "DataItem", "Custom", "Group", "SplitButton", 
        "StatusBar", "Tab", "Table", "TitleBar", "Window", "ToolBar",
        "MenuBar", "Menu", "List", "Thumb", "Separator"
    )

    foreach ($window in $topLevelWindows) {
        try {
            $wRect = Get-BoundingRect $window
            if ($wRect -eq $null -or $wRect.genislik -le 0 -or $wRect.yukseklik -le 0) { continue }
            
            $wName = $window.Current.Name
            $wClass = $window.Current.ClassName
            $parentName = if ([string]::IsNullOrWhiteSpace($wName)) { 
                if ($wClass -eq "Shell_TrayWnd") { "Windows Taskbar ($wClass)" }
                elseif ($wClass -eq "Progman" -or $wClass -eq "WorkerW") { "Windows Desktop ($wClass)" }
                else { "Bilinmeyen Pencere ($wClass)" }
            } else { $wName }
            $color = @( (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250) )
            $pBorder = @($wRect.x, $wRect.y, ($wRect.x + $wRect.genislik), ($wRect.y + $wRect.yukseklik))
            
            $windowGroup = @{
                pencere = $parentName
                z_index = $currentZIndex
                renk = $color
                kutu = $pBorder
                elmanlar = [System.Collections.ArrayList]::new()
            }
            
            # Elementleri toplamak icin agaci gezelim
            $treeWalker = [System.Windows.Automation.TreeWalker]::RawViewWalker
            
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
                    if ($cRect -eq $null -or $cRect.genislik -le 0 -or $cRect.yukseklik -le 0) { continue }
                    
                    $cType = Get-ControlTypeString $node.Current.ControlType.Id
                    $cName = $node.Current.Name
                    
                    $isMeaningful = $meaningfulTypes -contains $cType
                    if ([string]::IsNullOrWhiteSpace($cName) -and -not $isMeaningful) { continue }
                    
                    $isim = if ([string]::IsNullOrWhiteSpace($cName)) { "" } else { $cName.Trim() }
                    
                    $centerX = [math]::Round($cRect.x + ($cRect.genislik / 2))
                    $centerY = [math]::Round($cRect.y + ($cRect.yukseklik / 2))
                    
                    $elData = @{
                        tip = $cType
                        isim = $isim
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
