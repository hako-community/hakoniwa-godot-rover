# =============================================================================
# ビルドした addon をプロジェクトへ入れる（project\addons\ は git 管理外の生成物）
#
#   powershell -ExecutionPolicy Bypass -File scripts\windows\install_addons.ps1
#
#   build\addon\addons\{hakoniwa, hakoniwa_msgs}                 → project\addons\
#   third_party\hakoniwa-godot\addons\hakoniwa_robot_sync（GDScript）→ project\addons\
#   codec_manifest.json は実際に建てた codec だけに絞る（無い型を読もうとして Godot がエラーを出すため）
# ★ third_party の中は読むだけ。
# =============================================================================
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$From = Join-Path $Root "build\addon\addons"
$To = Join-Path $Root "project\addons"
if (-not (Test-Path (Join-Path $From "hakoniwa\hakoniwa.gdextension"))) { throw "先に build_addon.ps1 を実行してください" }
New-Item -ItemType Directory -Force $To | Out-Null
foreach ($a in "hakoniwa", "hakoniwa_msgs") {
    $dst = Join-Path $To $a
    if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
    Copy-Item -Recurse (Join-Path $From $a) $dst
}
$rs = Join-Path $To "hakoniwa_robot_sync"
if (Test-Path $rs) { Remove-Item -Recurse -Force $rs }
Copy-Item -Recurse (Join-Path $Root "third_party\hakoniwa-godot\addons\hakoniwa_robot_sync") $rs

$manPath = Join-Path $To "hakoniwa\codec_manifest.json"
$man = Get-Content -Encoding UTF8 $manPath -Raw | ConvertFrom-Json
$exts = @(Get-ChildItem (Join-Path $To "hakoniwa\codecs") -Filter "*.gdextension" | Sort-Object Name |
          ForEach-Object { "res://addons/hakoniwa/codecs/$($_.Name)" })
$man.extensions = $exts
[System.IO.File]::WriteAllText($manPath, ($man | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[install] codecs: $($exts -join ', ')"
