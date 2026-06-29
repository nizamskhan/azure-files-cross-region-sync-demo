FROM ubuntu:24.04

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar; \
    curl -L https://aka.ms/downloadazcopy-v10-linux -o /tmp/azcopy.tar.gz; \
    mkdir -p /tmp/azcopy; \
    tar -xzf /tmp/azcopy.tar.gz -C /tmp/azcopy --strip-components=1; \
    mv /tmp/azcopy/azcopy /usr/local/bin/azcopy; \
    chmod +x /usr/local/bin/azcopy; \
    rm -rf /tmp/azcopy /tmp/azcopy.tar.gz /var/lib/apt/lists/*

COPY sync-azure-files.sh /usr/local/bin/sync-azure-files.sh
RUN chmod +x /usr/local/bin/sync-azure-files.sh

ENTRYPOINT ["/usr/local/bin/sync-azure-files.sh"]
