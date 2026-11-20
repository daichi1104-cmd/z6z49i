# band2score を Windows で使えるように準備する（最初に 1回だけ）。setup.bat から呼ばれる。
# Python 3.11・ffmpeg・必要なライブラリ・音源分離の AI モデルを入れる。
# 外部コマンドの警告で止まらないよう、失敗は終了コード（$LASTEXITCODE）で判断する
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Say($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""
    Write-Host "うまくいきませんでした: $msg" -ForegroundColor Red
    Write-Host "この画面の写真（スクリーンショット）を送ってもらえれば原因を調べます。"
    exit 1
}
function HasWinget { return [bool](Get-Command winget -ErrorAction SilentlyContinue) }
function RefreshPath {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
}

function FindPython311 {
    $candidates = @("$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
                    "C:\Program Files\Python311\python.exe")
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $p = (& py -3.11 -c "import sys; print(sys.executable)" 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $p -and (Test-Path $p.Trim())) { return $p.Trim() }
    }
    return $null
}

Write-Host "band2score の準備を始めます。10〜30分ほどかかります（ネットの速さによります）。" -ForegroundColor Green
Write-Host "途中で「このアプリがデバイスに変更を加えることを許可しますか？」と出たら「はい」を押してください。"

# 1. Python 3.11
Say "1/5 Python 3.11 を確認しています"
$py = FindPython311
if (-not $py) {
    if (-not (HasWinget)) { Fail "Python 3.11 が見つかりません。https://www.python.org/downloads/ から Python 3.11 を入れてから、もう一度 setup.bat を実行してください。" }
    Write-Host "Python 3.11 を入れています…"
    winget install -e --id Python.Python.3.11 --scope user --accept-package-agreements --accept-source-agreements
    RefreshPath
    $py = FindPython311
    if (-not $py) { Fail "Python 3.11 を入れられませんでした。" }
}
Write-Host "Python: $py"

# 2. ffmpeg（スマホの録音 m4a などを読むのに使う）
Say "2/5 ffmpeg を確認しています"
RefreshPath
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    if (-not (HasWinget)) { Fail "ffmpeg が見つかりません。https://www.gyan.dev/ffmpeg/builds/ から入れてください。" }
    Write-Host "ffmpeg を入れています…"
    winget install -e --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements
    RefreshPath
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Fail "ffmpeg を入れられませんでした。" }
}
Write-Host "ffmpeg: OK"

# 3. 仮想環境とライブラリ
Say "3/5 必要なライブラリを入れています（いちばん時間がかかります）"
$venvPy = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    & $py -m venv (Join-Path $root ".venv")
    if ($LASTEXITCODE -ne 0) { Fail "Python の仮想環境を作れませんでした。" }
}
& $venvPy -m pip install --upgrade pip
& $venvPy -m pip install torch torchaudio
if ($LASTEXITCODE -ne 0) { Fail "PyTorch を入れられませんでした。" }
& $venvPy -m pip install -r (Join-Path $root "requirements.txt")
if ($LASTEXITCODE -ne 0) { Fail "ライブラリを入れられませんでした。" }
& $venvPy -m pip install --no-deps basic-pitch
if ($LASTEXITCODE -ne 0) { Fail "basic-pitch を入れられませんでした。" }

# 4. AI モデルを先にダウンロード（最初の変換を待たせないため）
Say "4/5 音源分離の AI モデルをダウンロードしています"
& $venvPy -c "from demucs.pretrained import get_model; get_model('htdemucs_6s'); print('OK')"
if ($LASTEXITCODE -ne 0) { Fail "AI モデルをダウンロードできませんでした。" }

# 5. ファイアウォール（同じ Wi-Fi と Tailscale のスマホからだけ、ポート 8000 につなげるようにする）
Say "5/5 スマホからつなげるように設定しています"
$rule = "band2score (port 8000)"
$exists = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
if (-not $exists) {
    $cmd = "New-NetFirewallRule -DisplayName '$rule' -Direction Inbound -Protocol TCP -LocalPort 8000 " +
           "-RemoteAddress LocalSubnet,100.64.0.0/10 -Action Allow -Profile Any"
    try {
        Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile", "-Command", $cmd
    } catch {
        Write-Host "設定をスキップしました。あとで start.bat を初めて動かしたときに「アクセスを許可する」を押してください。" -ForegroundColor Yellow
    }
}

Say "使う部品を読み込めるか確かめています"
& $venvPy -m band2score.check
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host ""
Write-Host "準備ができました！" -ForegroundColor Green
Write-Host "次からは同じフォルダの start.bat をダブルクリックすると起動します。"
