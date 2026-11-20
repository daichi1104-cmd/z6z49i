"""Web アプリを起動する: python -m band2score.web

同じ Wi-Fi につないだスマホから、表示される URL（または QR コード）を開くと使えます。
この PC とスマホに Tailscale を入れておくと、外出先からも使えます。
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import shutil
import socket
import subprocess


def lan_addresses() -> list[str]:
    """この PC の、同じネットワークの機器から見える IP アドレス（Tailscale のものは除く）。"""
    found = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))  # 実際には送信しない。経路からアドレスを知るだけ
        found.append(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in found and not ip.startswith("127."):
                found.append(ip)
    except OSError:
        pass
    return [ip for ip in found if not is_tailscale_ip(ip)]


def is_tailscale_ip(ip: str) -> bool:
    """Tailscale が使うアドレス（100.64.0.0/10）か。"""
    try:
        return ipaddress.ip_address(ip) in ipaddress.ip_network("100.64.0.0/10")
    except ValueError:
        return False


TAILSCALE_PATHS = [
    r"C:\Program Files\Tailscale\tailscale.exe",
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
]


def tailscale_address() -> str | None:
    """Tailscale につながっていれば、外出先のスマホから使えるこの PC の名前（または IP）を返す。"""
    exe = shutil.which("tailscale") or next((p for p in TAILSCALE_PATHS if os.path.exists(p)), None)
    if not exe:
        return None
    try:
        out = subprocess.run([exe, "status", "--json"], capture_output=True, text=True, timeout=5)
        status = json.loads(out.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    if status.get("BackendState") != "Running":
        return None
    me = status.get("Self") or {}
    name = (me.get("DNSName") or "").rstrip(".")
    if name and status.get("MagicDNSSuffix"):
        return name
    ips = [ip for ip in me.get("TailscaleIPs") or [] if "." in ip]
    return ips[0] if ips else None


def main() -> None:
    p = argparse.ArgumentParser(prog="band2score.web", description="band2score の Web アプリを起動します")
    p.add_argument("--host", default="0.0.0.0", help="待ち受けるアドレス（既定: 0.0.0.0 = 同じ Wi-Fi から使える）")
    p.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8000")))
    p.add_argument("--password", default=None, help="使うときに求めるパスワード（環境変数 BAND2SCORE_PASSWORD でも可）")
    a = p.parse_args()
    if a.password:
        os.environ["BAND2SCORE_PASSWORD"] = a.password

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    import uvicorn

    from .server import create_app

    lan = [f"http://{ip}:{a.port}" for ip in lan_addresses()] if a.host == "0.0.0.0" else []
    ts = tailscale_address() if a.host == "0.0.0.0" else None
    ts_url = f"http://{ts}:{a.port}" if ts else None

    print("\nband2score を起動しました。スマホのブラウザで次の URL を開いてください。\n")
    if ts_url:
        print("  ● どこからでも（スマホでも Tailscale をオンにしておく）:")
        print(f"      {ts_url}")
    if lan:
        print("  ● 家の中で（PC と同じ Wi-Fi のとき）:")
        for url in lan:
            print(f"      {url}")
    if not ts_url and not lan:
        print(f"      http://{a.host}:{a.port}")
    if not ts_url and a.host == "0.0.0.0":
        print("\n  （外出先からも使うには、この PC とスマホに Tailscale を入れて同じアカウントでログインしてください）")
    qr_url = ts_url or (lan[0] if lan else None)
    if qr_url:
        try:
            import qrcode

            qr = qrcode.QRCode(border=1)
            qr.add_data(qr_url)
            print(f"\nスマホのカメラでこの QR コードを読み取ると開けます（{qr_url}）:\n")
            qr.print_ascii(invert=True)
        except ImportError:
            pass
    print("\nこの PC では http://localhost:%d でも開けます。" % a.port)
    print("終了するときはこの画面を閉じるか Ctrl+C。PC がスリープすると使えなくなります。\n")
    uvicorn.run(create_app(), host=a.host, port=a.port, log_level="warning")


if __name__ == "__main__":
    main()
