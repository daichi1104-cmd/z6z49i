# band2score の Web アプリを起動する。start.bat から呼ばれる。
# 外部コマンドの警告で止まらないよう、失敗は終了コード（$LASTEXITCODE）で判断する
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$venvPy = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Write-Host "まだ準備ができていません。先に setup.bat をダブルクリックしてください。" -ForegroundColor Red
    exit 1
}

# ffmpeg などを見つけられるように PATH を最新にする
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
$env:BAND2SCORE_DATA = Join-Path $root "web_data"

# 起動している間は PC がスリープしないようにする（この画面を閉じると元に戻る）
Add-Type -Namespace B2S -Name Power -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
"@
[void][B2S.Power]::SetThreadExecutionState([uint32]2147483649)  # 0x80000001 = ES_CONTINUOUS | ES_SYSTEM_REQUIRED
Write-Host "（起動している間、この PC はスリープしません。画面は消えても大丈夫です）" -ForegroundColor DarkGray

& $venvPy -m band2score.web @args
