# syntax=docker/dockerfile:1.7

ARG ELEMENT_CALL_REPO=https://github.com/vector-im/element-call.git
ARG ELEMENT_CALL_REF=v0.20.0

FROM node:22-alpine AS source
RUN apk add --no-cache git
WORKDIR /src
ARG ELEMENT_CALL_REPO
ARG ELEMENT_CALL_REF
RUN git clone --depth 1 --branch "${ELEMENT_CALL_REF}" "${ELEMENT_CALL_REPO}" .

FROM source AS deps
RUN corepack enable && corepack prepare pnpm@11.6.0 --activate
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

FROM deps AS build
ARG VITE_PRODUCT_NAME
ARG VITE_APP_VERSION=dev
COPY overlay/ /overlay/
RUN cp -R /overlay/. /src/ && rm -rf /overlay
RUN VITE_PRODUCT_NAME="${VITE_PRODUCT_NAME}" \
    VITE_APP_VERSION="${VITE_APP_VERSION}" \
    VITE_CUSTOM_CSS="$(cat /src/branding.css)" \
    pnpm run build:full:production

FROM ghcr.io/element-hq/element-call:v0.20.0 AS runtime
USER root
RUN rm -rf /app/*
COPY --from=build /src/dist /app
