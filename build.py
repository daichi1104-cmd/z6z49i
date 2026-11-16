#!/usr/bin/env python3
"""原稿（chapters/*.md）から PDF を作る。

Markdown 内の ```lilypond {#ex1-1 caption="..."} ブロックを LilyPond で SVG に変換し、
図として差し込んでから Pandoc → HTML → WeasyPrint → PDF の順に組版する。
"""
import hashlib, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).parent
BUILD = ROOT / "build"
FIG = BUILD / "fig"
FIG.mkdir(parents=True, exist_ok=True)
COMMON = (ROOT / "styles/common.ily").read_text()

BLOCK = re.compile(r'```lilypond\s*\{#([\w-]+)\s+caption="([^"]*)"\}\n(.*?)```', re.S)

def render(name, body):
    src = COMMON + "\n" + body
    h = hashlib.sha1(src.encode()).hexdigest()[:10]
    ly = FIG / f"{name}-{h}.ly"
    svg = FIG / f"{name}-{h}.cropped.svg"
    if not svg.exists():
        ly.write_text(src)
        r = subprocess.run(["lilypond", "-dbackend=svg", "-dcrop", "-dno-point-and-click",
                            "-o", str(FIG / f"{name}-{h}"), str(ly)], capture_output=True, text=True)
        if r.returncode != 0 or not svg.exists():
            sys.exit(f"LilyPond error in {name}:\n{r.stderr}")
    return svg

def process(md):
    def sub(m):
        name, cap, body = m.groups()
        svg = render(name, body)
        return f"![{cap}]({svg.relative_to(BUILD)})"
    return BLOCK.sub(sub, md)

def main():
    chapters = sorted((ROOT / "chapters").glob("*.md"))
    md = "\n\n".join(process(p.read_text()) for p in chapters)
    (BUILD / "book.md").write_text(md)
    subprocess.run(["pandoc", "book.md", "-f", "markdown", "-t", "html5", "-s",
                    "--metadata", "pagetitle=6弦ベースのためのジャズ理論", "--metadata", "lang=ja",
                    "-c", "../styles/book.css", "-o", "book.html"], cwd=BUILD, check=True)
    from weasyprint import HTML
    HTML(BUILD / "book.html").write_pdf(BUILD / "book.pdf")
    print("built:", BUILD / "book.pdf")

if __name__ == "__main__":
    main()
