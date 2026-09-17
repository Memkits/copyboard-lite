https://cp.chenyong.life {
    encode gzip

    header Strict-Transport-Security "max-age=31536000; includeSubDomains"

    handle /api/* {
        reverse_proxy 127.0.0.1:12000
    }

    handle /health {
        reverse_proxy 127.0.0.1:12000
    }

    @assets path /assets/*
    header @assets Cache-Control "public, max-age=31536000, immutable"

    handle {
        root * /web-assets/repo/Memkits/copyboard-lite/
        try_files {path} /index.html
        file_server
    }
}
