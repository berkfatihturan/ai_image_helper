<#
.SYNOPSIS
  UIA scanner + Desktop/Taskbar + DESKTOP ICONS Unified (Kesin Cozum)
.NOTES
  Desktop ikonlarını görmek için script kullanıcı oturumunda (interactive) çalışmalı.
#>

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Web.Extensions

Start-Sleep -Milliseconds 200

try {
# --- USER32 (EnumWindows + FindWindowEx + GetClassName) ---
if (-not ('User32' -as [type])) {
  Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  using System.Text;

  public class User32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
  }
"@
}

function Get-NativeClassName ($hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return "" }
  $sb = New-Object System.Text.StringBuilder(256)
  $res = [User32]::GetClassName($hwnd, $sb, $sb.Capacity)
  if ($res -gt 0) { return $sb.ToString() }
  return ""
}

function Get-ControlTypeString ($controlTypeId) {
  $typeInfo = [System.Windows.Automation.ControlType]::LookupById($controlTypeId)
  if ($typeInfo) { return $typeInfo.ProgrammaticName.Replace("ControlType.", "") }
  return "Unknown"
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
  } catch { return $null }
}

function Get-PrimaryScreenRect {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  return @{ x=$b.X; y=$b.Y; genislik=$b.Width; yukseklik=$b.Height }
}

# 1) Progman veya WorkerW içinde SHELLDLL_DefView bul
# 2) Onun içinde SysListView32 ("FolderView") bul -> DESKTOP ICONS burada
function Get-DesktopListViewHwnd {
  $found = [IntPtr]::Zero

  $cb = [User32+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)

    $cls = Get-NativeClassName $hWnd
    if ($cls -ne "Progman" -and $cls -ne "WorkerW") { return $true }

    # SHELLDLL_DefView arıyoruz
    $defView = [User32]::FindWindowEx($hWnd, [IntPtr]::Zero, "SHELLDLL_DefView", $null)
    if ($defView -eq [IntPtr]::Zero) { return $true }

    # SysListView32 ("FolderView")
    $listView = [User32]::FindWindowEx($defView, [IntPtr]::Zero, "SysListView32", "FolderView")
    if ($listView -ne [IntPtr]::Zero) {
      $script:found = $listView
      return $false
    }
    return $true
  }

  [User32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $found
}

# Desktop ikonlarını UIA ile al
function Read-DesktopIcons {
  $hwndLV = Get-DesktopListViewHwnd
  if ($hwndLV -eq [IntPtr]::Zero) {
    return @{ ok=$false; reason="Desktop ListView (SysListView32/FolderView) bulunamadı. Büyük ihtimalle yanlış session/SYSTEM." ; icons=@() }
  }

  $ae = $null
  try { $ae = [System.Windows.Automation.AutomationElement]::FromHandle($hwndLV) } catch { $ae = $null }
  if ($ae -eq $null) {
    return @{ ok=$false; reason="AutomationElement.FromHandle(ListView) null döndü. Yanlış session olabilir."; icons=@() }
  }

  $trueCondition = [System.Windows.Automation.Condition]::TrueCondition

  # ListView içindeki item’lar çoğu sistemde ListItem gelir
  $items = @()
  try {
    $items = $ae.FindAll([System.Windows.Automation.TreeScope]::Descendants, $trueCondition)
  } catch { $items = @() }

  $out = New-Object System.Collections.ArrayList
  $count = 0

  foreach ($it in $items) {
    if ($count -ge 5000) { break }
    try {
      $ct = Get-ControlTypeString $it.Current.ControlType.Id
      if ($ct -ne "ListItem" -and $ct -ne "Text" -and $ct -ne "Item" -and $ct -ne "DataItem") { continue }

      $r = Get-BoundingRect $it
      if ($r -eq $null) { continue }
      if ($r.genislik -lt 4 -or $r.yukseklik -lt 4) { continue }

      $name = ""
      try {
        $rawName = $it.Current.Name
        if ($null -ne $rawName) { $name = $rawName.Trim() }
      } catch { }

      $centerX = [math]::Round($r.x + ($r.genislik/2))
      $centerY = [math]::Round($r.y + ($r.yukseklik/2))

      [void]$out.Add(@{
        tip = $ct
        isim = $name
        koordinat = $r
        merkez_koordinat = @{ x=$centerX; y=$centerY }
      })
      $count++
    } catch {}
  }

  return @{ ok=$true; hwnd=[int64]$hwndLV; icons=$out.ToArray() }
}

# ---------------- MAIN ----------------
  $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
  if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

  $allElementsOutput = @()

  # A) MASAUSTU (DESKTOP ICONS) ISLEMI (USER SCRIPT)
  $desktopRect = Get-PrimaryScreenRect
  $desktopIcons = Read-DesktopIcons
  
  $desktopOut = @{
    pencere = "Windows Desktop"
    z_index = 99990
    renk = @( (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250) )
    kutu = @($desktopRect.x, $desktopRect.y, ($desktopRect.x + $desktopRect.genislik), ($desktopRect.y + $desktopRect.yukseklik))
    desktop_listview = @{
      ok = $desktopIcons.ok
      hwnd = $desktopIcons.hwnd
      reason = $desktopIcons.reason
    }
    elmanlar = $desktopIcons.icons
  }
  $allElementsOutput += $desktopOut

  # B) TASKBAR & DIGER PENCERELER (UIA Root Taramasi)
  $rootElement = [System.Windows.Automation.AutomationElement]::RootElement
  if ($rootElement -ne $null) {
      $trueCondition = [System.Windows.Automation.Condition]::TrueCondition
      $topLevelWindows = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $trueCondition)
      
      $currentZIndex = 10
      $validChildTypes = @("Button", "CheckBox", "ComboBox", "Document", "Edit", "Hyperlink", "Image", "ListItem", "MenuItem", "RadioButton", "Slider", "Spinner", "TabItem", "Text", "TreeItem", "Thumb", "HeaderItem", "Pane", "Group", "Custom", "List")

      foreach ($window in $topLevelWindows) {
          try {
              if ($window.Current.IsOffscreen) { continue }
              
              $hwnd = [IntPtr]$window.Current.NativeWindowHandle
              $className = Get-NativeClassName $hwnd
              
              # masaustunu zaten ozel olarak (A)'da ekledik, bunlari atla
              if ($className -eq "Progman" -or $className -eq "WorkerW") { continue }
              
              $cTypeString = Get-ControlTypeString $window.Current.ControlType.Id
              
              # Eger Pane ise, sadece Taskbar'i al
              if ($cTypeString -eq "Pane") {
                  if ($className -ne "Shell_TrayWnd") { continue }
              } elseif ($cTypeString -ne "Window") {
                  continue
              }
              
              $wRect = Get-BoundingRect $window
              if ($wRect -eq $null) { continue }
              
              $parentName = if ([string]::IsNullOrWhiteSpace($window.Current.Name)) { "" } else { $window.Current.Name }
              $isTaskbar = ($className -eq "Shell_TrayWnd")
              $myZIndex = if ($isTaskbar) { 1 } else { $currentZIndex }
              
              if ($parentName -eq "") { 
                  $parentName = if ($isTaskbar) { "Windows Taskbar" } else { "Bilinmeyen Pencere" }
              }
              
              $windowGroup = @{
                  pencere = $parentName
                  z_index = $myZIndex
                  renk = @( (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250), (Get-Random -Minimum 50 -Maximum 250) )
                  kutu = @($wRect.x, $wRect.y, ($wRect.x + $wRect.genislik), ($wRect.y + $wRect.yukseklik))
                  elmanlar = [System.Collections.ArrayList]::new()
              }
              
              # Pencere altindakileri topla
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
                      if ($cName -eq "" -and ($nodeType -eq "Pane" -or $nodeType -eq "Group" -or $nodeType -eq "Custom" -or $nodeType -eq "List")) { continue }
                      
                      $centerX = [math]::Round($cRect.x + ($cRect.genislik / 2))
                      $centerY = [math]::Round($cRect.y + ($cRect.yukseklik / 2))
                      
                      [void]$windowGroup.elmanlar.Add(@{
                          tip = $nodeType
                          isim = $cName
                          koordinat = $cRect
                          merkez_koordinat = @{ x=$centerX; y=$centerY }
                      })
                      $elementCount++
                  } catch {}
              }
              
              $windowGroup.elmanlar = $windowGroup.elmanlar.ToArray()
              $allElementsOutput += $windowGroup
              if (-not $isTaskbar) { $currentZIndex += 10 }
              
          } catch {}
      }
  }

  $json = $allElementsOutput | ConvertTo-Json -Depth 10 -Compress
  [System.IO.File]::WriteAllText((Join-Path $outDir "ui_output_all.json"), $json, [System.Text.Encoding]::UTF8)

} catch {
  $outDir = if ($args.Count -gt 0) { $args[0] } else { "C:\Temp" }
  if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $errMsg = $_.Exception.Message + "`n" + $_.ScriptStackTrace
  [System.IO.File]::WriteAllText((Join-Path $outDir "psexec_error.log"), $errMsg, [System.Text.Encoding]::UTF8)
}