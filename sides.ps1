# Petal side strips: slim chromeless browser windows of falling petals pinned to
# screen edges. Each strip is registered with Windows as an "app bar" (like the
# taskbar), so maximized windows stop at the strips instead of covering them.
# Drag a strip's inner edge to resize it: the reserved space and any maximized
# window next to it follow live, like the splitter between browser panes.
#
#   -Mode PerScreen      a left and a right strip on every monitor (default)
#   -Mode Outer          one strip on the far left of the leftmost monitor and one on the
#                        far right of the rightmost monitor, bracketing the whole desktop
#   -SideWidth N         strip width in pixels (default 280; Edge refuses much narrower)
#   -NoReserve           don't reserve space (maximized windows may cover the strips)
#   -Close               close all strips and release the reserved space
#
# The script keeps running (hidden) while the strips are open, holding the
# reservations and tracking resizes. It exits on its own when the strips close.

param(
  [ValidateSet('PerScreen', 'Outer')] [string]$Mode = 'PerScreen',
  [int]$SideWidth = 280,
  [int]$TitleBar = 31,       # height of the browser's app-window title bar at 100% scaling, hidden above the screen
  [switch]$NoReserve,
  [switch]$Close
)

$titlePrefix = 'Petal Waterfall'                      # the page's <title>, used to find its windows
$page        = Join-Path $PSScriptRoot "wallpaper\index.html"
$profileBase = Join-Path $env:LOCALAPPDATA "cherry-sides-profile"

# Prefer Edge, fall back to Chrome
$browser = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $browser)) { $browser = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" }

Add-Type @"
using System; using System.Runtime.InteropServices;
public class Native {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
    public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr BeginDeferWindowPos(int n);
  [DllImport("user32.dll")] public static extern IntPtr DeferWindowPos(IntPtr hdwp, IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool EndDeferWindowPos(IntPtr hdwp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, ref RECT rect);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromRect(ref RECT rc, uint flags);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  public static bool MouseDown() { return (GetAsyncKeyState(1) & 0x8000) != 0; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
    public uint length; public uint flags; public uint showCmd; public POINT minPos; public POINT maxPos; public RECT normalPos; }
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
  [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint a, uint p, ref RECT r, uint f);
  // Un-maximize a window in place: its normal-state rectangle is set to where it
  // is right now, so nothing visibly jumps. Returns once it is no longer maximized.
  public static void RestoreInPlace(IntPtr h) {
    uint on = 1;
    DwmSetWindowAttribute(h, DWMWA_TRANSITIONS_FORCEDISABLED, ref on, 4);
    RECT now = Visible(h);
    RECT wa = new RECT(); SystemParametersInfo(0x30, 0, ref wa, 0);   // normalPos is relative to the primary work area
    WINDOWPLACEMENT wp = new WINDOWPLACEMENT();
    wp.length = (uint)Marshal.SizeOf(typeof(WINDOWPLACEMENT));
    GetWindowPlacement(h, ref wp);
    wp.showCmd = 1;   // SW_SHOWNORMAL
    wp.normalPos.Left = now.Left - wa.Left; wp.normalPos.Top = now.Top - wa.Top;
    wp.normalPos.Right = now.Right - wa.Left; wp.normalPos.Bottom = now.Bottom - wa.Top;
    SetWindowPlacement(h, ref wp);
    for (int i = 0; i < 20 && IsZoomed(h); i++) System.Threading.Thread.Sleep(15);
  }
  // Re-maximize, checking that it took (a busy browser can drop the first request).
  public static void MaximizeChecked(IntPtr h) {
    for (int i = 0; i < 4 && !IsZoomed(h); i++) {
      ShowWindow(h, SW_MAXIMIZE);
      for (int j = 0; j < 20 && !IsZoomed(h); j++) System.Threading.Thread.Sleep(15);
      if (!IsZoomed(h)) { ShowWindow(h, SW_RESTORE); System.Threading.Thread.Sleep(60); }
    }
    uint off = 0;
    DwmSetWindowAttribute(h, DWMWA_TRANSITIONS_FORCEDISABLED, ref off, 4);
  }
  [DllImport("user32.dll")] public static extern uint RegisterWindowMessage(string s);
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hWnd, uint attr, ref uint value, uint size);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, uint attr, ref RECT value, uint size);
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder s, int n);
  public const uint DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_BORDER_COLOR = 34, DWMWA_COLOR_NONE = 0xFFFFFFFE;
  public const uint DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_DONOTROUND = 1, DWMWA_TRANSITIONS_FORCEDISABLED = 3;
  public const uint SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010;
  public const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3;
  public const uint ABE_LEFT = 0, ABE_RIGHT = 2;
  public const int SW_RESTORE = 9, SW_MAXIMIZE = 3;

  // All visible top-level windows whose title starts with the given text.
  public static System.Collections.Generic.List<IntPtr> FindByTitle(string prefix) {
    var found = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      var sb = new System.Text.StringBuilder(256);
      GetWindowText(h, sb, 256);
      if (sb.ToString().StartsWith(prefix)) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found;
  }
  // All visible maximized top-level windows on a monitor.
  public static System.Collections.Generic.List<IntPtr> MaximizedOn(IntPtr monitor) {
    var found = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h) && IsZoomed(h) && MonitorFromWindow(h, 2) == monitor) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found;
  }
  // Visible bounds (without the invisible resize border), falling back to the window rect.
  public static RECT Visible(IntPtr h) {
    RECT r = new RECT();
    if (DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, ref r, 16) != 0) GetWindowRect(h, ref r);
    return r;
  }
  // Re-maximize a window so it picks up the current work area, without the animation.
  public static void Refit(IntPtr h) {
    uint on = 1, off = 0;
    DwmSetWindowAttribute(h, DWMWA_TRANSITIONS_FORCEDISABLED, ref on, 4);
    ShowWindow(h, SW_RESTORE);
    ShowWindow(h, SW_MAXIMIZE);
    DwmSetWindowAttribute(h, DWMWA_TRANSITIONS_FORCEDISABLED, ref off, 4);
  }
}
"@
# Per-monitor DPI awareness: every coordinate is a physical pixel on every monitor.
if (-not [Native]::SetProcessDpiAwarenessContext([IntPtr]::op_Explicit(-4))) { [Native]::SetProcessDPIAware() | Out-Null }
Add-Type -AssemblyName System.Windows.Forms

function Close-Strips {
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like "*cherry-sides-profile*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# Window rectangle that makes the VISIBLE part of a strip cover its X, Y, W, H, with
# the browser's title bar pushed above Y. Uses the strip's measured margins.
function Strip-Rect($st) {
  $tb = [int][Math]::Round($TitleBar * [Native]::GetDpiForWindow($st.Hwnd) / 96)
  @{ X = $st.X - $st.DL; Y = $st.Y - $tb; W = $st.W + $st.DL + $st.DR; H = $st.H + $tb + $st.DB; TB = $tb }
}

# Place several strips at once (one batched move), then measure, learn each one's
# invisible resize margins, and repeat until every strip sits exactly where it should.
# Windows adds an invisible border on the left, right and bottom of every window,
# and the browser keeps adjusting its window for a moment after it appears.
function Place-Strips($list) {
  $list = @($list | Where-Object { $_.Hwnd -ne [IntPtr]::Zero -and [Native]::IsWindow($_.Hwnd) })
  if (-not $list) { return }
  for ($k = 0; $k -lt 15; $k++) {
    $hdwp = [Native]::BeginDeferWindowPos($list.Count)
    foreach ($st in $list) {
      $r = Strip-Rect $st
      $hdwp = [Native]::DeferWindowPos($hdwp, $st.Hwnd, [IntPtr]::Zero, $r.X, $r.Y, $r.W, $r.H, [Native]::SWP_NOZORDER -bor [Native]::SWP_NOACTIVATE)
    }
    [Native]::EndDeferWindowPos($hdwp) | Out-Null
    Start-Sleep -Milliseconds 150
    $ok = $true
    foreach ($st in $list) {
      $r = Strip-Rect $st
      $rc = New-Object Native+RECT
      [Native]::GetWindowRect($st.Hwnd, [ref]$rc) | Out-Null
      $vis = [Native]::Visible($st.Hwnd)
      if ($vis.Left -eq $st.X -and $vis.Right -eq $st.X + $st.W -and $vis.Bottom -eq $st.Y + $st.H -and $rc.Top -eq $r.Y) {
        $st.VisTop = $vis.Top; continue
      }
      $ok = $false
      $st.DL = $vis.Left - $rc.Left; $st.DR = $rc.Right - $vis.Right; $st.DB = $rc.Bottom - $vis.Bottom
    }
    if ($ok) { return }
  }
}

# Reserve (or re-reserve) an edge of a monitor for a strip.
function Set-Bar($st) {
  $d = $st.Bar.Data
  $rc = New-Object Native+RECT
  $rc.Left = $st.X; $rc.Top = $st.Y; $rc.Right = $st.X + $st.W; $rc.Bottom = $st.Y + $st.H
  $d.rc = $rc
  [Native]::SHAppBarMessage([Native]::ABM_QUERYPOS, [ref]$d) | Out-Null
  [Native]::SHAppBarMessage([Native]::ABM_SETPOS, [ref]$d) | Out-Null
  $st.Bar.Data = $d
}

# Maximized windows keep their old size until re-maximized, so nudge the ones on
# the strip's monitor (never the strips themselves).
function Refit-Maximized($st) {
  foreach ($mw in [Native]::MaximizedOn($st.Monitor)) {
    if ($strips | Where-Object { $_.Hwnd -eq $mw }) { continue }
    [Native]::Refit($mw)
  }
}
function Refit-All {
  $done = @{}
  foreach ($st in $strips) { if (-not $done[$st.Monitor]) { $done[$st.Monitor] = $true; Refit-Maximized $st } }
}

Close-Strips                      # a previous resident instance notices and releases its app bars
if ($Close) { exit }
Start-Sleep -Seconds 2

$screens = [System.Windows.Forms.Screen]::AllScreens
$url = "file:///" + ($page -replace '\\', '/')

# One entry per strip: which screen, which edge, and the current width.
$strips = @()
if ($Mode -eq 'PerScreen') {
  foreach ($s in $screens) {
    $strips += @{ Screen = $s; Edge = [Native]::ABE_LEFT;  W = $SideWidth }
    $strips += @{ Screen = $s; Edge = [Native]::ABE_RIGHT; W = $SideWidth }
  }
} else {
  $leftmost  = $screens | Sort-Object { $_.Bounds.Left }  | Select-Object -First 1
  $rightmost = $screens | Sort-Object { $_.Bounds.Right } | Select-Object -Last 1
  $strips += @{ Screen = $leftmost;  Edge = [Native]::ABE_LEFT;  W = $SideWidth }
  $strips += @{ Screen = $rightmost; Edge = [Native]::ABE_RIGHT; W = $SideWidth }
}
foreach ($st in $strips) {
  $wa = $st.Screen.WorkingArea
  $st.Y = $wa.Top; $st.H = $wa.Height
  $st.X = if ($st.Edge -eq [Native]::ABE_LEFT) { $wa.Left } else { $wa.Right - $st.W }
  $st.DL = 0; $st.DR = 0; $st.DB = 0; $st.Hwnd = [IntPtr]::Zero
  $rc = New-Object Native+RECT
  $rc.Left = $wa.Left; $rc.Top = $wa.Top; $rc.Right = $wa.Right; $rc.Bottom = $wa.Bottom
  $st.Monitor = [Native]::MonitorFromRect([ref]$rc, 2)
}

# Launch the strips in ONE browser profile so they share settings (the page syncs
# its settings panel across windows through the profile's storage). The first
# launch starts the browser; once its window exists the rest are launched together
# and handed to the running browser, then all windows are placed in one batch.
$launchArgs = { param($st) @("--user-data-dir=$profileBase", "--no-first-run", "--no-default-browser-check",
                              "--app=$url", "--window-position=$($st.X),$($st.Y)", "--window-size=$($st.W),$($st.H)") }
function Wait-Windows([int]$count, $known) {
  $found = @()
  for ($i = 0; $i -lt 150 -and $found.Count -lt $count; $i++) {
    Start-Sleep -Milliseconds 100
    $found = @([Native]::FindByTitle($titlePrefix) | Where-Object { $known -notcontains $_ })
  }
  return $found
}
$known = [Native]::FindByTitle($titlePrefix)
Start-Process $browser -ArgumentList (& $launchArgs $strips[0])
$first = Wait-Windows 1 $known
$known += $first
for ($i = 1; $i -lt $strips.Count; $i++) { Start-Process $browser -ArgumentList (& $launchArgs $strips[$i]) }
$rest = Wait-Windows ($strips.Count - 1) $known
$handles = @($first) + @($rest)
for ($i = 0; $i -lt $strips.Count -and $i -lt $handles.Count; $i++) {
  $h = $handles[$i]
  $strips[$i].Hwnd = $h
  # No border, square corners (Windows 11 draws both around every window).
  $v = [Native]::DWMWA_COLOR_NONE
  [Native]::DwmSetWindowAttribute($h, [Native]::DWMWA_BORDER_COLOR, [ref]$v, 4) | Out-Null
  $v = [Native]::DWMWCP_DONOTROUND
  [Native]::DwmSetWindowAttribute($h, [Native]::DWMWA_WINDOW_CORNER_PREFERENCE, [ref]$v, 4) | Out-Null
}

# Reserve each strip's space by registering the strip window ITSELF as an app bar.
# Windows shoves ordinary windows out of newly reserved space, but never an app
# bar's own window, so the strips can be resized live without being pushed around.
if (-not $NoReserve) {
  $msg = [Native]::RegisterWindowMessage("CherryPetalsAppBar")
  foreach ($st in $strips) {
    if ($st.Hwnd -eq [IntPtr]::Zero) { continue }
    $d = New-Object Native+APPBARDATA
    $d.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($d)
    $d.hWnd = $st.Hwnd
    $d.uCallbackMessage = $msg
    $d.uEdge = $st.Edge
    [Native]::SHAppBarMessage([Native]::ABM_NEW, [ref]$d) | Out-Null
    $st.Bar = @{ Data = $d }
    Set-Bar $st
  }
}
Place-Strips $strips
Refit-All

if ($NoReserve) { exit }

# Stay resident while any strip is open. Watch for the user resizing a strip by
# its inner edge (or dragging it). While the drag is in progress, the reservation
# and the maximized windows next to it follow live; when it ends, the strip is
# pinned back to the screen edge with its title bar hidden again.
# The reservation itself cannot change mid-drag: Edge pulls its window inside the
# work area whenever that changes, which would yank the strip out of the user's
# hand. So during a drag the neighbouring maximized windows are un-maximized and
# driven directly to the moving edge (smooth), and on release the reservation is
# updated once, the strip is pinned, and the neighbours are re-maximized.
function Other-Width($st, $edge) {
  $o = $strips | Where-Object { $_.Monitor -eq $st.Monitor -and $_.Edge -eq $edge } | Select-Object -First 1
  if ($o) { $o.W } else { 0 }
}
try {
  Start-Sleep -Seconds 2
  while ([Native]::FindByTitle($titlePrefix).Count -gt 0) {
    Start-Sleep -Milliseconds 30
    foreach ($st in $strips) {
      if ($st.Hwnd -eq [IntPtr]::Zero -or -not [Native]::IsWindow($st.Hwnd)) { continue }
      $vis = [Native]::Visible($st.Hwnd)
      $seenW = $vis.Right - $vis.Left
      $moved = ($st.Edge -eq [Native]::ABE_LEFT -and $vis.Left -ne $st.X) -or
               ($st.Edge -eq [Native]::ABE_RIGHT -and $vis.Right -ne $st.X + $st.W) -or
               ($vis.Top -ne $st.VisTop)
      if ($seenW -eq $st.W -and -not $moved -and -not $st.Dragging) { $st.Still = 0; continue }

      $wa = $st.Screen.WorkingArea
      $liveW = [Math]::Max(120, [Math]::Min($seenW, [int]($wa.Width * 0.45)))
      $key = "$seenW,$($vis.Left),$($vis.Top)"
      if ($st.LastKey -eq $key) { $st.Still++ } else { $st.Still = 0 }
      $st.LastKey = $key

      if ($liveW -ne $st.W -and -not $st.Dragging) {
        # Drag started: take the maximized neighbours out of maximized state so
        # they can be moved, remembering each one's invisible margins.
        $st.Dragging = $true
        $st.Followers = @()
        foreach ($mw in [Native]::MaximizedOn($st.Monitor)) {
          if ($strips | Where-Object { $_.Hwnd -eq $mw }) { continue }
          [Native]::RestoreInPlace($mw)
          $rc = New-Object Native+RECT; [Native]::GetWindowRect($mw, [ref]$rc) | Out-Null
          $v = [Native]::Visible($mw)
          $st.Followers += @{ Hwnd = $mw; DL = $v.Left - $rc.Left; DT = $v.Top - $rc.Top; DR = $rc.Right - $v.Right; DB = $rc.Bottom - $v.Bottom }
        }
      }

      if ($st.Dragging) {
        # Neighbours fill the space between this strip's live edge and the other strip.
        $leftW  = if ($st.Edge -eq [Native]::ABE_LEFT)  { $liveW } else { Other-Width $st ([Native]::ABE_LEFT) }
        $rightW = if ($st.Edge -eq [Native]::ABE_RIGHT) { $liveW } else { Other-Width $st ([Native]::ABE_RIGHT) }
        $x0 = $wa.Left + $leftW; $x1 = $wa.Right - $rightW
        $hdwp = [Native]::BeginDeferWindowPos($st.Followers.Count)
        foreach ($f in $st.Followers) {
          if (-not [Native]::IsWindow($f.Hwnd)) { continue }
          $hdwp = [Native]::DeferWindowPos($hdwp, $f.Hwnd, [IntPtr]::Zero, $x0 - $f.DL, $wa.Top - $f.DT,
                    ($x1 - $x0) + $f.DL + $f.DR, $wa.Height + $f.DT + $f.DB, [Native]::SWP_NOZORDER -bor [Native]::SWP_NOACTIVATE)
        }
        [Native]::EndDeferWindowPos($hdwp) | Out-Null
      }

      if ($st.Still -ge 3 -and -not [Native]::MouseDown()) {
        # Mouse button up and the window held still: the user let go. Commit the new width.
        $st.Still = 0
        $st.W = $liveW
        $st.X = if ($st.Edge -eq [Native]::ABE_LEFT) { $wa.Left } else { $wa.Right - $st.W }
        if ($st.Bar) { Set-Bar $st }
        Place-Strips @($st)
        if ($st.Dragging) {
          foreach ($f in $st.Followers) {
            if ([Native]::IsWindow($f.Hwnd)) { [Native]::MaximizeChecked($f.Hwnd) }
          }
          $st.Followers = @()
          $st.Dragging = $false
        }
      }
    }
  }
} finally {
  foreach ($st in $strips) {
    if (-not $st.Bar -or -not [Native]::IsWindow($st.Hwnd)) { continue }   # a closed window's bar is gone already
    $d = $st.Bar.Data
    [Native]::SHAppBarMessage([Native]::ABM_REMOVE, [ref]$d) | Out-Null
  }
  Refit-All
}
