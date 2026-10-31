"""Claude Code の UserPromptSubmit フック。発言のたびに、今の会話の長さと前回からの空き時間を調べ、
区切ったほうがよいときだけ AI への注意書きを出す（標準出力の内容が AI の文脈に足される）。

設定（~/.claude/settings.json）:
  "hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command",
      "command": "python \"C:/Users/<ユーザー名>/.claude/hooks/context_guard.py\"", "timeout": 10}]}]}
"""
import datetime as dt, json, os, sys

SPLIT_AT = 300_000   # これを超えたら区切りを勧める
URGENT_AT = 500_000  # これを超えたら強く勧める
IDLE_MIN = 5         # 前回の応答からこの分数以上空き、
IDLE_CTX = 100_000   # かつ会話がこの長さ以上なら、書き直しが起きたと知らせる
TAIL_BYTES = 4_000_000


def last_usage(path):
    """会話記録の末尾から、最後の応答の usage と時刻を返す。"""
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        fh.seek(max(0, size - TAIL_BYTES))
        lines = fh.read().decode("utf-8", errors="ignore").splitlines()
    for line in reversed(lines):
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message") or {}
        u = m.get("usage")
        if d.get("type") == "assistant" and u and m.get("model") != "<synthetic>":
            return u, d.get("timestamp")
    return None, None


def main():
    try:
        data = json.load(sys.stdin)
        path = data.get("transcript_path")
        if not path or not os.path.exists(path):
            return
        u, ts = last_usage(path)
        if not u:
            return
        ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) \
            + u.get("cache_creation_input_tokens", 0) + u.get("output_tokens", 0)
        msgs = []
        if ts:
            gap = (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds() / 60
            if gap >= IDLE_MIN and ctx >= IDLE_CTX:
                span = f"{gap / 1440:.0f}日" if gap >= 1440 else f"{gap / 60:.0f}時間" if gap >= 60 else f"{gap:.0f}分"
                msgs.append(f"前回の応答から{span}空いたため、この発言で会話全体（約{ctx // 10000}万トークン）を読み込み直している可能性が高い。")
        if ctx >= URGENT_AT:
            msgs.append(f"会話が約{ctx // 10000}万トークンあり、1回のやり取りの費用が大きい。今の依頼に答えた後、引き継ぎメモ（handoff スキル）を書いて新しい会話に移るよう、ユーザーに強く勧めること。")
        elif ctx >= SPLIT_AT:
            msgs.append(f"会話が約{ctx // 10000}万トークンある。作業の切れ目なら、引き継ぎメモ（handoff スキル）を書いて新しい会話に移るよう、ユーザーに勧めること。")
        elif msgs:
            msgs.append("作業の切れ目なら、新しい会話に移るよう勧めること。")
        if msgs:
            print("【会話の長さの注意（context_guard フック）】" + " ".join(msgs))
    except Exception:
        return  # フックの失敗で作業を止めない


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
