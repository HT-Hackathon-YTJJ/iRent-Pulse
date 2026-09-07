# 部署到 Hugging Face Spaces（sdk: docker）用的映像檔。
#
# Space 的容器以 uid 1000 執行，程式碼目錄不保證可寫，所以照片存放位置改指到
# /tmp——demo 不需要永久保存，Space 重啟時清掉反而乾淨。
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PHOTO_DIR=/tmp/irent-photos

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY app ./app

# HF Spaces 預設把流量導到 7860（README frontmatter 的 app_port）。
EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
