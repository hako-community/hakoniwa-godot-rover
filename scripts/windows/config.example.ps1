# 各自の PC の場所の設定。config.local.ps1 にコピーして書き換える（config.local.ps1 は git 管理外）。
#   copy scripts\windows\config.example.ps1 scripts\windows\config.local.ps1

# vcpkg（Boost。rover 専用のローカル SDK。hakoniwa-mujoco-rover の tools/local_sdk/build_deps_sdk.py で建てる）
$VcpkgRoot = "D:\work_rover\devai_rover\sdk\windows-msvc-x64\vcpkg"
# nlohmann/json の置き場所（hakoniwa-mujoco-rover の submodule を使う）
$NlohmannJsonRoot = "D:\work_rover\rover\hakoniwa-mujoco-rover\third_party\nlohmann-json"
# Godot 4.7（mono 版でよい）
$GodotExe = "D:\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
# hakoniwa-mujoco-rover（GLB・コースの配置表・PDU 定義を読む）
$MujocoRoverRoot = "D:\work_rover\rover\hakoniwa-mujoco-rover"
