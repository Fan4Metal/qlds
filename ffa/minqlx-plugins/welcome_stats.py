"""
This is a plugin for minqlx created by Metal Fan (fan4_metal@mail.ru)
Copyright (c) 2025 Metal Fan

Version 0.5

Its purpose is to display welcome message and some information about the players.
"""

import minqlx
import requests
import re
import os
import json

# Файл с кастомными приветственными сообщениями (лежит рядом с плагином).
# Ключ — SteamID64 (строка), значение — строка или список строк.
SPECIAL_WELCOME_MESSAGES_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "special_welcome_messages.json"
)


class welcome_stats(minqlx.Plugin):
    def __init__(self):
        super().__init__()
        self.center_printed = set()
        self.SPECIAL_WELCOME_MESSAGES = self.load_special_welcome_messages()

        # Cvar для включения/отключения кастомных приветственных сообщений.
        # Установить 0 в конфиге сервера, чтобы отключить: set qlx_wsSpecialMsg "0"
        self.set_cvar_once("qlx_wsSpecialMsg", "1")

        # Правильная регистрация команды!
        self.add_command(("info", "stats"), self.cmd_info, usage="<id | steam_id>")

        self.add_hook("player_connect", self.handle_player_connect, priority=minqlx.PRI_LOWEST)
        self.add_hook("player_loaded", self.handle_player_loaded, priority=minqlx.PRI_LOWEST)
        self.add_hook("player_disconnect", self.handle_player_disconnect)

    def load_special_welcome_messages(self):
        try:
            with open(SPECIAL_WELCOME_MESSAGES_FILE, encoding="utf-8") as f:
                raw = json.load(f)
            # Ключи в JSON всегда строки — приводим к int (SteamID64).
            # Значение — объект {"name": ..., "message": ...} (name только для
            # читаемости), либо просто строка/список строк.
            result = {}
            for sid, entry in raw.items():
                msg = entry["message"] if isinstance(entry, dict) else entry
                result[int(sid)] = msg
            return result
        except FileNotFoundError:
            minqlx.get_logger(self).warning(
                "Special welcome messages file not found: %s", SPECIAL_WELCOME_MESSAGES_FILE
            )
            return {}
        except (ValueError, OSError) as e:
            minqlx.get_logger(self).warning(
                "Failed to load special welcome messages from %s: %s",
                SPECIAL_WELCOME_MESSAGES_FILE, e
            )
            return {}

    def handle_player_connect(self, player):
        if not player or player.steam_id < 10000000000000000:
            return

        sid = player.steam_id
        name = player.clean_name

        @minqlx.thread
        def fetch():
            data = self.get_ffa_data(sid)
            if not data:
                msg = f"^7Welcome, ^5{name}^7! Tracked games: ^1—^7, FFA ELO: ^1—"
            else:
                games = data["games"]
                elo = data["elo"]
                elo_str = f"^3{elo:^4}^7" if elo != "—" else "^1—^7"
                msg = f"^7Welcome, ^5{name}^7! Tracked games: ^2{games}^7, FFA ELO: {elo_str}"
            self.chat_reply(msg)

            if self.get_cvar("qlx_wsSpecialMsg", bool):
                special_msg = self.SPECIAL_WELCOME_MESSAGES.get(sid)
                if special_msg:
                    self.chat_reply(special_msg, name=name, sid=sid)

        fetch()

    def handle_player_loaded(self, player):
        if not player or player.steam_id < 10000000000000000:
            return

        if not self.get_cvar("qlx_wsSpecialMsg", bool):
            return

        sid = player.steam_id
        special_msg = self.SPECIAL_WELCOME_MESSAGES.get(sid)
        if not special_msg or sid in self.center_printed:
            return

        self.center_printed.add(sid)
        self.delayed_center_print(player, special_msg, name=player.clean_name, sid=sid)

    def handle_player_disconnect(self, player, reason):
        if player:
            self.center_printed.discard(player.steam_id)

    def cmd_info(self, player, msg, channel):
        if len(msg) < 2:
            player.tell("^7Usage: ^2!info <id | steam_id>")
            return minqlx.RET_STOP_EVENT

        query = " ".join(msg[1:]).strip()

        # 1. Short ID (0-63)
        if re.fullmatch(r"\d{1,2}", query):
            cid = int(query)
            target = minqlx.Player(cid) if 0 <= cid < 64 else None
            if target and target.steam_id >= 10000000000000000:
                self.show_stats(target.steam_id, target.clean_name)
                return minqlx.RET_STOP_EVENT
            player.tell(f"^3Player ^7{cid} ^3not found or is a bot.")
            return minqlx.RET_STOP_EVENT

        # 2. Full SteamID
        if re.fullmatch(r"\d{17}", query):
            sid = int(query)
            name = next((p.clean_name for p in minqlx.Player.iter_players() if p.steam_id == sid), f"Player {sid}")
            self.show_stats(sid, name)
            return minqlx.RET_STOP_EVENT

        player.tell("^3Invalid input. Use short ID (0-63) or full 17-digit SteamID.")
        return minqlx.RET_STOP_EVENT

    def show_stats(self, steam_id, name):
        @minqlx.thread
        def fetch():
            data = self.get_ffa_data(steam_id)
            if not data:
                msg = f"^5{name}^7 (^3{steam_id}^7) — ^1no FFA data on qlstats.net"
            else:
                games = data["games"]
                elo = data["elo"]
                elo_str = f"^3{elo:^4}^7" if elo != "—" else "^1—^7"
                msg = f"^5{name}^7 => Tracked games: ^2{games}^7, FFA ELO: {elo_str}"
            self.chat_reply(msg)

        fetch()

    def chat_reply(self, message, **format_kwargs):
        if isinstance(message, (list, tuple)):
            lines = message
        else:
            lines = str(message).splitlines()

        for line in lines:
            minqlx.CHAT_CHANNEL.reply(line.format(**format_kwargs))

    def center_print(self, player, message, **format_kwargs):
        if isinstance(message, (list, tuple)):
            lines = message
        else:
            lines = str(message).splitlines()

        player.center_print("\n".join(line.format(**format_kwargs) for line in lines))

    @minqlx.delay(2)
    def delayed_center_print(self, player, message, **format_kwargs):
        self.center_print(player, message, **format_kwargs)

    def get_ffa_data(self, steam_id):
        try:
            r = requests.get(f"http://qlstats.net/elo/{steam_id}", timeout=6)
            if r.status_code != 200:
                return None
            player = r.json().get("players", [{}])[0]
            ffa = player.get("ffa", {})
            return {"games": ffa.get("games", 0), "elo": ffa.get("elo", "—")}
        except Exception:
            return None
