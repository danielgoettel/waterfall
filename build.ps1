# Rebuilds wallpaper\index.html from wallpaper\index-template.html by embedding
# three.js, so the finished page is a single file that works offline.
# Run this after editing the template.

$root = $PSScriptRoot
$three = Get-Content -Raw -Encoding UTF8 (Join-Path $root "wallpaper\vendor\three.min.js")
$tpl   = Get-Content -Raw -Encoding UTF8 (Join-Path $root "wallpaper\index-template.html")
$out   = $tpl.Replace('<!--THREE-->', "<script>`n$three`n</script>")
[System.IO.File]::WriteAllText((Join-Path $root "wallpaper\index.html"), $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Built wallpaper\index.html ($([int]($out.Length / 1KB)) KB)"
