FROM golang:1.25.1-alpine3.22 AS build_deps

RUN apk add --no-cache git

WORKDIR /workspace

COPY go.mod go.sum ./

RUN go mod download -x

FROM build_deps AS build

COPY . .

RUN CGO_ENABLED=0 go build -v -o webhook -ldflags '-w -extldflags "-static"' .

FROM alpine:3.22

RUN apk add --no-cache ca-certificates

COPY --from=build /workspace/webhook /usr/local/bin/webhook

ENTRYPOINT ["webhook"]
