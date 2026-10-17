# =============================================================================
# hakoniwa-godot（C++ の GDExtension）を Windows 用にビルドする
#
#   powershell -ExecutionPolicy Bypass -File scripts\windows\build_addon.ps1 [-Clean]
#
# ★ hakoniwa-godot は他者のリポジトリ。third_party の中では何も書かない・ビルドしない。
#   hakoniwa-humanoid の build_godot_ext.ps1 と同じ手順:
#   1) third_party\hakoniwa-godot とその submodule を、コミット済みの HEAD だけ git archive で build\src\ へ書き出す
#   2) 書き出したコピーを configure（nlohmann-json は手元のもの、Boost は SDK の vcpkg）
#   3) 書き出したコピーの tools\build_all_codecs.ps1 でビルド（ローバは geometry_msgs・sensor_msgs が要る）
#   4) addon 一式を build\addon\ へ集め、manifest を書く（プロジェクトへ入れるのは install_addons.ps1）
# =============================================================================
param(
    [string]$Packages = "hako_msgs;std_msgs;builtin_interfaces;geometry_msgs;sensor_msgs",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$Clean
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
. (Join-Path $PSScriptRoot "config.local.ps1")
$GODOT_REPO = Join-Path $Root "third_party\hakoniwa-godot"
$SRC = Join-Path $Root "build\src\hakoniwa-godot"
$BUILD = Join-Path $Root "build\cmake"
$OUT = Join-Path $Root "build\addon"
$TOOLCHAIN = Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
if (-not (Test-Path $TOOLCHAIN)) { throw "vcpkg がありません: $TOOLCHAIN" }
if (-not (Test-Path (Join-Path $GODOT_REPO "third_party\godot-cpp\CMakeLists.txt"))) {
    throw "submodule 未取得：git -c core.longpaths=true -C third_party\hakoniwa-godot submodule update --init --recursive"
}
if ($Clean) { foreach ($d in $SRC, $BUILD, $OUT) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } } }
if (Test-Path $SRC) { throw "書き出し先が既にあります（-Clean で作り直す）: $SRC" }

# --- 1) git archive ---
$subs = @("", "third_party/godot-cpp", "third_party/hakoniwa-core-pro", "third_party/hakoniwa-core-pro/hakoniwa-core-cpp",
          "third_party/hakoniwa-core-pro/hakoniwa-pdu-registry", "third_party/hakoniwa-pdu-endpoint")
$commits = [ordered]@{}
$tmpTar = Join-Path $env:TEMP "hako_godot_rover_archive.tar"
foreach ($rel in $subs) {
    $repo = if ($rel) { Join-Path $GODOT_REPO $rel } else { $GODOT_REPO }
    $dest = if ($rel) { Join-Path $SRC $rel } else { $SRC }
    New-Item -ItemType Directory -Force $dest | Out-Null
    $c = (& git -C $repo rev-parse HEAD).Trim()
    & git -C $repo archive --format=tar -o $tmpTar HEAD
    if ($LASTEXITCODE -ne 0) { throw "git archive failed: $repo" }
    & "$env:SystemRoot\System32\tar.exe" -xf $tmpTar -C $dest   # Git の GNU tar は C: をホスト名と解釈するので Windows の tar
    if ($LASTEXITCODE -ne 0) { throw "tar failed: $dest" }
    $name = if ($rel) { $rel } else { "hakoniwa-godot" }
    $commits[$name] = $c
    Write-Host "[export] $name $c"
}
Remove-Item $tmpTar -ErrorAction SilentlyContinue

# --- 2) configure ---
$cfg = @("-S", $SRC, "-B", $BUILD, "-G", "Visual Studio 17 2022", "-A", "x64",
         "-DHAKONIWA_GODOT_CODEC_PACKAGES=$Packages", "-DHAKONIWA_GODOT_BUILD_TESTS=OFF",
         "-DHAKONIWA_GODOT_BUILD_EXAMPLES=OFF", "-DHAKONIWA_GODOT_MINIMAL_DEP_BUILD=ON",
         "-DCMAKE_TOOLCHAIN_FILE=$($TOOLCHAIN.Replace('\', '/'))", "-DVCPKG_TARGET_TRIPLET=x64-windows",
         "-DHAKO_LOCAL_NLOHMANN_JSON_ROOT=$($NlohmannJsonRoot.Replace('\', '/'))")
& cmake @cfg
if ($LASTEXITCODE -ne 0) { throw "configure failed" }

# --- 3) build（書き出したコピーの上流スクリプト）---
& (Join-Path $SRC "tools\build_all_codecs.ps1") -BuildDir $BUILD -Configuration $Configuration `
    -ToolchainFile $TOOLCHAIN -VcpkgTriplet "x64-windows" -Tests OFF -Packages $Packages
if ($LASTEXITCODE -ne 0) { throw "build_all_codecs.ps1 failed" }

# --- 4) addon を集める ---
New-Item -ItemType Directory -Force (Join-Path $OUT "addons") | Out-Null
foreach ($a in "hakoniwa", "hakoniwa_msgs") {
    $to = Join-Path $OUT "addons\$a"
    if (Test-Path $to) { Remove-Item -Recurse -Force $to }
    Copy-Item -Recurse (Join-Path $SRC "addons\$a") $to
}
$man = [ordered]@{ built = (Get-Date).ToString("s"); configuration = $Configuration; packages = $Packages; sources = $commits }
$man | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $OUT "godot_addon_manifest.json")
Write-Host "[done] addon -> $OUT"
