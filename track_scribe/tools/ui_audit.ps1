# Track-scribe UI layout audit -- parses a `uiautomator dump` and reports the
# violations WE wrote down, in text, with no screenshot (FLAG_SECURE blackens
# our images on this device anyway). Behaviour ported from trailmark's
# tools/ui_audit.ps1 (docs/BORROW-FROM-TRAILMARK.md, borrow 1b); the rule set is ours.
#
#   powershell -File tools/ui_audit.ps1 <dump.xml> [-Density 2] [-NavBarTop 1516] [-ShowNodes]
#
# Capture a dump first:
#   adb shell uiautomator dump --windows /sdcard/d.xml && adb pull /sdcard/d.xml d.xml
# Flutter emits no `text`/`content-desc` until an accessibility service is bound
# (Select to Speak), and `--windows` is what makes the nav-bar and IME bands visible.
#
# Defaults are the Realme RMX3910 measured in the 2026-10-16 round: 720x1604 px at
# 320 dpi (density 2.0) and a nav bar whose top edge sits at y=1516.
#
# TWO PITFALLS THIS FILE IS WRITTEN AROUND.
# (1) PowerShell variable names are CASE-INSENSITIVE. The first draft read the
#     screen width as `$W` and then assigned `$w` inside a loop, so each rule
#     compared against the previous node's width instead of the screen: nothing
#     fired, and the out-of-bounds rule fired on every node. No name is reused
#     across scopes here.
# (2) Windows PowerShell 5.1 decodes a .ps1 as ANSI unless it carries a UTF-8
#     BOM, which silently corrupts every non-ASCII character in the SOURCE -- a
#     literal ellipsis in a pattern never matched the real one. So this file is
#     pure ASCII and takes the ellipsis from its code point. Arabic comes from
#     the dump at runtime, where UTF-8 is read correctly.
param(
  [Parameter(Mandatory = $true)][string]$XmlPath,
  [double]$Density = 2.0,
  [int]$NavBarTop = 1516,
  [switch]$ShowNodes
)

# Without these lines the Arabic labels -- the whole point of auditing our
# screens -- print as `?????` on a Windows console.
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$LDOTS = [string][char]0x2026   # the horizontal-ellipsis glyph Flutter truncates with

$xml = Get-Content -Raw -Encoding UTF8 $XmlPath
$nodes = @()
foreach ($match in [regex]::Matches($xml, '<node[^>]*>')) {
  $nodeXml = $match.Value
  $bounds = [regex]::Match($nodeXml, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  if (-not $bounds.Success) { continue }
  $nodes += [pscustomobject]@{
    x1        = [int]$bounds.Groups[1].Value
    y1        = [int]$bounds.Groups[2].Value
    x2        = [int]$bounds.Groups[3].Value
    y2        = [int]$bounds.Groups[4].Value
    text      = [regex]::Match($nodeXml, 'text="([^"]*)"').Groups[1].Value
    desc      = [regex]::Match($nodeXml, 'content-desc="([^"]*)"').Groups[1].Value
    cls       = [regex]::Match($nodeXml, 'class="([^"]*)"').Groups[1].Value
    clickable = [regex]::Match($nodeXml, 'clickable="([^"]*)"').Groups[1].Value -eq 'true'
  }
}
if ($nodes.Count -eq 0) { Write-Output 'no nodes parsed'; exit 1 }

# The first node is the window root on every dump measured so far; screen size
# comes from it, not from `wm size`, so a rotation or a split-screen dump is
# audited against the bounds it was actually taken in.
$scrW = $nodes[0].x2
$scrH = $nodes[0].y2
Write-Output ("SCREEN {0}x{1}px  (density {2} -> {3}x{4}dp)  nodes={5}" -f `
    $scrW, $scrH, $Density, [int]($scrW / $Density), [int]($scrH / $Density), $nodes.Count)

$issues = 0
$labeled = @($nodes | Where-Object { $_.text -ne '' -or $_.desc -ne '' })

if ($ShowNodes) {
  Write-Output '--- labeled nodes (dp) ---'
  foreach ($n in $labeled) {
    Write-Output ("  [{0},{1}][{2},{3}]dp  '{4}'  {5}" -f `
        [int]($n.x1 / $Density), [int]($n.y1 / $Density), [int]($n.x2 / $Density), [int]($n.y2 / $Density), `
        ($n.text + $n.desc), $n.cls)
  }
}

# 1) Touch targets. Our floor is 48 dp (the spec's own rule, and why
# test/ui/overlay_bounds_test.dart exists); trailmark used 44. A full-width band
# is not a target, so a clickable node spanning the screen -- the map, the stop
# control's row -- is skipped.
$minPx = 48 * $Density
foreach ($n in $nodes) {
  if (-not $n.clickable) { continue }
  $nW = $n.x2 - $n.x1
  $nH = $n.y2 - $n.y1
  if ($nW -ge ($scrW - 4)) { continue }
  if ($nW -lt $minPx -or $nH -lt $minPx) {
    Write-Output ("SMALL-TARGET: {0}x{1}dp at {2},{3} '{4}'" -f `
        [int]($nW / $Density), [int]($nH / $Density), [int]($n.x1 / $Density), [int]($n.y1 / $Density), ($n.desc + $n.text))
    $issues++
  }
}

# 2) Anything a user can read or press must stay inside the window.
foreach ($n in $labeled) {
  if ($n.x1 -lt 0 -or $n.y1 -lt 0 -or $n.x2 -gt $scrW -or $n.y2 -gt $scrH) {
    Write-Output ("OUT-OF-BOUNDS: [{0},{1}][{2},{3}] '{4}'" -f `
        $n.x1, $n.y1, $n.x2, $n.y2, ($n.text + $n.desc))
    $issues++
  }
}

# 3) The nav bar band is dead space on ColorOS: ftap.sh refuses to tap below
# y=1516, so a control that lives there is a control nobody can press.
# Pass -NavBarTop 0 on a device measured with a different bar.
if ($NavBarTop -gt 0) {
  foreach ($n in $nodes) {
    if (-not ($n.clickable -or ($n.text -ne '') -or ($n.desc -ne ''))) { continue }
    if ($n.y2 -le $NavBarTop) { continue }
    if ($n.y1 -ge $scrH) { continue }
    Write-Output ("NAV-BAR-INTRUSION: y {0}-{1}px '{2}' (bar top {3})" -f `
        $n.y1, $n.y2, ($n.text + $n.desc), $NavBarTop)
    $issues++
  }
}

# 4) Two overlays that both carry a label and overlap are colliding -- the exact
# failure mode that made the recording screen's chips/banner pair bottom-anchor
# instead of sharing the top corners. Nesting is not collision: a labelled
# container (the map band, the stat panel) fully holds its own children, so a
# pair where one box contains the other is the widget tree, not an overlap.
for ($i = 0; $i -lt $labeled.Count; $i++) {
  for ($j = $i + 1; $j -lt $labeled.Count; $j++) {
    $a = $labeled[$i]
    $b = $labeled[$j]
    $aInsideB = ($b.x1 -le $a.x1 -and $b.y1 -le $a.y1 -and $b.x2 -ge $a.x2 -and $b.y2 -ge $a.y2)
    $bInsideA = ($a.x1 -le $b.x1 -and $a.y1 -le $b.y1 -and $a.x2 -ge $b.x2 -and $a.y2 -ge $b.y2)
    if ($aInsideB -or $bInsideA) { continue }
    $ovW = [Math]::Min($a.x2, $b.x2) - [Math]::Max($a.x1, $b.x1)
    $ovH = [Math]::Min($a.y2, $b.y2) - [Math]::Max($a.y1, $b.y1)
    if ($ovW -gt 2 -and $ovH -gt 2) {
      Write-Output ("OVERLAP: '{0}' x '{1}' area={2}x{3}px" -f ($a.text + $a.desc), ($b.text + $b.desc), $ovW, $ovH)
      $issues++
    }
  }
}

# 5) Truncation. An ellipsis is Flutter saying the Arabic string did not fit --
# invisible in a black FLAG_SECURE screenshot and obvious here. It is the
# device-side twin of the 97 dp overflow that test/ui/recording_screen_test.dart
# now pins at 1.5x and 2.0x text scale.
foreach ($n in $labeled) {
  foreach ($s in @($n.text, $n.desc)) {
    if ($s.EndsWith($LDOTS) -or $s.EndsWith('...')) {
      Write-Output ("CLIPPED-TEXT: '{0}' at {1},{2}-{3},{4}px" -f $s, $n.x1, $n.y1, $n.x2, $n.y2)
      $issues++
    }
  }
}

# 6) Informational: the 60/40 band split the owner ordered on 2026-10-16 is the
# one layout number decided by hand, so print the widest full-width bands
# instead of leaving the ratio to be eyeballed out of the node dump.
$bands = @($nodes | Where-Object { $_.x1 -le 2 -and $_.x2 -ge ($scrW - 2) } |
  Sort-Object { ($_.y2 - $_.y1) } -Descending | Select-Object -First 4)
Write-Output '--- widest full-width bands (px height, % of screen) ---'
foreach ($b in $bands) {
  $bH = $b.y2 - $b.y1
  if ($bH -eq $scrH) { continue }
  Write-Output ("  {0}px = {1:N1}%  [{2},{3}][{4},{5}]" -f $bH, (100.0 * $bH / $scrH), $b.x1, $b.y1, $b.x2, $b.y2)
}

Write-Output "TOTAL ISSUES: $issues"
if ($issues -gt 0) { exit 1 }
