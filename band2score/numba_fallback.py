"""numba を読み込めない PC 用の「代わりの部品」。

numba は Python の関数を機械語に変換して速くする部品で、librosa（テンポ・コードの解析）と
resampy の土台になっている。ところが Windows 11 の「スマート アプリ コントロール」が numba の
中の llvmlite.dll を止めることがあり、そうなると librosa の多くの機能が使えない。

このモジュールは numba と同じ名前・同じ使い方の部品を、ふつうの Python と NumPy で提供する。
計算の中身は librosa の元の関数そのままなので結果は同じで、遅くなるだけ（この用途では数秒程度）。
本物の numba を読み込めるときは使われない。

対応している numba の機能（librosa 0.10〜1.0・resampy が使うもの）:
  jit / njit, vectorize, guvectorize, stencil, prange, TypingError, 型名（uint32 など）
"""

from __future__ import annotations

import os
import re
import sys
import types

import numpy as np

ACTIVE = False  # 代わりの部品を使っているか
REASON = ""  # 本物の numba を読み込めなかった理由

__version__ = "0.0+band2score-fallback"


class TypingError(Exception):
    """numba.TypingError の代わり（この部品では起きない）。"""


def _numba_range(*args):
    """numba の range と同じく、小数を渡されたら 0 の方向に切り捨てて整数にする。

    numba 用に書かれた関数（librosa 0.11 の拍の検出など）は range に小数を渡すことがあり、
    ふつうの Python の range だとエラーになるため。
    """
    return range(*(a if isinstance(a, int) else int(a) for a in args))


prange = _numba_range


def _numba_semantics(func):
    """numba 用に書かれた関数が、ふつうの Python でも同じように動くようにする。

    関数が属するモジュールの中だけで range を numba と同じ振る舞いのものにする
    （この代わりの部品が使われているときだけ。整数を渡したときの動きは変わらない）。
    """
    module_globals = getattr(func, "__globals__", None)
    if module_globals is not None and "range" not in module_globals:
        module_globals["range"] = _numba_range
    return func


# ---------------------------------------------------------------- jit
def jit(*args, **kwargs):
    """関数をそのまま返す（@jit と @jit(...) のどちらの書き方にも対応）。"""
    if len(args) == 1 and callable(args[0]) and not kwargs:
        return _numba_semantics(args[0])
    return _numba_semantics


njit = jit
generated_jit = jit


# ---------------------------------------------------------------- vectorize
# 大きな配列に使われる関数は、要素ごとの Python 呼び出しだと遅すぎるので NumPy で書き直す
_FAST_VECTORIZE = {
    "_cabs2": lambda x: (x.real ** 2 + x.imag ** 2),
    "_phasor_angles": lambda x: np.cos(x) + 1j * np.sin(x),
}


def vectorize(*args, **kwargs):
    signatures = args[0] if args and not callable(args[0]) else None

    def decorate(func):
        fast = _FAST_VECTORIZE.get(func.__name__)
        if fast is not None:
            def call(x, out=None):
                result = fast(np.asarray(x))
                if out is not None:
                    out[...] = result
                    return out
                return result
            call.__name__ = func.__name__
            return call
        _numba_semantics(func)
        otypes = None
        if signatures:
            ret = _dtype(str(signatures[0]).split("(")[0])
            otypes = [ret] if ret is not None else None
        return np.vectorize(func, otypes=otypes)

    if args and callable(args[0]):
        return decorate(args[0])
    return decorate


# ---------------------------------------------------------------- 型
_DTYPES = {
    "bool_": np.bool_, "boolean": np.bool_, "b1": np.bool_,
    "int8": np.int8, "int16": np.int16, "int32": np.int32, "int64": np.int64,
    "uint8": np.uint8, "uint16": np.uint16, "uint32": np.uint32, "uint64": np.uint64,
    "intp": np.intp, "uintp": np.uintp, "uint": np.uint64,
    "float32": np.float32, "float64": np.float64, "f4": np.float32, "f8": np.float64,
    "complex64": np.complex64, "complex128": np.complex128,
}
for _name, _t in _DTYPES.items():
    globals()[_name] = _t


def _dtype(text: str):
    name = text.strip().replace("[:]", "").replace("[::1]", "").strip()
    return _DTYPES.get(name)


# ---------------------------------------------------------------- guvectorize
_DIMS = re.compile(r"\(([^)]*)\)")


def _parse_layout(layout: str) -> tuple[list[tuple[str, ...]], list[tuple[str, ...]]]:
    left, right = layout.replace(" ", "").split("->")

    def dims(part: str) -> list[tuple[str, ...]]:
        return [tuple(d for d in m.split(",") if d) for m in _DIMS.findall(part)]

    return dims(left), dims(right)


def _split_signature(sig: str) -> list[str]:
    inner = str(sig)[str(sig).index("(") + 1:str(sig).rindex(")")]
    return [p.strip() for p in inner.split(",")]


class _GUFunc:
    """numba.guvectorize の代わり。中身の関数を、先頭の次元ごとに Python のループで呼ぶ。"""

    def __init__(self, func, signatures, layout: str):
        self.func = _numba_semantics(func)
        self.__name__ = getattr(func, "__name__", "gufunc")
        self.__doc__ = func.__doc__
        self.ins, self.outs = _parse_layout(layout)
        self.signatures = [_split_signature(s) for s in (signatures or [])]

    def _signature(self, inputs: list[np.ndarray], raw: tuple) -> list[str] | None:
        """numba（NumPy の ufunc）と同じく、宣言（シグネチャ）を上から見て、
        すべての入力を精度を落とさずに変換できる最初のものを選ぶ。

        Python の数（50.0 など）は、同じ種類（小数どうし）なら精度が下がっても変換できる扱い。
        """
        for sig in self.signatures:
            ok = True
            for arr, value, decl in zip(inputs, raw, sig):
                want = _dtype(decl)
                if want is None:
                    continue
                weak = isinstance(value, (bool, int, float, complex)) or np.ndim(value) == 0
                if not np.can_cast(arr.dtype, want, casting="same_kind" if weak else "safe"):
                    ok = False
                    break
            if ok:
                return sig
        return self.signatures[0] if self.signatures else None

    def _out_dtypes(self, inputs: list[np.ndarray], sig: list[str] | None) -> list:
        if sig is not None:
            return [_dtype(t) or np.float64 for t in sig[len(self.ins):]]
        base = inputs[0].dtype if inputs else np.float64
        return [base] * len(self.outs)

    def __call__(self, *args, out=None, **kwargs):
        n_in = len(self.ins)
        inputs = [np.asarray(a) for a in args[:n_in]]
        sig = self._signature(inputs, args[:n_in])
        if sig is not None:
            # numba は入力を宣言どおりの型（float32 など）に変換してから計算するので、それに合わせる
            # （合わせないと、小数の細かな誤差で拍の位置が 1つずれることがある）
            inputs = [a.astype(_dtype(t)) if _dtype(t) is not None and a.dtype != _dtype(t) else a
                      for a, t in zip(inputs, sig)]
        outputs = list(args[n_in:])
        if out is not None:
            outputs = list(out) if isinstance(out, tuple) else [out]

        sizes: dict[str, int] = {}
        loop_shapes = []
        for arr, core in zip(inputs, self.ins):
            if core:
                for name, size in zip(core, arr.shape[arr.ndim - len(core):]):
                    sizes[name] = size
            loop_shapes.append(arr.shape[:arr.ndim - len(core)])
        loop = np.broadcast_shapes(*loop_shapes) if loop_shapes else ()

        if not outputs:
            dtypes = self._out_dtypes(inputs, sig)
            outputs = [np.zeros(loop + tuple(sizes[d] for d in core), dtype=dt)
                       for core, dt in zip(self.outs, dtypes)]
        views = [np.broadcast_to(arr, loop + arr.shape[arr.ndim - len(core):])
                 for arr, core in zip(inputs, self.ins)]

        for idx in np.ndindex(*loop):
            call_args = []
            for arr, core in zip(views, self.ins):
                item = arr[idx]
                # () の入力は、宣言した型の精度に丸めたうえで Python の数として渡す
                # （NumPy の uint32 のまま渡すと、n - pre_max が負になるところで桁あふれする。
                #   numba は計算のときに型を広げるので、そうはならない）
                call_args.append(item if core else item[()].item())
            for arr, core in zip(outputs, self.outs):
                # 出力が () のときは、中身の関数が out[0] に書けるよう 1要素の配列（view）にする
                call_args.append(arr[idx] if core else arr[idx + (None,)])
            self.func(*call_args)
        return outputs[0] if len(outputs) == 1 else tuple(outputs)


def guvectorize(*args, **kwargs):
    if args and isinstance(args[0], str):  # @guvectorize("(n)->(n)") の書き方
        signatures, layout = None, args[0]
    else:
        signatures = args[0] if args else kwargs.get("signatures")
        layout = args[1] if len(args) > 1 else kwargs["layout"]
    return lambda func: _GUFunc(func, signatures, layout)


# ---------------------------------------------------------------- stencil
class _OutOfRange(Exception):
    pass


class _Relative:
    __slots__ = ("data", "i", "n")

    def __init__(self, data, i):
        self.data, self.i, self.n = data, i, len(data)

    def __getitem__(self, k):
        j = self.i + k
        if j < 0 or j >= self.n:
            raise _OutOfRange
        return self.data[j]


def _sten_localmax(x):
    out = np.zeros(len(x), dtype=bool)
    out[1:-1] = (x[1:-1] > x[:-2]) & (x[1:-1] >= x[2:])
    return out


def _sten_localmin(x):
    out = np.zeros(len(x), dtype=bool)
    out[1:-1] = (x[1:-1] < x[:-2]) & (x[1:-1] <= x[2:])
    return out


def _sten_parabolic(x):
    out = np.zeros(len(x), dtype=x.dtype if x.dtype.kind == "f" else np.float64)
    a = x[2:] + x[:-2] - 2 * x[1:-1]
    b = (x[2:] - x[:-2]) / 2
    with np.errstate(divide="ignore", invalid="ignore"):
        out[1:-1] = np.where(np.abs(b) >= np.abs(a), 0, -b / a)
    return out


def _sten_zero_crossings(x, threshold, zero_pos):
    out = np.zeros(len(x), dtype=bool)
    x0, x1 = x[1:].copy(), x[:-1].copy()  # x[0] と x[-1]（1つ前）
    x0[np.abs(x0) <= threshold] = 0
    x1[np.abs(x1) <= threshold] = 0
    if zero_pos:
        out[1:] = np.signbit(x0) != np.signbit(x1)
    else:
        out[1:] = np.sign(x0) != np.sign(x1)
    return out


# librosa のステンシルを、配列全体の NumPy 計算に置き換えたもの（要素ごとの呼び出しだと遅すぎる）
_FAST_STENCIL = {
    "_localmax_sten": _sten_localmax,
    "_localmin_sten": _sten_localmin,
    "_pi_stencil": _sten_parabolic,
    "_zc_stencil": _sten_zero_crossings,
}


def stencil(*args, **kwargs):
    """numba.stencil の代わり（1次元）。x[0] が今の要素、x[-1] が 1つ前。端は 0 にする。"""

    def decorate(kernel):
        _numba_semantics(kernel)
        fast = _FAST_STENCIL.get(kernel.__name__)
        if fast is not None:
            return lambda x, *extra: fast(np.asarray(x), *extra)

        def apply(x, *extra):
            x = np.asarray(x)
            values = []
            for i in range(len(x)):
                try:
                    values.append(kernel(_Relative(x, i), *extra))
                except _OutOfRange:
                    values.append(None)
            got = [v for v in values if v is not None]
            # numba と同じく、全部の戻り値が入る型にする（0 と 0.5 が混ざれば小数）
            out = np.zeros(len(x), dtype=np.asarray(got).dtype if got else x.dtype)
            for i, v in enumerate(values):
                if v is not None:
                    out[i] = v
            return out

        apply.__name__ = kernel.__name__
        return apply

    if args and callable(args[0]):
        return decorate(args[0])
    return decorate


# ---------------------------------------------------------------- 組み込み
def install(reason: str = "") -> None:
    """本物の numba の代わりに、このモジュールを numba として使えるようにする。"""
    global ACTIVE, REASON
    for name in list(sys.modules):  # 読み込みに失敗した本物の numba の残りを消す
        if name == "numba" or name.startswith("numba.") or name.startswith("llvmlite"):
            del sys.modules[name]
    me = sys.modules[__name__]
    sys.modules["numba"] = me
    # librosa などが「from numba.core.errors import ...」のように書いても動くように
    for sub in ("numba.core", "numba.core.errors", "numba.np", "numba.typed"):
        mod = types.ModuleType(sub)
        mod.TypingError = TypingError
        sys.modules[sub] = mod
    ACTIVE, REASON = True, reason


def ensure() -> None:
    """本物の numba が読み込めなければ、代わりの部品に切り替える。"""
    if "numba" in sys.modules and sys.modules["numba"] is sys.modules[__name__]:
        return
    if os.environ.get("BAND2SCORE_NUMBA_FALLBACK") == "1":  # 試験・逃げ道用
        install("BAND2SCORE_NUMBA_FALLBACK=1")
        return
    try:
        import numba  # noqa: F401
        import numba.core  # noqa: F401  本当に使える状態か（DLL まで読めたか）
    except Exception as e:  # noqa: BLE001 — DLL が止められたときは OSError など様々
        install(f"{type(e).__name__}: {e}")
