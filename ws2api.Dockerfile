# The WebSocket proxy from github.com/mevdschee/ws2api (ADR 13), which compose
# passes in as the build context `ws2api`. It terminates chat connections and
# turns them into plain HTTP against the API server, which is what keeps the
# API stateless.
#
# Nothing is patched here: the proxy takes its listen address and API URL as
# flags, which compose supplies as WS2API_LISTEN and WS2API_URL.
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY --from=ws2api go.mod go.sum ./
RUN go mod download
COPY --from=ws2api . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/wsproxy ./wsproxy

FROM alpine:3.20
RUN adduser -D -u 1000 ws2api
COPY --from=build /out/wsproxy /usr/local/bin/wsproxy
USER ws2api
ENV WS2API_LISTEN=:7001 WS2API_URL=http://api:8080/wsoverhttp/
EXPOSE 7001
ENTRYPOINT ["wsproxy"]
