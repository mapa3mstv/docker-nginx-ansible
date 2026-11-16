# Ansible CI/CD: деплой репозиториев на удаленный сервер через Docker + nginx

Плейбуки выполняют полный цикл: склонировать указанный ref → выбрать сервер по `-e target=`
→ скопировать код → собрать docker-образ (Dockerfile содержит полный CI, включая тесты)
→ запустить/заменить контейнер → настроить реверс-прокси subdomain.base_domain в nginx
с TLS от Let's Encrypt.

## Структура

```
ansible-deploy/
├── docker-compose.yml          # изолированная среда выполнения Ansible
├── docker/                     # образ runner (alpine + ansible-core + git)
│   ├── Dockerfile
│   └── entrypoint.sh
├── ansible.cfg                 # inventory, роли, настройки вывода
├── inventory/hosts.yml         # удаленные серверы (выбор через -e target=<host>)
├── playbooks/
│   ├── deploy.yml              # мастер-плейбук CI (шаги 0–5)
│   ├── containers.yml          # список контейнеров и репозиториев
│   └── manage.yml              # start / stop / restart / purge / logs по репозиторию
├── roles/deploy/
│   └── tasks/{parse,prepare,copy,build,run,nginx,registry}.yml
├── ssh_keys/                   # положить сюда SSH-ключ (монтируется в ~/.ssh)
└── README.md
```

## Конфигурация проекта: devops.yaml (в корне репозитория)

```yaml
nginx:
    subdomain: xxx.xz        # итоговый fqdn = <subdomain>.<base_domain из inventory>
docker:
    image: myproject         # имя образа и контейнера (1 репозиторий = 1 контейнер)
    volumes:
        - folderA:/etc/myapp # /dockervolumes/folderA -> /etc/myapp в контейнере
        - folderB:/opt/myapp
    purgePolicy: deleteAll   # container | image | deleteAll
```

Внутренний порт приложения задаётся ENV `APP_PORT` в Dockerfile (по умолчанию 80);
контейнер публикуется только на `127.0.0.1` (рандомный хост-порт), наружу идёт через nginx.

## Запуск (из docker-compose)

```bash
# 0) Собрать среду один раз
docker compose build

# Деплой: клонирование ref -> сборка CI-образа на prod1 -> запуск -> nginx+TLS
docker compose run --rm ansible playbooks/deploy.yml \
    -e repo_url=git@example.com:team/myproject.git \
    -e ref=main \
    -e target=prod1

# Логи сборки только с ошибками (ERROR-фильтрация)
docker compose run --rm ansible playbooks/deploy.yml \
    -e repo_url=... -e ref=main -e target=prod1 -e log_level=error

# Список запущенных контейнеров и репозиториев, из которых они собраны
docker compose run --rm ansible playbooks/containers.yml -e target=prod1

# Управление контейнером конкретного репозитория
docker compose run --rm ansible playbooks/manage.yml -e target=prod1 -e repo=myproject -e action=start
docker compose run --rm ansible playbooks/manage.yml -e target=prod1 -e repo=myproject -e action=stop
docker compose run --rm ansible playbooks/manage.yml -e target=prod1 -e repo=myproject -e action=restart
docker compose run --rm ansible playbooks/manage.yml -e target=prod1 -e repo=myproject -e action=logs
docker compose run --rm ansible playbooks/manage.yml -e target=prod1 -e repo=myproject -e action=purge
```

## purge-политика (manage.yml, action=purge)

| purgePolicy | контейнер | образ | маршрут nginx | volumes проекта | исходники /opt/apps/<repo> |
|-------------|:--------:|:-----:|:-------------:|:---------------:|:---------------------------:|
| container   | ✅       | —     | —             | —               | —                           |
| image       | ✅       | ✅    | ✅            | —               | ✅                          |
| deleteAll   | ✅       | ✅    | ✅            | ✅              | ✅                          |

Политика запоминается в реестре сервера `/etc/ansible-deploy/registry.yml` при деплое,
поэтому purge работает без повторного клонирования репозитория.

## Логи

- **Логи сборки**: печатаются шагом `Print build log`; полный лог всегда сохраняется на
  сервере в `/opt/apps/<repo>/.logs/build-latest.log`. При `-e log_level=error`
  в консоль выводятся только строки с error/failed/fatal.
- **Логи запуска контейнера**: последние 200 строк `docker logs` печатаются после старта
  (также фильтруются при `log_level=error`).
- **Логи любого контейнера позже**: `manage.yml -e action=logs`.

## Требования к серверу

- Linux с установленным Docker и nginx; доступ по SSH под пользователем с sudo (`become`).
- Открытые 80/443 и DNS A-запись `*.base_domain` (или конкретного subdomain) на сервер —
  для Let's Encrypt webroot-челленджа.
- certbot устанавливается плейбуком автоматически (пакеты `certbot`, `python3-certbot-nginx`).
- Получение сертификата: `certbot certonly --webroot -w /var/www/certbot -d <fqdn>` (email — переменная `ssl_email`).
- Автопродление: плейбук ставит cron-задание `certbot renew --quiet --deploy-hook "reload nginx"` (ежедневно в 03:15), лог — `/var/log/certbot-renew.log`.
