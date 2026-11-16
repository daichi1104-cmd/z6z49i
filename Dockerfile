# band2score の Web アプリをクラウドで動かすためのイメージ。
#   docker build -t band2score .
#   docker run -p 7860:7860 -e BAND2SCORE_PASSWORD=好きな合言葉 band2score
# Hugging Face Spaces（Docker）にもそのまま置けます（ポート 7860）。
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
# GPU の無いサーバー向けに、小さい CPU 版の PyTorch を先に入れる
RUN pip install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir --no-deps basic-pitch

# 音源分離のモデルを先にダウンロードしておく（最初の変換を待たせないため）
ENV TORCH_HOME=/app/models
RUN python -c "from demucs.pretrained import get_model; get_model('htdemucs_6s')"

COPY band2score ./band2score
RUN useradd -m app && mkdir -p /data && chown -R app /data /app/models
USER app
# librosa（numba）のキャッシュを書き込める場所に置く（root 以外で動かすため）
ENV BAND2SCORE_DATA=/data PORT=7860 NUMBA_CACHE_DIR=/tmp/numba_cache
EXPOSE 7860
CMD ["sh", "-c", "python -m band2score.web --port ${PORT}"]
