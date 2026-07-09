# Выделенный сервер Quake Live

[English](README.md) · **Русский**

Выделенные серверы [Quake Live](https://store.steampowered.com/app/282440/Quake_Live/)
в Docker. Собраны на базе образа
[Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards)
с плагинами [minqlx](https://github.com/MinoMino/minqlx) и хранилищем Redis.
Предусмотрено несколько серверов с общими Redis и volume'ом Steam Workshop:

| Сервер | Режим | Конфиг | Профиль |
|--------|-------|--------|---------|
| `ffa` | Classic Free-For-All | [ffa/](ffa/) | `ffa` (или `ffa_all`, `all`) |
| `instagib_ffa_pql` | PQL Instagib FFA (кастомная фабрика) | [instagib_ffa_pql/](instagib_ffa_pql/) | `instagib` (или `ffa_all`, `all`) |
| `duel` | Duel (сток, без модификаций геймплея) | [duel/](duel/) | `duel` (или `all`) |

Все серверы описаны в [compose.yml](compose.yml) и закрыты профилями Compose:
`ffa`, `instagib`, `duel` (по одному серверу), `ffa_all` (оба FFA-сервера) либо
`all` (все сразу). Какие из них стартуют по умолчанию, задаётся через
`COMPOSE_PROFILES` в [.env](.env) — по умолчанию `ffa` (см.
[Запуск серверов](#запуск-серверов)).

## Требования

- [Docker](https://docs.docker.com/get-docker/) и плагин Docker Compose
- Открытые порты на хосте/фаерволе (см. [Порты](#порты))

## Быстрый старт

```bash
# 1. Скопировать секреты и список доступа (все файлы в .gitignore)
cp ffa/secret.cfg.example ffa/secret.cfg
cp instagib_ffa_pql/secret.cfg.example instagib_ffa_pql/secret.cfg
cp duel/secret.cfg.example duel/secret.cfg
cp access.txt.example access.txt

# 2. Отредактировать файлы secret.cfg -> пароли, SteamID64 (qlx_owner), имя сервера
# 3. Отредактировать access.txt        -> SteamID64 как admin

# 4. Запустить (поднимет только FFA; остальные серверы — см. «Запуск серверов»)
docker compose up -d

# Логи / наблюдение за запуском
docker compose logs -f ffa
```

Остановка — `docker compose down` (данные Redis сохраняются в volume `redis`).

### Запуск серверов

У каждого игрового сервера свой **профиль** Compose — `ffa`, `instagib` и `duel`.
Два FFA-сервера дополнительно входят в `ffa_all`, а все — в `all`. (`redis` и
init-сервис `workshop` профиля не имеют и поднимаются всегда.) Выбор того, что
запускать:

```bash
docker compose --profile ffa up -d          # только FFA
docker compose --profile instagib up -d     # только инстагиб
docker compose --profile duel up -d         # только duel
docker compose --profile ffa_all up -d      # оба FFA-сервера (ffa + instagib)
docker compose --profile all up -d          # все серверы
```

Что поднимает обычный `docker compose up -d` (без `--profile`), задаётся через
`COMPOSE_PROFILES` в [.env](.env) — по умолчанию `ffa`. Значение меняется, чтобы
стартовало другое:

```dotenv
# .env
COMPOSE_PROFILES=all        # все серверы; либо `duel`, либо `ffa,duel` и т.д.
```

CLI-флаг `--profile` перекрывает значение из `.env`. Важно: запуск другого набора
профилей **не останавливает** серверы, уже поднятые из предыдущего набора, — их
нужно гасить явно, например `docker compose --profile all down` или
`docker compose stop duel`.

## Структура конфигурации

Конфиг каждого сервера лежит в своём каталоге ([ffa/](ffa/),
[instagib_ffa_pql/](instagib_ffa_pql/), [duel/](duel/)) с одинаковой структурой
файлов; каталог [minqlx-plugins/](minqlx-plugins/), [workshop.txt](workshop.txt)
и `access.txt` — общие. В таблице ниже — FFA-сервер; остальные устроены так же.

| Файл | Назначение |
|------|-----------|
| [compose.yml](compose.yml) | Все сервисы-серверы (каждый под своим профилем Compose), общие `workshop`/`redis`, volume'ы |
| [.env](.env) | Профили Compose по умолчанию — какие серверы поднимает обычный `docker compose up` |
| [ffa/server.cfg](ffa/server.cfg) | Базовый конфиг QLDS (Redis, floodprotect, master) |
| [ffa/autoexec.cfg](ffa/autoexec.cfg) | Геймплей: ротация карт, голосования, warmup, брендинг, minqlx |
| `ffa/secret.cfg` | **Секреты и личные данные** (не в git) — пароли, `qlx_owner`, имя сервера, брендинг |
| [ffa/secret.cfg.example](ffa/secret.cfg.example) | Шаблон для `secret.cfg` |
| [ffa/mappool.txt](ffa/mappool.txt) | Пул карт ротации |
| [workshop.txt](workshop.txt) | ID предметов Steam Workshop для загрузки, **общий для всех серверов** |
| [minqlx-plugins/](minqlx-plugins/) | Python-плагины minqlx, **общие для всех серверов** |
| `access.txt` | Список admin / mod / ban (не в git; сервер правит его в рантайме), общий для всех серверов |
| [access.txt.example](access.txt.example) | Шаблон для `access.txt` |

У инстагиб-сервера есть один файл, которого нет у FFA, — кастомная игровая
фабрика [instagib_ffa_pql/instagib_ffa_pql.factories](instagib_ffa_pql/instagib_ffa_pql.factories)
(правила PQL Instagib). Она монтируется в `baseq3/scripts/`, откуда Quake Live
грузит `*.factories`. Duel-серверу такой файл не нужен — он использует **стоковую
фабрику `duel`** без геймплейных cvar'ов, поэтому играется как ванильный дуэль.
У каждого сервера своя логическая база Redis (`qlx_redisDatabase` = `0` для FFA,
`1` для инстагиба, `2` для duel), поэтому баны и статистика изолированы.

`autoexec.cfg` выполняется при старте и **последним шагом** запускает `secret.cfg`,
поэтому значения оттуда перекрывают всё заданное ранее. Так все секреты и личные
идентификаторы каждого сервера лежат в одном неотслеживаемом файле.

## Секреты и личные данные

В репозиторий не попадает ничего чувствительного. Всё приватное лежит в
git-ignored файлах, создаваемых из шаблонов `*.example`:

**`ffa/secret.cfg`**, **`instagib_ffa_pql/secret.cfg`** и **`duel/secret.cfg`** (по одному на сервер)
- `zmq_rcon_password` / `zmq_stats_password` — пароли API rcon и статистики
- `sv_privatePassword` — пароль зарезервированных слотов
- `qlx_owner` — SteamID64 владельца (без него minqlx не выполняет админ-команды)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — имя и брендинг сервера
- `sv_tags` (опционально, по умолчанию закомментировано) — доп. теги в браузере серверов

Каждому серверу стоит задать свой `sv_hostname`, чтобы они различались в браузере
серверов.

**`access.txt`** (общий для всех серверов)
- SteamID64 владельца с пометкой `admin`

SteamID64 можно узнать на [steamid.io](https://steamid.io/).

## Порты

| Сервер | Порт | Протокол | Назначение |
|--------|------|----------|------------|
| `ffa` | 27960 | UDP | Игровой трафик |
| `ffa` | 27960 | TCP | Статистика ZMQ |
| `ffa` | 28960 | TCP | Rcon ZMQ |
| `instagib_ffa_pql` | 27961 | UDP | Игровой трафик |
| `instagib_ffa_pql` | 27961 | TCP | Статистика ZMQ |
| `instagib_ffa_pql` | 28961 | TCP | Rcon ZMQ |
| `duel` | 27962 | UDP | Игровой трафик |
| `duel` | 27962 | TCP | Статистика ZMQ |
| `duel` | 28962 | TCP | Rcon ZMQ |

Маппинг портов настраивается в [compose.yml](compose.yml) — если нужны другие
внешние порты.

## Карты и Steam Workshop

- Пул ротации — [ffa/mappool.txt](ffa/mappool.txt) (по строке `карта|фабрика`).
- Кастомные карты берутся из Steam Workshop; их ID перечислены в
  [workshop.txt](workshop.txt).

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

## Статистика и ELO (qlstats.net)

[qlstats.net](https://qlstats.net) собирает статистику игроков и даёт ELO по
режимам, который плагин `balance` использует для `!elo` и балансировки. Конфиг уже
настроен на него (`qlx_balanceUrl "qlstats.net"`, `qlx_balanceUseLocal "0"`), но
сервер нужно **зарегистрировать**, чтобы фидер qlstats подключился к нему и начал
собирать статистику.

Предпосылки (в репозитории уже выставлены):

- `zmq_stats_enable "1"` и `zmq_stats_password` (в `ffa/secret.cfg`).
- Порт ZMQ-статистики доступен из интернета. Здесь статистика идёт по **TCP
  27960** (тот же номер, что и игровой порт), и [compose.yml](compose.yml) его
  уже публикует — на файрволе хоста порт тоже должен быть открыт.

Регистрация:

1. На <https://qlstats.net> нажать кнопку **Add server** (откроется панель
   регистрации сервера; собственный адрес панели со временем может меняться).
2. Указать `<ip-сервера>:27960` и `zmq_stats_password` из `ffa/secret.cfg`.
3. Отправить форму. Фидер подключится к сокету статистики; ELO появится через
   несколько сыгранных матчей.

Для повторной проверки после изменения настроек — на той же странице кликнуть по
порту (подставит `server:port`), ввести только текущий ZMQ Stats Password и снова
отправить. Ошибка `can't connect` обычно означает, что `zmq_stats_enable` не
`1`, порт закрыт, либо пароль / ip / порт не совпадают.

Каждый сервер регистрируется отдельно, со своим `zmq_stats_password`:
инстагиб-сервер использует **TCP 27961** (`instagib_ffa_pql/secret.cfg`), duel —
**TCP 27962** (`duel/secret.cfg`).

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
