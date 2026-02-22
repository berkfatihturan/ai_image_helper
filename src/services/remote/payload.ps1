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
    
    # UIAutomation her zaman gizli shell komponentlerini gostermeyebiliyor. 
    # Win32 API pencerelerini zorla arayalim ve listeye manuel ekleyelim.
    $signature = @'
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindow(string strClassName, string strWindowName);
'@
    Add-Type -MemberDefinition $signature -Name "Win32FindWindow" -Namespace Win32Functions -PassThru | Out-Null
    
    $topLevelWindows = New-Object System.Collections.ArrayList
    
    # Gorev Cubugu (Taskbar) EN USTTE OLMALI (Z-Index = 0)
    $taskbarHandle = [Win32Functions.Win32FindWindow]::FindWindow("Shell_TrayWnd", $null)
    if ($taskbarHandle -ne [IntPtr]::Zero) {
        try {
            $taskbarElement = [System.Windows.Automation.AutomationElement]::FromHandle($taskbarHandle)
            if ($taskbarElement -ne $null) { [void]$topLevelWindows.Add($taskbarElement) }
        } catch {}
    }
    
    foreach ($win in $topLevelWindowsCollection) {
        # Zaten ekledigimiz ozel pencereleri tekrar eklememek icin
        $wClass = $win.Current.ClassName
        if ($wClass -eq "Shell_TrayWnd" -or $wClass -eq "Progman" -or $wClass -eq "WorkerW") { continue }
        [void]$topLevelWindows.Add($win)
    }
    
    # Masaustu Root HWND (Progman) EN ALTTA OLMALI (Z-Index = Son)
    $desktopHandle = [Win32Functions.Win32FindWindow]::FindWindow("Progman", $null)
    if ($desktopHandle -ne [IntPtr]::Zero) {
        try {
            $desktopElement = [System.Windows.Automation.AutomationElement]::FromHandle($desktopHandle)
            if ($desktopElement -ne $null) { [void]$topLevelWindows.Add($desktopElement) }
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
            
            # Elementleri toplamak icin native FindAll kullaniyoruz (Asiri hizli ve stabil)
            $controlCondition = [System.Windows.Automation.Condition]::TrueCondition
            $elements = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $controlCondition)
            
            $elementCount = 0
            $allNodes = @($window)
            if ($elements -ne $null) { foreach ($e in $elements) { $allNodes += $e } }
            
            foreach ($node in $allNodes) {
                if ($elementCount -ge 4000) { break }
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
