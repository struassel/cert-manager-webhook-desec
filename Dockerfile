FROM golang:1.25.1-alpine3.22 AS build

RUN apk add --no-cache git

WORKDIR /workspace

COPY . .

RUN go mod download -x \
    && CGO_ENABLED=0 go build -v -o webhook -ldflags '-w -extldflags "-static"' .

FROM alpine:3.22

RUN apk add --no-cache ca-certificates

COPY --from=build /workspace/webhook /usr/local/bin/webhook

ENTRYPOINT ["webhook"]
