# this was created by an AI agent

FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY server/ ./server/
USER node
EXPOSE 8080
CMD ["node", "server/main.mjs"]
