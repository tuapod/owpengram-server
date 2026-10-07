# syntax=docker/dockerfile:1.7

# ==========================================
# Stage 1: Base Build Environment
# ==========================================
ARG GO_IMAGE=golang:1.25-alpine
ARG ALPINE_IMAGE=alpine:3.22

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build-base

ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache ca-certificates git

WORKDIR /src

COPY go.mod go.sum ./

# ✅ فرمت صحیح Railway: id=s/<service-id>-<target-path>
RUN --mount=type=cache,id=s/<service-id>-/go/pkg/mod,target=/go/pkg/mod go mod download

COPY cmd/ ./cmd/
COPY deploy/ ./deploy/
COPY internal/ ./internal/

ENV CGO_ENABLED=0

# ==========================================
# Stage 2: Build Main Server
# ==========================================
FROM build-base AS build-server

ARG VCS_REF=unknown
ARG VCS_BRANCH=unknown
ARG VCS_TREE_STATE=unknown
ARG BUILD_DATE=unknown

# ✅ فرمت صحیح Railway
RUN --mount=type=cache,id=s/<service-id>-/go/pkg/mod,target=/go/pkg/mod \
    --mount=type=cache,id=s/<service-id>-/root/.cache/go-build,target=/root/.cache/go-build \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build -trimpath \
    -ldflags="-s -w -X main.gitCommit=${VCS_REF} -X main.gitBranch=${VCS_BRANCH} -X main.gitTreeState=${VCS_TREE_STATE} -X main.buildTime=${BUILD_DATE}" \
    -o /out/telesrv ./cmd/telesrv

# ==========================================
# Stage 3: Build Admin Panel
# ==========================================
FROM build-base AS build-admin

RUN apk add --no-cache nodejs npm

WORKDIR /src/cmd/telesrv-admin/web

# ✅ فرمت صحیح Railway
RUN --mount=type=cache,id=s/<service-id>-/root/.npm,target=/root/.npm npm ci && npm run build

WORKDIR /src

# ✅ فرمت صحیح Railway
RUN --mount=type=cache,id=s/<service-id>-/go/pkg/mod,target=/go/pkg/mod \
    --mount=type=cache,id=s/<service-id>-/root/.cache/go-build,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/telesrv-admin ./cmd/telesrv-admin

# ==========================================
# Stage 4: Final Runtime Image
# ==========================================
FROM ${ALPINE_IMAGE}

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=build-server /out/telesrv /app/telesrv
COPY --from=build-admin /out/telesrv-admin /app/telesrv-admin
COPY --from=build-admin /src/cmd/telesrv-admin/web/dist /app/web

EXPOSE 8080

ENTRYPOINT ["/app/telesrv"]
