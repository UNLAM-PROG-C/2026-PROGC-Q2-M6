FROM python:3.11-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8080
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "-u", "main.py"]
CMD ["--duration", "300"]
