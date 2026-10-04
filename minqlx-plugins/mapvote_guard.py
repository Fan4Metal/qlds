"""
This is a plugin for minqlx created by Metal Fan (fan4_metal@mail.ru)
Copyright (c) 2026 Metal Fan

Version 0.1

Blocks map-changing votes (callvote map / nextmap) for a short time after a map
is loaded. A map vote that passes while players are still reconnecting after
the previous map change crashes qzeroded with a segfault inside qagame
(seen 7 times on FFA, 2026-09-22 .. 2026-10-04), which kicks everyone.

Cvars:
    qlx_mapVoteGuardDelay - seconds after map load during which map votes
                            are rejected. 0 disables the plugin. Default: 30
"""

import time

import minqlx

GUARDED_VOTES = ("map", "nextmap")


class mapvote_guard(minqlx.Plugin):
    def __init__(self):
        self.set_cvar_once("qlx_mapVoteGuardDelay", "30")

        self.add_hook("map", self.handle_map)
        self.add_hook("vote_called", self.handle_vote_called)

        # The plugin may be (re)loaded mid-map; count from now to be safe.
        self.map_loaded_at = time.monotonic()

    def handle_map(self, mapname, factory):
        self.map_loaded_at = time.monotonic()

    def handle_vote_called(self, caller, vote, args):
        if vote.lower() not in GUARDED_VOTES:
            return

        delay = self.get_cvar("qlx_mapVoteGuardDelay", int)
        remaining = delay - (time.monotonic() - self.map_loaded_at)
        if remaining > 0:
            caller.tell("^7Map votes are allowed {}s after the map loads. Try again in ^3{}^7s."
                        .format(delay, int(remaining) + 1))
            return minqlx.RET_STOP_ALL
