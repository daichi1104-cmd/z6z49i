#!/usr/bin/env python3
"""build/book.pdf から Kindle 用の固定レイアウト EPUB（build/book.epub）を作る。

各ページを JPEG 画像にし、1ページ＝1つの XHTML に1枚ずつ置く。
目次（nav と NCX）は、PDF のしおり（WeasyPrint が見出しから作る）から章（h1）と節（h2）を取る。
仕様は KINDLE.md を参照。先に python3 build.py と node tools/gen_cover.js を実行しておく。
"""
import datetime, html, pathlib, shutil, subprocess, sys, tempfile, uuid, zipfile
from pypdf import PdfReader

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
PDF, COVER, OUT = BUILD / "book.pdf", BUILD / "cover.jpg", BUILD / "book.epub"

META = {
    "title": "6弦ベースのためのジャズ理論",
    "creator": "〔仮〕著者名",
    "language": "ja",
    # 版を改めても同じ本として扱われるよう、識別子は固定する
    "identifier": "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "6string-bass-jazz-theory")),
}
PAGE_H = 2500          # ページ画像の高さ（px）。幅は A5 の縦横比から決まる
JPEG_Q = 88
SKIP_FRONT_H2 = True   # 「はじめに」の小見出しは目次に載せない


def outline(reader):
    """PDF のしおりを (深さ, ページ番号(1始まり), 見出し) のリストにする。"""
    items = []
    def walk(nodes, depth):
        for n in nodes:
            if isinstance(n, list):
                walk(n, depth + 1)
            else:
                items.append((depth, reader.get_destination_page_number(n) + 1, n.title))
    walk(reader.outline, 0)
    return items


def toc_entries(items):
    """章（深さ0）と節（深さ1）だけを、入れ子のリスト [(見出し, ページ, [子...])] にする。"""
    tree = []
    for depth, page, title in items:
        if depth == 0:
            tree.append((title, page, []))
        elif depth == 1 and tree:
            if SKIP_FRONT_H2 and tree[-1][0] == "はじめに":
                continue
            tree[-1][2].append((title, page, []))
    return tree


def render_pages(tmp, n):
    subprocess.run(["pdftoppm", "-jpeg", "-jpegopt", f"quality={JPEG_Q}", "-scale-to-y", str(PAGE_H),
                    "-scale-to-x", "-1", str(PDF), str(tmp / "p")], check=True)
    files = sorted(tmp.glob("p-*.jpg"))
    if len(files) != n:
        sys.exit(f"ページ画像の数が合いません：{len(files)} / {n}")
    return files


def xhtml(title, w, h, img, alt):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja" lang="ja">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width={w}, height={h}"/>
<title>{html.escape(title)}</title>
<style>html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden}}img{{display:block;width:{w}px;height:{h}px}}</style>
</head>
<body><img src="{img}" alt="{html.escape(alt)}"/></body>
</html>
'''


def page_file(p):
    return f"p{p:04d}.xhtml"


def nav_ol(tree):
    out = ["<ol>"]
    for title, page, kids in tree:
        out.append(f'<li><a href="{page_file(page)}">{html.escape(title)}</a>')
        if kids:
            out.append(nav_ol(kids))
        out.append("</li>")
    out.append("</ol>")
    return "\n".join(out)


def ncx_points(tree, counter):
    out = []
    for title, page, kids in tree:
        counter[0] += 1
        out.append(f'<navPoint id="np{counter[0]}" playOrder="{counter[0]}">'
                   f'<navLabel><text>{html.escape(title)}</text></navLabel>'
                   f'<content src="{page_file(page)}"/>')
        out.extend(ncx_points(kids, counter))
        out.append("</navPoint>")
    return out


def main():
    for f in (PDF, COVER):
        if not f.exists():
            sys.exit(f"{f.relative_to(ROOT)} がありません（README のビルド方法を参照）")
    reader = PdfReader(str(PDF))
    n = len(reader.pages)
    items = outline(reader)
    tree = toc_entries(items)
    toc_page = next(p for d, p, t in items if d == 0 and t == "目次")
    body_page = next(p for d, p, t in items if d == 0 and t.startswith("第1章"))
    tree.append(("奥付", n, []))

    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        imgs = render_pages(tmp, n)
        from PIL import Image
        w, h = Image.open(imgs[0]).size
        cw, ch = Image.open(COVER).size

        root = tmp / "epub"
        oebps = root / "OEBPS"
        (oebps / "img").mkdir(parents=True)
        (root / "META-INF").mkdir()
        (root / "META-INF" / "container.xml").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>\n')

        shutil.copy(COVER, oebps / "img" / "cover.jpg")
        (oebps / "cover.xhtml").write_text(xhtml("表紙", cw, ch, "img/cover.jpg", "表紙"))
        manifest = ['<item id="cover-img" href="img/cover.jpg" media-type="image/jpeg" properties="cover-image"/>',
                    '<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>']
        spine = ['<itemref idref="cover" linear="yes"/>']
        for i, img in enumerate(imgs, 1):
            shutil.copy(img, oebps / "img" / f"p{i:04d}.jpg")
            (oebps / page_file(i)).write_text(xhtml(f"{META['title']} {i}", w, h, f"img/p{i:04d}.jpg", f"ページ {i}"))
            manifest.append(f'<item id="i{i:04d}" href="img/p{i:04d}.jpg" media-type="image/jpeg"/>')
            manifest.append(f'<item id="p{i:04d}" href="{page_file(i)}" media-type="application/xhtml+xml"/>')
            spine.append(f'<itemref idref="p{i:04d}"/>')

        (oebps / "nav.xhtml").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ja" lang="ja">
<head><meta charset="UTF-8"/><title>目次</title></head>
<body>
<nav epub:type="toc" id="toc"><h1>目次</h1>
{nav_ol(tree)}
</nav>
<nav epub:type="landmarks" hidden=""><ol>
<li><a epub:type="cover" href="cover.xhtml">表紙</a></li>
<li><a epub:type="toc" href="{page_file(toc_page)}">目次</a></li>
<li><a epub:type="bodymatter" href="{page_file(body_page)}">本文</a></li>
</ol></nav>
</body>
</html>
''')
        manifest.append('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>')

        (oebps / "toc.ncx").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="ja">
<head><meta name="dtb:uid" content="{META['identifier']}"/></head>
<docTitle><text>{html.escape(META['title'])}</text></docTitle>
<navMap>
{chr(10).join(ncx_points(tree, [0]))}
</navMap>
</ncx>
''')
        manifest.append('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')

        modified = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        (oebps / "content.opf").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="ja">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">{META['identifier']}</dc:identifier>
<dc:title>{html.escape(META['title'])}</dc:title>
<dc:creator>{html.escape(META['creator'])}</dc:creator>
<dc:language>{META['language']}</dc:language>
<meta property="dcterms:modified">{modified}</meta>
<meta property="rendition:layout">pre-paginated</meta>
<meta property="rendition:orientation">portrait</meta>
<meta property="rendition:spread">none</meta>
<meta name="fixed-layout" content="true"/>
<meta name="original-resolution" content="{w}x{h}"/>
<meta name="orientation-lock" content="portrait"/>
<meta name="cover" content="cover-img"/>
</metadata>
<manifest>
{chr(10).join(manifest)}
</manifest>
<spine toc="ncx" page-progression-direction="ltr">
{chr(10).join(spine)}
</spine>
</package>
''')

        OUT.unlink(missing_ok=True)
        with zipfile.ZipFile(OUT, "w") as z:
            z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
            for f in sorted(root.rglob("*")):
                if f.is_file():
                    z.write(f, f.relative_to(root).as_posix(), compress_type=zipfile.ZIP_DEFLATED)
    size = OUT.stat().st_size / 1e6
    print(f"built: {OUT}（{n}ページ＋表紙、ページ画像 {w}×{h} px、{size:.1f} MB、目次 {len(tree)} 章）")


if __name__ == "__main__":
    main()
