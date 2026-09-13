# ==========================================
# Multi-stage Dockerfile Template
# ==========================================

# 1. ビルドステージ
FROM node:20-alpine AS builder

WORKDIR /app

# 依存関係定義ファイルのコピー
COPY package*.json ./

# 依存パッケージのインストール
RUN npm ci

# ソースコードのコピーとビルド
COPY . .
RUN npm run build --if-present

# 2. 実行ステージ
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# 非特権ユーザーの作成と切り替え
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nodeuser

# ビルド成果物およびに必要なファイルのコピー
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist 2>/dev/null || true

USER nodeuser

EXPOSE 8080

CMD ["node", "dist/index.js"]
