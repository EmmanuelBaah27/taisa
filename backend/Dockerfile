FROM node:20.20.2-bookworm-slim AS build
WORKDIR /app
COPY package.json ./
COPY package-lock.json ./
COPY backend/package.json backend/package.json
COPY shared/package.json shared/package.json
RUN npm ci --workspaces --include-workspace-root
COPY backend backend
COPY shared shared
RUN npm run build --workspace=backend

FROM node:20.20.2-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
COPY package-lock.json ./
COPY backend/package.json backend/package.json
COPY shared/package.json shared/package.json
RUN npm ci --omit=dev --workspaces --include-workspace-root \
  && sed -i 's/index\.ts/index.js/g' shared/package.json
COPY --from=build /app/backend/dist/backend/src backend/dist/backend/src
COPY --from=build /app/backend/dist/shared shared
COPY backend/src/db/schema.sql backend/dist/backend/src/db/schema.sql
RUN chown -R node:node /app
USER node
EXPOSE 3000
CMD ["npm", "run", "start", "--workspace=backend"]
