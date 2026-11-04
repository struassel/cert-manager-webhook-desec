FROM --platform=$BUILDPLATFORM golang:1.27.2-alpine3.23@sha256:9e45f0eb4a63ed37ad6e604950407558b7c738e34e015ae77a5d4ad369cde079 AS build_deps
ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache git

WORKDIR /workspace

ENV GOCACHE=/go-cache-${TARGETOS}-${TARGETARCH} GOMODCACHE=/gomod-cache-${TARGETOS}-${TARGETARCH} GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0

COPY go.mod go.sum ./

RUN --mount=type=cache,target=${GOMODCACHE} \
    go mod download -x

FROM --platform=$BUILDPLATFORM build_deps AS build

COPY . .

RUN --mount=type=cache,target=${GOMODCACHE} \
    --mount=type=cache,target=${GOCACHE} \
    go build -v -o webhook -ldflags '-w -extldflags "-static"' .

FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache ca-certificates \
    && addgroup --system --gid 1000 appuser \
    && adduser --system --uid 1000 --ingroup appuser appuser

COPY --from=build --chmod=770 --chown=1000:1000 /workspace/webhook /usr/local/bin/webhook

USER 1000

ENTRYPOINT ["webhook"]
