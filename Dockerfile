FROM --platform=$BUILDPLATFORM golang:1.27.1-alpine3.23 AS build_deps
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

FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

RUN apk add --no-cache ca-certificates

COPY --from=build /workspace/webhook /usr/local/bin/webhook

ENTRYPOINT ["webhook"]
