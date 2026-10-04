# syntax=docker/dockerfile:1.7

############################
# Stage 1 - builder
############################
ARG GO_VERSION=1.22
FROM golang:${GO_VERSION}-alpine AS builder

WORKDIR /src

# Salin go.mod dulu agar layer dependency ter-cache
COPY go.mod ./
RUN go mod download

COPY . .

# Versi di-inject lewat --build-arg VERSION=...
ARG VERSION=dev

# CGO_ENABLED=0 => binary statically linked (tanpa libc / shared library)
# -s -w         => buang symbol table & debug info (ukuran lebih kecil)
# -trimpath     => hilangkan path build dari binary (reproducible)
RUN CGO_ENABLED=0 GOOS=linux \
    go build -trimpath \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o /out/server .

############################
# Stage 2 - runtime (minimal)
############################
FROM scratch

ARG VERSION=dev
LABEL org.opencontainers.image.title="hello-devops" \
      org.opencontainers.image.version="${VERSION}"

# Binary ditaruh di direktori khusus (/app/bin) supaya direktori ini bisa
# di-mount dari host untuk hotfix swap (lihat README bagian Deploy).
COPY --from=builder /out/server /app/bin/server

# Jalankan sebagai non-root (UID:GID numerik karena scratch tidak punya /etc/passwd)
USER 65534:65534

ENV PORT=8080
EXPOSE 8080

# scratch tidak punya curl/wget, jadi health check memakai binary itu sendiri
HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
  CMD ["/app/bin/server", "-healthcheck"]

ENTRYPOINT ["/app/bin/server"]
