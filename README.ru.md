# Выделенный сервер Quake Live

[English](README.md) · **Русский**

Выделенные серверы [Quake Live](https://store.steampowered.com/app/282440/Quake_Live/)
в Docker. Собраны на базе образа
[Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards)
с плагинами [minqlx](https://github.com/MinoMino/minqlx) и хранилищем Redis.
Предусмотрено два сервера с общими Redis и volume'ом Steam Workshop:

| Сервер | Режим | Конфиг | Включение |
|--------|-------|--------|-----------|
| `ffa` | Classic Free-For-All | [ffa/](ffa/) | всегда (по умолчанию) |
| `instagib_ffa_pql` | PQL Instagib FFA (кастомная фабрика) | [instagib_ffa_pql/](instagib_ffa_pql/) | профиль Compose `instagib` |

Оба сервера описаны в [compose.yml](compose.yml). FFA-сервер стартует по
умолчанию; инстагиб-сервер включается опционально через профиль Compose
`instagib` (см. [Запуск обоих серверов](#запуск-обоих-серверов)).

## Требования

- [Docker](https://docs.docker.com/get-docker/) и плагин Docker Compose
- Открытые порты на хосте/фаерволе (см. [Порты](#порты))

## Быстрый старт

```bash
# 1. Скопировать секреты и список доступа (все файлы в .gitignore)
cp ffa/secret.cfg.example ffa/secret.cfg
cp instagib_ffa_pql/secret.cfg.example instagib_ffa_pql/secret.cfg
cp access.txt.example access.txt

# 2. Отредактировать файлы secret.cfg -> пароли, SteamID64 (qlx_owner), имя сервера
# 3. Отредактировать access.txt        -> SteamID64 как admin

# 4. Запустить (добавление инстагиб-сервера — см. «Запуск обоих серверов»)
docker compose up -d

# Логи / наблюдение за запуском
docker compose logs -f ffa
```

Остановка — `docker compose down` (данные Redis сохраняются в volume `redis`).

### Запуск обоих серверов

Оба сервера описаны в [compose.yml](compose.yml). Инстагиб-серверу назначен
**профиль** Compose `instagib`, поэтому он не поднимается, пока профиль не
включён:

```bash
docker compose up -d                        # только FFA (по умолчанию)
docker compose --profile instagib up -d     # FFA + инстагиб
```

Чтобы включать его по умолчанию без флага — задать профиль в локальном `.env`
рядом с `compose.yml` (файл в .gitignore):

```dotenv
# .env
COMPOSE_PROFILES=instagib
```

После этого обычный `docker compose up -d` поднимает оба сервера. Важно: `docker
compose up -d` без профиля **не останавливает** уже запущенный инстагиб-сервер —
для остановки нужен явный `docker compose --profile instagib down` (или
`docker compose stop instagib_ffa_pql`).

## Структура конфигурации

Конфиг каждого сервера лежит в своём каталоге ([ffa/](ffa/),
[instagib_ffa_pql/](instagib_ffa_pql/)) с одинаковой структурой файлов; каталог
[minqlx-plugins/](minqlx-plugins/), [workshop.txt](workshop.txt) и `access.txt` —
общие. В таблице ниже — FFA-сервер; инстагиб-сервер устроен так же.

| Файл | Назначение |
|------|-----------|
| [compose.yml](compose.yml) | Оба сервиса-сервера (инстагиб под профилем `instagib`), общие `workshop`/`redis`, volume'ы |
| [ffa/server.cfg](ffa/server.cfg) | Базовый конфиг QLDS (Redis, floodprotect, master) |
| [ffa/autoexec.cfg](ffa/autoexec.cfg) | Геймплей: ротация карт, голосования, warmup, брендинг, minqlx |
| `ffa/secret.cfg` | **Секреты и личные данные** (не в git) — пароли, `qlx_owner`, имя сервера, брендинг |
| [ffa/secret.cfg.example](ffa/secret.cfg.example) | Шаблон для `secret.cfg` |
| [ffa/mappool.txt](ffa/mappool.txt) | Пул карт ротации |
| [workshop.txt](workshop.txt) | ID предметов Steam Workshop для загрузки, **общий для обоих серверов** |
| [minqlx-plugins/](minqlx-plugins/) | Python-плагины minqlx, **общие для обоих серверов** |
| `access.txt` | Список admin / mod / ban (не в git; сервер правит его в рантайме), общий для обоих серверов |
| [access.txt.example](access.txt.example) | Шаблон для `access.txt` |

У инстагиб-сервера есть один файл, которого нет у FFA, — кастомная игровая
фабрика [instagib_ffa_pql/instagib_ffa_pql.factories](instagib_ffa_pql/instagib_ffa_pql.factories)
(правила PQL Instagib). Она монтируется в `baseq3/scripts/`, откуда Quake Live
грузит `*.factories`. Кроме того, он использует отдельную логическую базу Redis
(`qlx_redisDatabase "1"`), поэтому его баны и статистика изолированы от FFA.

`autoexec.cfg` выполняется при старте и **последним шагом** запускает `secret.cfg`,
поэтому значения оттуда перекрывают всё заданное ранее. Так все секреты и личные
идентификаторы каждого сервера лежат в одном неотслеживаемом файле.

## Секреты и личные данные

В репозиторий не попадает ничего чувствительного. Всё приватное лежит в
git-ignored файлах, создаваемых из шаблонов `*.example`:

**`ffa/secret.cfg`** и **`instagib_ffa_pql/secret.cfg`** (по одному на сервер)
- `zmq_rcon_password` / `zmq_stats_password` — пароли API rcon и статистики
- `sv_privatePassword` — пароль зарезервированных слотов
- `qlx_owner` — SteamID64 владельца (без него minqlx не выполняет админ-команды)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — имя и брендинг сервера

Каждому серверу стоит задать свой `sv_hostname`, чтобы они различались в браузере
серверов.

**`access.txt`** (общий для обоих серверов)
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

[qlstats.net](https://qlstats.net) собирает статистику игроков и даёт FFA ELO,
который плагин `balance` использует для `!elo` и балансировки. Конфиг уже
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

Каждый сервер регистрируется отдельно: инстагиб-сервер использует **TCP 27961** и
`zmq_stats_password` из `instagib_ffa_pql/secret.cfg`.

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
