FROM alpine:3.20

RUN apk add --no-cache \
      python3 py3-pip \
      git openssh-client \
      bash curl jq \
      ansible-core && \
    pip3 install --no-cache-dir --break-system-packages \
      yq paramiko netaddr

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV ANSIBLE_CONFIG=/playbook/ansible.cfg
WORKDIR /playbook
ENTRYPOINT ["/entrypoint.sh"]
