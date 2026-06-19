FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/p11-kit /tmp/p11-kit-ssh-home \
 && useradd --uid 65532 --gid 0 --home-dir /tmp/p11-kit-ssh-home --no-create-home --shell /usr/sbin/nologin p11kitssh

COPY proxy-start.sh /app/proxy-start.sh
RUN chmod +x /app/proxy-start.sh

ENTRYPOINT ["/app/proxy-start.sh"]
