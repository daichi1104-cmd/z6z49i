"""Web アプリを起動する: python -m band2score.web

同じ Wi-Fi につないだスマホから、表示される URL（または QR コード）を開くと使えます。
"""

from __future__ import annotations

import argparse
import logging
import os
import socket


def lan_addresses() -> list[str]:
    """この PC の、同じネットワークの機器から見える IP アドレス。"""
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
    return found


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

    print("\nband2score を起動しました。スマホのブラウザで次の URL を開いてください（同じ Wi-Fi が必要です）:\n")
    urls = [f"http://{ip}:{a.port}" for ip in lan_addresses()] if a.host == "0.0.0.0" else []
    urls = urls or [f"http://{a.host}:{a.port}"]
    for url in urls:
        print(f"    {url}")
    try:
        import qrcode

        qr = qrcode.QRCode(border=1)
        qr.add_data(urls[0])
        print("\nスマホのカメラでこの QR コードを読み取っても開けます:\n")
        qr.print_ascii(invert=True)
    except ImportError:
        pass
    print("\nこの PC では http://localhost:%d でも開けます。終了するときは Ctrl+C。\n" % a.port)
    uvicorn.run(create_app(), host=a.host, port=a.port, log_level="warning")


if __name__ == "__main__":
    main()
