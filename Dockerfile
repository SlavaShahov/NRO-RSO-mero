FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /bin/rso-api ./cmd/api

FROM alpine:3.21
RUN adduser -D -g '' appuser
USER appuser
WORKDIR /home/appuser
COPY --from=builder /bin/rso-api /usr/local/bin/rso-api
EXPOSE 8080
ENTRYPOINT ["rso-api"]
