https://cp.chenyong.life {
    encode gzip

    header Strict-Transport-Security "max-age=31536000; includeSubDomains"

    reverse_proxy 127.0.0.1:12000 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
    }
}
