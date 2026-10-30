#!/usr/bin/env python3
"""Version check: compare materials.csv (Terran + Protoss) with the installed StarCraft II build.

One-shot python-sc2 game (realtime=False); on_start reads self.game_data and the tech dicts, prints
the SC2 build and one line per mismatch, then leaves the game. Exit 1 if any mismatch is left.
Run it after every SC2 patch:  .venv/bin/python ingest/check_materials.py
"""
import sys
from pathlib import Path

from s2clientprotocol import sc2api_pb2 as sc_pb
from sc2 import maps
from sc2.bot_ai import BotAI
from sc2.data import Difficulty, Race
from sc2.dicts.unit_research_abilities import RESEARCH_INFO
from sc2.dicts.unit_train_build_abilities import TRAIN_INFO
from sc2.dicts.unit_trained_from import UNIT_TRAINED_FROM
from sc2.dicts.upgrade_researched_from import UPGRADE_RESEARCHED_FROM
from sc2.ids.unit_typeid import UnitTypeId
from sc2.ids.upgrade_id import UpgradeId
from sc2.main import run_game
from sc2.paths import Paths
from sc2.player import Bot, Computer

from parse_replay import LOOPS_PER_SECOND, load_materials

# (matnr, field): (csv value, game value, reason). Suppressed only when both values match exactly.
EXPECTED_DIFF = {
    ("Archon", "mineral_cost"): (0, 175, "morph: game data reports a Templar's cost, the CSV has the free merge"),
    ("Archon", "gas_cost"): (0, 275, "morph: game data reports a Templar's cost, the CSV has the free merge"),
    ("Archon", "build_seconds"): (9, 0, "morph: game data reports no build time, the CSV has the 9 s merge"),
    ("WarpGate", "mineral_cost"): (0, 150, "morph: game data reports the Gateway cost, the CSV has the free morph"),
    ("WarpGate", "build_seconds"): (7, 4, "morph: game data reports 4 s, the CSV has the 7 s transform"),
    ("TechLab", "build_seconds"): (18, 0, "generic add-on placeholder: game data reports no build time"),
    ("Reactor", "build_seconds"): (36, 0, "generic add-on placeholder: game data reports no build time"),
}
ADDONS = ("TechLab", "Reactor")   # not in python-sc2's trained-from / train-info dicts: producer checked by name


def build_info():
    versions = sorted(p.name for p in (Paths.BASE / "Versions").glob("Base*"))
    return f"{Paths.BASE / 'Versions'} -> {', '.join(versions)}"


class CheckBot(BotAI):
    mismatches: list[str] | None = None      # None: on_start never finished

    async def on_step(self, iteration):
        pass

    async def on_start(self):
        ping = (await self.client._execute(ping=sc_pb.RequestPing())).ping
        print(f"SC2 build: {build_info()}  (game_version {ping.game_version}, base_build {ping.base_build})")
        CheckBot.mismatches = self.compare(load_materials())
        for line in CheckBot.mismatches:
            print("MISMATCH", line)
        print(f"{len(CheckBot.mismatches)} mismatch(es)")
        await self.client.leave()

    def compare(self, materials):
        out = []
        by_upper = {m.upper(): m for m in materials}

        def diff(matnr, field, csv, game):
            if csv != game and EXPECTED_DIFF.get((matnr, field), (None, None))[:2] != (csv, game):
                out.append(f"{matnr}.{field}: csv {csv!r} != game {game!r}")

        def name(unit):                       # tech-dict id -> csv matnr ('' if it has none)
            return by_upper.get(unit.name, f"?{unit.name}")

        for r in materials.values():
            if r["bukrs"] not in ("1000", "3000"):
                continue                      # Zerg is not part of the match
            m, upgrade = r["matnr"], r["category"] == "UPGRADE"
            if upgrade:
                uid = UpgradeId[m.upper()]
                data, producers = self.game_data.upgrades[uid.value], {UPGRADE_RESEARCHED_FROM.get(uid)}
                supply = (0, 0)
                time = data.cost.time
                needs = {RESEARCH_INFO.get(p, {}).get(uid, {}).get("required_building") for p in producers}
                info = {}
            else:
                uid = UnitTypeId[m.upper()]
                data, producers = self.game_data.units[uid.value], UNIT_TRAINED_FROM.get(uid, set())
                supply = (data._proto.food_required, data._proto.food_provided)
                time = data.cost.time
                needs, info = None, {}
            cost = data.cost
            diff(m, "mineral_cost", r["mineral_cost"], cost.minerals)
            diff(m, "gas_cost", r["gas_cost"], cost.vespene)
            diff(m, "supply_cost", r["supply_cost"], int(supply[0]))
            diff(m, "supply_provided", r["supply_provided"], int(supply[1]))
            diff(m, "build_seconds", r["build_seconds"], int((time or 0) / LOOPS_PER_SECOND + 0.5))
            if r["order_blocked"]:
                continue                      # blocked rows are never ordered: tech data not checked
            if m.endswith(ADDONS):            # BarracksTechLab <- Barracks; generic TechLab / Reactor stand alone
                if not any(m in (r["produced_by"] + a, a) for a in ADDONS):
                    out.append(f"{m}.produced_by: csv {r['produced_by']!r} is not the add-on's building")
                continue
            if r["produced_by"] not in {name(p) for p in producers if p}:
                out.append(f"{m}.produced_by: csv {r['produced_by']!r} not in game {sorted(p.name for p in producers if p)}")
                continue
            if needs is None:
                prod_id = UnitTypeId[r["produced_by"].upper()]
                info = TRAIN_INFO.get(prod_id, {}).get(uid, {})
                needs = {info.get("required_building")}
            expected = {name(n) for n in needs if n}
            if info.get("requires_techlab"):  # Marauder, Cyclone ...: needs the producer's own add-on
                expected.add(r["produced_by"] + "TechLab")
            if r["prerequisite"] != "" and r["prerequisite"] not in expected or r["prerequisite"] == "" and expected:
                out.append(f"{m}.prerequisite: csv {r['prerequisite']!r} != game {sorted(expected)}")
        return out


def main():
    try:
        run_game(maps.get("AcropolisLE"),
                 [Bot(Race.Protoss, CheckBot()), Computer(Race.Terran, Difficulty.VeryEasy)],
                 realtime=False)
    except Exception as e:                    # python-sc2 often raises when the game is left on purpose
        print(f"(python-sc2 ended with {e!r})")
    sys.exit(1 if CheckBot.mismatches is None or CheckBot.mismatches else 0)


if __name__ == "__main__":
    main()
