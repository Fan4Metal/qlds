# Выделенный сервер Quake Live — Classic FFA

[English](README.md) · **Русский**

Выделенный сервер [Quake Live](https://store.steampowered.com/app/282440/Quake_Live/)
в Docker с режимом **Classic Free-For-All** (все против всех). Собран на базе
образа [Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards)
с плагинами [minqlx](https://github.com/MinoMino/minqlx) и хранилищем Redis.

## Требования

- [Docker](https://docs.docker.com/get-docker/) и плагин Docker Compose
- Открытые порты на хосте/фаерволе (см. [Порты](#порты))

## Быстрый старт

```bash
# 1. Создайте свои секреты и список доступа (оба файла в .gitignore)
cp ffa/secret.cfg.example ffa/secret.cfg
cp access.txt.example access.txt

# 2. Отредактируйте ffa/secret.cfg -> пароли, ваш SteamID64 (qlx_owner), имя сервера
# 3. Отредактируйте access.txt      -> ваш SteamID64 как admin

# 4. Запустите
docker compose up -d

# Логи / наблюдение за запуском
docker compose logs -f ffa
```

Остановка — `docker compose down` (данные Redis сохраняются в volume `redis`).

## Структура конфигурации

| Файл | Назначение |
|------|-----------|
| [compose.yml](compose.yml) | Сервисы, порты, volume'ы |
| [ffa/server.cfg](ffa/server.cfg) | Базовый конфиг QLDS (Redis, floodprotect, master) |
| [ffa/autoexec.cfg](ffa/autoexec.cfg) | Геймплей: ротация карт, голосования, warmup, брендинг, minqlx |
| `ffa/secret.cfg` | **Секреты и личные данные** (не в git) — пароли, `qlx_owner`, имя сервера, брендинг |
| [ffa/secret.cfg.example](ffa/secret.cfg.example) | Шаблон для `secret.cfg` |
| [ffa/mappool.txt](ffa/mappool.txt) | Пул карт ротации |
| [ffa/workshop.txt](ffa/workshop.txt) | ID предметов Steam Workshop для загрузки |
| [ffa/minqlx-plugins/](ffa/minqlx-plugins/) | Python-плагины minqlx |
| `access.txt` | Список admin / mod / ban (не в git; сервер правит его в рантайме) |
| [access.txt.example](access.txt.example) | Шаблон для `access.txt` |

`autoexec.cfg` выполняется при старте и **последним шагом** запускает `secret.cfg`,
поэтому значения оттуда перекрывают всё заданное ранее. Так все секреты и личные
идентификаторы лежат в одном неотслеживаемом файле.

## Секреты и личные данные

В репозиторий не попадает ничего чувствительного. Всё приватное лежит в двух
git-ignored файлах, создаваемых из шаблонов `*.example`:

**`ffa/secret.cfg`**
- `zmq_rcon_password` / `zmq_stats_password` — пароли API rcon и статистики
- `sv_privatePassword` — пароль зарезервированных слотов
- `qlx_owner` — ваш SteamID64 (без него minqlx не выполняет админ-команды)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — имя и брендинг сервера

**`access.txt`**
- Ваш SteamID64 с пометкой `admin`

Узнать свой SteamID64 — на [steamid.io](https://steamid.io/).

## Порты

| Порт | Протокол | Назначение |
|------|----------|------------|
| 27960 | UDP | Игровой трафик |
| 27960 | TCP | Статистика ZMQ |
| 28960 | TCP | Rcon ZMQ |

Правьте маппинг в [compose.yml](compose.yml), если запускаете несколько серверов
или нужны другие внешние порты.

## Карты и Steam Workshop

- Пул ротации — [ffa/mappool.txt](ffa/mappool.txt) (по строке `карта|фабрика`).
- Кастомные карты берутся из Steam Workshop; их ID перечислены в
  [ffa/workshop.txt](ffa/workshop.txt).

### Как работает загрузка

У сервера Quake Live есть **встроенный** загрузчик, который качает айтемы из
`workshop.txt` при старте, но в контейнерах он крайне ненадёжен — часто виснет
на `Waiting on Workshop downloads: 0.00%` или падает с
`Download item … failed with EResult code 2`.

Чтобы этого избежать, отдельный одноразовый **init-сервис `workshop`**
(см. [compose.yml](compose.yml)) использует `steamcmd` — надёжный штатный
загрузчик Steam — и скачивает все ID из `workshop.txt` в общий Docker-volume
`steamapps` **до** старта игрового сервера. Логика загрузки —
[scripts/download-workshop.sh](scripts/download-workshop.sh). Сервер QL затем
монтирует этот volume read-only; манифест, записанный steamcmd, помечает айтемы
как установленные, поэтому сервер не запускает свою (сломанную) загрузку.

- **Первый** `docker compose up` дольше — steamcmd качает контент; последующие
  запуски быстрые, т.к. steamcmd пропускает уже скачанное.
- Чтобы добавить карту: впишите её Workshop ID в `workshop.txt`, добавьте карту
  в `mappool.txt` и перезапустите.
- Принудительно перекачать: `docker compose down`, затем
  `docker volume rm qlds_steamapps`.
- Бинарников Workshop в репозитории нет.

## Администрирование

Команды minqlx вводятся в игре (префикс по умолчанию `!`). Несколько частых:

- `!help` — список команд
- `!map <карта> <фабрика>` — смена карты (например, `!map campgrounds ffa`)
- `!ban <id>` / `!kick <id>` — модерация
- `!reload_access` — перечитать `access.txt` после ручной правки

Сервер может перезаписывать `access.txt` при смене карты/выключении, поэтому
управляйте доступом через игровые команды, пока сервер запущен.

## Данные и персистентность

Состояние хранится в двух именованных Docker-volume'ах:

- `redis` — база minqlx (права, баны, статистика)
- `steamapps` — скачанный контент Steam Workshop

Чтобы очистить:

```bash
docker compose down
docker volume rm qlds_redis qlds_steamapps   # имена могут быть с префиксом папки проекта
```

## Лицензия / благодарности

Собрано на базе фреймворка
[Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards) и
[minqlx](https://github.com/MinoMino/minqlx). Quake Live — торговая марка
id Software / ZeniMax.
