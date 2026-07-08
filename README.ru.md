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
# 1. Скопировать секреты и список доступа (оба файла в .gitignore)
cp ffa/secret.cfg.example ffa/secret.cfg
cp access.txt.example access.txt

# 2. Отредактировать ffa/secret.cfg -> пароли, SteamID64 (qlx_owner), имя сервера
# 3. Отредактировать access.txt      -> SteamID64 как admin

# 4. Запустить
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
- `qlx_owner` — SteamID64 владельца (без него minqlx не выполняет админ-команды)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — имя и брендинг сервера

**`access.txt`**
- SteamID64 владельца с пометкой `admin`

SteamID64 можно узнать на [steamid.io](https://steamid.io/).

## Порты

| Порт | Протокол | Назначение |
|------|----------|------------|
| 27960 | UDP | Игровой трафик |
| 27960 | TCP | Статистика ZMQ |
| 28960 | TCP | Rcon ZMQ |

Маппинг портов настраивается в [compose.yml](compose.yml) — для нескольких
серверов или других внешних портов.

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
- Чтобы добавить карту: вписать её Workshop ID в `workshop.txt`, добавить карту
  в `mappool.txt` и перезапустить стек.
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
доступом лучше управлять через игровые команды, пока сервер запущен.

## Данные и персистентность

Состояние хранится в двух именованных Docker-volume'ах:

- `redis` — база minqlx (права, баны, статистика)
- `steamapps` — скачанный контент Steam Workshop

Чтобы очистить:

```bash
docker compose down
docker volume rm qlds_redis qlds_steamapps   # имена могут быть с префиксом папки проекта
```

### Бэкап и восстановление базы Redis

```bash
bash scripts/backup-redis.sh            # создаёт backups/redis-<timestamp>.rdb
bash scripts/restore-redis.sh <файл>    # останавливает стек, восстанавливает, запускает
```

Бэкап сначала делает синхронный `SAVE`, чтобы снимок был актуальным;
восстановление кладёт файл прямо в volume `qlds_redis` при остановленном стеке
(создавая том при необходимости — работает и на новом сервере). Дампы
(`backups/`, `*.rdb`) в git не попадают.

## Своя сборка образа сервера (опционально)

По умолчанию `ffa` тянет готовый образ `quakeliveserverstandards/ql-server`.
Для самостоятельной сборки движка + minqlx (пины версий, компактнее образ) есть
[Dockerfile](Dockerfile) и opt-in override:

```bash
docker compose -f compose.yml -f compose.build.yml build
docker compose -f compose.yml -f compose.build.yml up -d
```

`compose.build.yml` лишь добавляет `build:` сервису `ffa` — redis, init-загрузка
воркшопа и все монтирования берутся из [compose.yml](compose.yml) без изменений.
Пины версий (базовый образ, minqlx, плагины) — вверху Dockerfile. Важно: свой
образ нужно пересобирать под апдейты QL/minqlx, а перед боевым использованием
сборку стоит протестировать.

**Требования к диску.** Сборка качает полный сервер QL (~1.5 ГБ) и требует места
на распаковку, компиляцию minqlx и слои образа. Минимально необходимо
**~6 ГБ свободного места** на сборку; итоговый образ занимает ~2 ГБ. На маленькой
VM (например, диск 8–9 ГБ, где уже лежит готовый образ) места не хватает, и
steamcmd падает с обманчивой ошибкой `Missing configuration`. Текущий объём
показывает `df -h`; освободить место можно через `docker builder prune -af`
(но не `docker system prune --volumes` — это удалит том базы `qlds_redis`).

## Лицензия / благодарности

Собрано на базе фреймворка
[Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards) и
[minqlx](https://github.com/MinoMino/minqlx). Quake Live — торговая марка
id Software / ZeniMax.
