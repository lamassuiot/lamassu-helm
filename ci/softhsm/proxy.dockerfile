FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/p11-kit /root/.ssh

COPY proxy-start.sh /app/proxy-start.sh
RUN chmod +x /app/proxy-start.sh

ENTRYPOINT ["/app/proxy-start.sh"]
