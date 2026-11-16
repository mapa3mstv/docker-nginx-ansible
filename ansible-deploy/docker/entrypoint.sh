#!/usr/bin/env bash
# Точка входа изолированного Ansible-контейнера.
# 1) Первый аргумент - имя playbook (или путь к нему внутри /playbook).
# 2) Остальные аргументы передаются ansible-playbook как есть.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  cat <<EOF
Использование:
  docker compose run --rm ansible <playbook> [-e key=value ...]

Примеры:
  docker compose run --rm ansible playbooks/deploy.yml \\
      -e repo_url=git@example.com:team/myproject.git \\
      -e ref=main -e target=prod1 -e log_level=error

  docker compose run --rm ansible playbooks/containers.yml            # список контейнеров
  docker compose run --rm ansible playbooks/manage.yml -e repo=myproject -e action=restart
  docker compose run --rm ansible playbooks/manage.yml -e repo=myproject -e action=purge
EOF
  exit 1
fi

PLAYBOOK="$1"; shift

# SSH: не спрашивать подтверждение host-key в CI, ключи смонтированы из ./ssh_keys
export ANSIBLE_HOST_KEY_CHECKING=False
mkdir -p /root/.ssh
chmod 700 /root/.ssh 2>/dev/null || true
[[ -f /root/.ssh/config ]] || cat > /root/.ssh/config <<'CFG'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
CFG

exec ansible-playbook "/playbook/${PLAYBOOK}" "$@"
