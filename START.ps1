param([switch]$Editor)
$moonRoot = $PSScriptRoot
$moonGodot = Join-Path $moonRoot 'tools\godot\Godot_v4.6.1-stable_win64.exe'
if (-not (Test-Path -LiteralPath $moonGodot)) {
    throw 'Brak lokalnego Godota. Otwórz godot/project.godot w Godot 4.6 lub nowszym.'
}
$env:APPDATA = Join-Path $moonRoot 'tools\godot\editor_data'
$env:LOCALAPPDATA = $env:APPDATA
$moonArguments = @('--path', ('"' + (Join-Path $moonRoot 'godot') + '"'))
if ($Editor) { $moonArguments += '--editor' }
Start-Process -FilePath $moonGodot -ArgumentList $moonArguments
