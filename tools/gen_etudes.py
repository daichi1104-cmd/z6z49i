#!/usr/bin/env python3
"""第9章の練習曲を生成する。

音は実音で書く（例: "Eb2", "F#1/8", "r/2"）。弦は手の位置（人差し指のフレット p から
5フレット分の範囲）から自動で決める。"C1@6" のように @ で弦を直接指定してもよい。
生成時に、手の位置の範囲外の音・同時に鳴る音の弦の重なり・押さえる幅を検査する。
出力: chapters/09-etudes.md
"""
import pathlib, re, sys
from fractions import Fraction as F

OPEN = {6: 23, 5: 28, 4: 33, 3: 38, 2: 43, 1: 48}           # 開放弦の実音（MIDI）
STEP = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
LY_ACC = {'': '', '#': 'is', 'b': 'es'}
errors = []

def parse(tok, p, where):
    m = re.fullmatch(r"([A-Gr])([#b]?)(\d?)(?:@(\d))?(?:/(\d+\.?))?(~?)", tok)
    if not m:
        sys.exit(f"bad token {tok} at {where}")
    n, acc, octv, s, dur, tie = m.groups()
    dur = dur or "4"
    length = F(4, int(dur.rstrip('.'))) * (F(3, 2) if dur.endswith('.') else 1)
    if n == 'r':
        return dict(rest=True, dur=dur, len=length, tie=tie)
    midi = 12 * (int(octv) + 1) + STEP[n] + {'': 0, '#': 1, 'b': -1}[acc]
    if s:
        s = int(s)
    else:
        cands = [k for k, o in OPEN.items() if p <= midi - o <= p + 4]
        if len(cands) != 1:
            errors.append(f"{where}: {tok} は手の位置 {p} の範囲で弦が決まらない")
            s = min(OPEN, key=lambda k: abs(midi - OPEN[k] - p - 2))
        else:
            s = cands[0]
    fret = midi - OPEN[s]
    if not 0 <= fret <= 24:
        errors.append(f"{where}: {tok} は {s}弦で弾けない")
    w = midi + 12                                              # 記譜は1オクターブ上
    wo = w // 12 - 1
    marks = "'" * (wo - 3) if wo > 3 else "," * (3 - wo)
    name = n.lower() + LY_ACC[acc]
    return dict(rest=False, ly=f"{name}{marks}{dur}\\{s}{tie}", dur=dur, len=length,
                string=s, fret=fret, midi=midi)

def voice_ly(bars, pos, where):
    out, events, t = [], [], F(0)
    for i, bar in enumerate(bars):
        p = pos[i] if isinstance(pos, list) else pos
        items = []
        for tok in bar.split():
            e = parse(tok, p, f"{where} {i+1}小節")
            items.append(e["ly"] if not e["rest"] else f"r{e['dur']}")
            if not e["rest"]:
                events.append((t, t + e["len"], e["string"], e["fret"], i + 1))
            t += e["len"]
        out.append(" ".join(items))
    return out, events

def check_simultaneous(events, where):
    for a in events:
        for b in events:
            if a is b or not (a[0] < b[1] and b[0] < a[1]):
                continue
            if a[2] == b[2]:
                errors.append(f"{where} {a[4]}小節: 同じ弦（{a[2]}）で2音が重なる")
            frets = [x for x in (a[3], b[3]) if x > 0]
            if frets and max(frets) - min(frets) > 4:
                errors.append(f"{where} {a[4]}小節: 同時に押さえる幅が広すぎる（{a[3]}と{b[3]}）")

def staff(clef, lines, orient=None, breaks=4):
    body = []
    for i, l in enumerate(lines):
        sep = " | \\break\n    " if (i + 1) % breaks == 0 and i + 1 < len(lines) else " |\n    "
        body.append(l + (sep if i + 1 < len(lines) else ""))
    o = f" \\set stringNumberOrientations = #'({orient})" if orient else ""
    return f"\\clef {clef} \\time 4/4{o}\n    " + "".join(body) + ' \\bar "|."'

def score(e):
    chords = f"  \\new ChordNames \\chordmode {{ {e['chords']} }}\n"
    if "melody" in e:
        m, me = voice_ly(e["melody"], e["pos"], e["title"])
        b, be = voice_ly(e["bass"], e["pos"], e["title"])
        check_simultaneous(me + be, e["title"])
        return ("<<\n" + chords + "  \\new PianoStaff <<\n"
                f"    \\new Staff {{\n    {staff('treble', m, 'up', e.get('breaks', 4))}\n    }}\n"
                f"    \\new Staff {{\n    {staff('bass', b, 'down', e.get('breaks', 4))}\n    }}\n"
                "  >>\n>>\n")
    if "upper" in e:                                           # ルート＋和音（第5章型）
        up, ue = voice_ly(e["upper"], e["pos"], e["title"])
        lo, le = voice_ly(e["bass"], e["pos"], e["title"])
        return ("<<\n" + chords + "  \\new PianoStaff <<\n"
                f"    \\new Staff {{\n    {staff('treble', up, 'up', e.get('breaks', 4))}\n    }}\n"
                f"    \\new Staff {{\n    {staff('bass', lo, 'down', e.get('breaks', 4))}\n    }}\n"
                "  >>\n>>\n")
    l, _ = voice_ly(e["line"], e["pos"], e["title"])
    return ("<<\n" + chords + f"  \\new Staff {{\n    {staff('bass', l, None, e.get('breaks', 4))}\n  }}\n>>\n")


# ---------------------------------------------------------------- 練習曲のデータ
D = 3  # Dポジション（⑥弦の D1 に人差し指）

ETUDES = [
dict(
 id="et1", title="練習曲1　三つの音域", chapters="第1章・第3章",
 chords="f1:7 bes:7 f:7 f:7 bes:7 bes:7 f:7 d:7 g:m7 c:7 f:7 c:7",
 pos=[D]*10 + [1, 1],
 line=["F1 A1 C2 B1", "Bb1 D2 F2 Gb2", "F2 A2 C3 D3", "Eb3 D3 C3 A2",
       "Bb2 D3 F3 D3", "Ab2 Bb2 C3 E3", "F3 Eb3 C3 A2", "D3 C3 A2 F#2",
       "G2 F2 D2 Bb1", "C2 Bb1 G1 E1", "F1 Eb1 D1 C1", "C1/2 E1 G1"],
 intro="F のブルース12小節のウォーキングです。1〜4小節目で中域から高域へ上がり、5〜8小節目は高域にとどまり、9小節目から下りて、最後の2小節で初めて Low B 弦の音域（E♭1、D1、C1）を使います。",
 points=["5〜7小節目で①弦の F3 を頂上にし、そこから11小節目まで一度も上に戻らずに下ります（第3章 3.4節）。",
         "Low B 弦の音域は11〜12小節目だけです。曲の最後の山場のためにとっておく、という第3章の考え方を実際に試します。",
         "11小節目から手の位置を下げます（⑥弦の C1 を人差し指で押さえる位置）。手の移動が、ラインの区切りと重なっています。",
         "各小節の4拍目は、すべて次の小節の1拍目へ半音か全音で近づく音です。"],
),
dict(
 id="et2", title="練習曲2　Dポジションのマイナー", chapters="第2章",
 chords="d1:m7.5- g:7 c:m6 as:maj7 d:m7.5- g:7 c:m6 c:m6",
 pos=D,
 line=["D2 F2 Ab2 C3", "B2 Ab2 F2 Db2", "C2 Eb2 G2 A2", "Ab2 G2 Eb2 C2",
       "D2 E2 F2 Ab2", "G2 Ab2 B2 Db3", "C3 B2 A2 G2", "Eb2 G2 F2 Eb2"],
 intro="C マイナーのⅡ-Ⅴ-Ⅰを2回まわす8小節です。全体を Dポジションのまま弾きます。G7 はオルタード、Cm6 はメロディック・マイナー、Dm7(♭5) の2回目はロクリアン♮2 で弾いています。",
 points=["2小節目と6小節目の G7 では、オルタード・スケールの音（A♭、D♭）を使っています。",
         "3小節目と7小節目の Cm6 では、メロディック・マイナーの A（長6度）と B（長7度）を聞かせます。",
         "1小節目の Dm7(♭5) はコード・トーンだけで弾き、5小節目ではロクリアン♮2 の 9度（E）を加えています。",
         "8小節目の最後の E♭2 は、1小節目の D2 に半音上から戻る音です。"],
),
dict(
 id="et3", title="練習曲3　2拍ごとの着地点", chapters="第3章",
 chords="bes2:maj7 g:7 c:m7 f:7 d:m7 g:7 c:m7 f:7 f:m7 bes:7 es:maj7 as:7 d:m7 g:7 c:m7 f:7",
 pos=D,
 line=["Bb1 Ab1 G1 B1", "C2 E2 F2 Eb2", "D2 A1 G1 Db2", "C2 Bb1 A1 Gb1",
       "F1 Ab1 Bb1 D2", "Eb2 G2 Ab2 Eb2", "D2 F2 G2 B1", "C2 Eb2 F2 A1"],
 intro="B♭ のキーで、2拍ごとにコードが変わる8小節です。各コードの1拍目にルート、2拍目に次のルートへのアプローチを置く形を、8小節続けます。",
 points=["アプローチの型（第3章 3.2節）を、なるべく毎回変えています。たとえば1小節目は「半音上から」（A♭1 → G1）と「半音下から」（B1 → C2）です。",
         "3小節目の D♭2 は、G7 の裏コード D♭7 のルートです（第4章）。",
         "4小節目の3拍目は、ルートではなく F7 の3度（A1）から始めています。そのあと G♭1 で、5小節目の F1 へ半音上から近づきます。",
         "8小節目の最後の A1 は、1小節目の B♭1 に半音下から戻る音です。"],
),
dict(
 id="et4", title="練習曲4　裏道を通って", chapters="第4章",
 chords="c1:maj7 es:7 d:m7 des:7 c:maj7 f2:m7 bes:7 c1:maj7 c:maj7",
 pos=[D]*7 + [1],
 line=["C2 E2 G2 E2", "Eb2 G2 Bb2 Db3", "D3 C3 A2 D2", "Db2 F2 Ab2 B2",
       "C3 B2 G2 E2", "F2 Ab2 Bb2 Db3", "C3 A2 G2 D2", "C1/1"],
 intro="C のキーの8小節です。セカンダリー・ドミナントの裏コード（E♭7、D♭7）と、バックドア・ドミナント（Fm7 - B♭7）を使ったリハモの上でウォーキングします。",
 points=["1〜4小節目の1拍目は C → E♭ → D → D♭ と動きます。2小節目から先は、半音ずつ下りるベースラインです。",
         "4小節目の最後の B2 は、D♭7 の7度（C♭）で、同時に G7 の3度でもあります（第4章 4.2節）。",
         "6小節目はバックドア・ドミナントです。4拍目の D♭3 は B♭7 の♯9度で、7小節目の C3 へ半音上から解決します。",
         "最後の小節は、トニックを⑥弦の C1 で鳴らして終わります。"],
),
dict(
 id="et5", title="練習曲5　ガイドトーンの伴奏", chapters="第5章",
 chords="g1:m7 c:7 f:maj7 bes:maj7 e:m7.5- a:7 d:m7 d:m7",
 pos=D,
 upper=None, bass=None,  # 和音は下で手書き
 intro="F のキーで、4度進行を7つ続ける8小節の伴奏です。1拍目でルートを弾き、2拍目の裏でガイドトーン（3度と7度）を②①弦で弾いて伸ばします（チャールストンのリズム）。",
 points=["上声部の2音は、コードが変わるたびに半音か全音で動くか、そのまま残ります（第5章 5.2節）。",
         "5小節目で上声部を1オクターブ上に移して、仕切り直しています。そのまま続けると、6小節目の A7 のトライトーンが G2 - C♯3 になり、下の音が目安（B♭2）を下回るためです。",
         "4小節目の B♭maj7 の上声部 A2 - D3 は完全4度で、下の音がちょうど目安（A2）です。",
         "8分音符はスウィングで弾きます。"],
),
dict(
 id="et6", title="練習曲6　ドリアンの16小節", chapters="第6章",
 chords="d1:m7 d:m7 d:m7 d:m7 d:m7 d:m7 d:m7 d:m7 es:m7 es:m7 es:m7 es:m7 d:m7 d:m7 d:m7 d:m7",
 pos=D,
 line=["D2 F2 G2 A2", "B2 C3 D3 B2", "A2 G2 E2 F2", "G2 A2 B2 D3",
       "E3 D3 B2 A2", "G2 F2 E2 C2", "D2 B1 A1 G1", "A1 B1 C2 D2",
       "Eb2 Gb2 Bb2 C3", "Db3 C3 Bb2 Gb2", "Ab2 Bb2 C3 Eb3", "Db3 Bb2 Gb2 Eb2",
       "D2 F2 A2 B2", "C3 A2 G2 E2", "F2 C2 A1 E1", "D1/1"],
 intro="D ドリアン8小節、E♭ ドリアン4小節、D ドリアン4小節の16小節です。全体を Dポジションのまま弾きます。",
 points=["D ドリアンの部分では、特性音の B を何度も聞かせ、C♯ は一度も使いません（第6章 6.3節）。",
         "8小節目は D2 まで上がり、9小節目の E♭2 へ半音下から入ります。E♭ ドリアンの部分では、特性音の C を聞かせます。",
         "12小節目の最後の E♭2 は、13小節目の D2 に半音上から戻る音です。",
         "15小節目の最後は、導音の C♯ ではなく、全音上の E1 から D1 に着地します。"],
),
dict(
 id="et7", title="練習曲7　エンクロージャーのソロ", chapters="第7章",
 chords="g1:m7 c:7 f:maj7 f:maj7 a:m7.5- d:7 g2:m7 c:7 f1:maj7",
 pos=D,
 line=["G2/8 A2/8 Bb2/8 C3/8 D3/8 G3/8 F3/8 D#3/8",
       "E3/8 D3/8 C3/8 Bb2/8 A2/8 G2/8 Bb2/8 G#2/8",
       "A2/8 C3/8 E3/8 G3/8 F3/8 E3/8 D3/8 C3/8",
       "A2/2 r/2",
       "r/8 A2/8 C3/8 Eb3/8 G3/8 Eb3/8 G3/8 F3/8",
       "F#3/8 Eb3/8 D3/8 C3/8 Bb2/8 A2/8 C3/8 A2/8",
       "Bb2/8 D3/8 F3/8 D3/8 C3/8 E3/8 G3/8 E3/8",
       "F3/2 r/2"],
 intro="F のキーで、8分音符のソロ・ラインを弾く8小節です。小節の変わり目で、次のコードの3度にエンクロージャーで着地します。すべて Dポジションで弾けます。",
 points=["1小節目の最後は F3 → D♯3 → E3（C7 の3度）、2小節目の最後は B♭2 → G♯2 → A2（Fmaj7 の3度）のエンクロージャーです（第7章 7.3節）。",
         "4小節目は半分が休符です。前半4小節の区切りで、息つぎを入れています。",
         "5小節目の最後は G3 → F3 → F♯3（D7 の3度）、6小節目の最後は C3 → A2 → B♭2（Gm7 の3度）で着地します。",
         "7小節目の最後の G3 → E3 → F3 も、最後のトニックの F を上下から挟む形です。"],
),
dict(
 id="et8", title="練習曲8　ひとりで弾く", chapters="第8章",
 chords="c1:maj7 a:7 d:m7 g:7 e:m7 a:7 d2:m7 g:7 c1:maj7",
 pos=[D]*7 + [1],
 melody=["E3/1", "C#3/2 E3/2", "F3/1", "F3/2 D3/2", "G3/1", "E3/2 C#3/2", "F3/2 B2/2", "E3/1"],
 bass=["C2 G1 B1 Bb1", "A1/1", "D2 A1 F1 Ab1", "G1/1", "E1 G1 B1 Bb1", "A1/1", "D2/2 G1/2", "C1/1"],
 intro="C のキーで、オリジナルのメロディをソロベースで弾く8小節です。メロディが伸びている小節（1、3、5小節目）ではベースが歩き、メロディが動く小節ではルートを伸ばします。",
 points=["メロディの強拍の音は、ほとんどがコードの3度か7度です。ルートを足すだけでコードが聞こえます（第8章 8.2節）。",
         "1、3、5小節目では、メロディを①弦で伸ばしたまま、⑥⑤④弦でベースを歩かせます。メロディを押さえる指を先に決めてください。",
         "4拍目のアプローチ（1小節目の B♭1、3小節目の A♭1、5小節目の B♭1）は、どれも次のルートへ半音上から近づきます。",
         "最後の小節だけ手の位置を下げ、⑥弦の C1 とメロディの E3 を同時に鳴らして終わります。"],
),
]

# 練習曲5の和音（ルート＋ガイドトーン、チャールストンのリズム）は手で書き、弦の指定は check で検査する
ET5_UPPER = [
 "r4 r8 <bes\\2 f'\\1>8~ <bes f'>2", "r4 r8 <bes\\2 e'\\1>8~ <bes e'>2",
 "r4 r8 <a\\2 e'\\1>8~ <a e'>2", "r4 r8 <a\\2 d'\\1>8~ <a d'>2",
 "r4 r8 <d'\\2 g'\\1>8~ <d' g'>2", "r4 r8 <cis'\\2 g'\\1>8~ <cis' g'>2",
 "r4 r8 <c'\\2 f'\\1>8~ <c' f'>2", "r4 r8 <c'\\2 f'\\1>8~ <c' f'>2",
]
ET5_BASS = ["G1 r/2.", "C2 r/2.", "F1@5 r/2.", "Bb1@4 r/2.", "E1@6 r/2.", "A1 r/2.", "D2 r/2.", "D2 r/2."]

def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    md = [HEADER]
    for e in ETUDES:
        if e["id"] == "et5":
            lo, _ = voice_ly(ET5_BASS, e["pos"], e["title"])
            sc = ("<<\n" + f"  \\new ChordNames \\chordmode {{ {e['chords']} }}\n" + "  \\new PianoStaff <<\n"
                  f"    \\new Staff {{\n    {staff('treble', ET5_UPPER, 'up')}\n    }}\n"
                  f"    \\new Staff {{\n    {staff('bass', lo, 'down')}\n    }}\n  >>\n>>\n")
        else:
            sc = score(e)
        md.append(f"## {e['title']}\n\n**関連する章**：{e['chapters']}\n\n{e['intro']}\n\n"
                  f"```lilypond {{#{e['id']} caption=\"{e['title']}\"}}\n{sc}```\n\n"
                  "**ポイント**\n\n" + "\n".join(f"- {p}" for p in e["points"]) + "\n")
    md.append(FOOTER)
    if errors:
        print("\n".join(errors)); sys.exit(1)
    (root / "chapters/09-etudes.md").write_text("\n".join(md))
    print("wrote chapters/09-etudes.md")

HEADER = """# 第9章　練習曲

この章には、第1章から第8章までの内容をまとめた8つの練習曲を収めました。どの曲も本書のために作ったオリジナルです。

練習曲は、次の順番で取り組むと効果的です。

1. **ゆっくり弾く。** メトロノームを遅めに設定し、譜面の弦の指定どおりに弾きます。
2. **ポイントを確かめる。** 各曲の「ポイント」を読み、その曲で何を練習しているのかを意識しながら弾きます。
3. **テンポを上げる。** 弦の指定どおりに弾けるようになったら、少しずつテンポを上げます。
4. **自分のラインに変える。** 同じコード進行で、ポイントの考え方を守りながら、自分のラインを作ります。練習曲は、そのための手本です。

ほとんどの曲は、第2章の Dポジション（⑥弦の D1 に人差し指を置いた手の位置）の中で弾けるように作ってあります。手の位置を変える場所は、各曲のポイントに書いてあります。
"""

FOOTER = """## 練習曲の使い方のまとめ

| 曲 | 練習すること | 関連する章 |
|---|---|---|
| 1 | 3つの音域を使い分け、Low B を最後にとっておく | 第1章・第3章 |
| 2 | 1つのポジションのまま、マイナーのスケールを切り替える | 第2章 |
| 3 | 2拍ごとのアプローチの型を使い分ける | 第3章 |
| 4 | 裏コードとバックドア・ドミナントの上で歩く | 第4章 |
| 5 | ルートとガイドトーンで伴奏する | 第5章 |
| 6 | モードの特性音を聞かせ、モードの切り替わりを示す | 第6章 |
| 7 | エンクロージャーで3度に着地するソロ | 第7章 |
| 8 | メロディの下でベースを歩かせる | 第8章 |
"""

if __name__ == "__main__":
    main()
