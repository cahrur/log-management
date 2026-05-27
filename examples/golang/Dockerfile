# Multi-stage build untuk Go app
# Hasil binary kecil, image final ~20MB

# === Build stage ===
FROM golang:1.23-alpine AS builder

WORKDIR /build

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.version=$(git describe --tags --always 2>/dev/null || echo dev)" \
    -o /app ./cmd/server

# === Runtime stage ===
FROM alpine:3.20

# Security: non-root user
RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app

# Timezone data (kalau butuh)
RUN apk add --no-cache ca-certificates tzdata wget

WORKDIR /home/app

COPY --from=builder /app /app

# Switch ke non-root
USER app:app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/app"]
