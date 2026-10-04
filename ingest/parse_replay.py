#!/usr/bin/env python3
"""Turn one .SC2Replay into the OData V4 deep-create body for ZSD_SCE / Game.

Usage: parse_replay.py <replay.SC2Replay> [payload.json]
"""
import csv
import hashlib
import json
import sys
import uuid
from collections import Counter
from pathlib import Path

import sc2reader

LOOPS_PER_SECOND = 22.4                      # LotV "Faster"; sc2reader's .second uses 16
STATS_INTERVAL_SECONDS = 160 / LOOPS_PER_SECOND   # PlayerStatsEvent every 160 loops
TOWN_HALLS = {"CommandCenter", "Nexus", "Hatchery"}
COMPANY = {"Terran": "1000", "Zerg": "2000", "Protoss": "3000"}
SIGN = {"101": 1, "501": 1, "561": 1, "262": 1, "261": -1, "551": -1}
HERE = Path(__file__).parent


def load_materials(path=HERE / "materials.csv"):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        for k in ("mineral_cost", "gas_cost", "supply_cost", "supply_provided", "build_seconds"):
            r[k] = int(r[k])
    return {r["matnr"]: r for r in rows}


def new_id():
    return str(uuid.uuid4())


def seconds(frame):
    return int(frame / LOOPS_PER_SECOND)


def clean(row):
    return {k: v for k, v in row.items() if v is not None}


class Division:
    def __init__(self, player, materials, skipped):
        self.uuid = new_id()
        self.materials = materials
        self.skipped = skipped   # Counter shared across divisions: unit/upgrade names not in materials.csv
        self.row = {
            "DivisionUUID": self.uuid,
            "CompanyCode": COMPANY[player.play_race],
            "DivisionCode": f"P{player.pid}",
            "PlayerName": player.name[:40],
            "GameResult": (player.result or "UNKNOWN").upper(),
        }
        self.plants, self.orders, self.events = [], [], []
        self.plant_by_tag = {}
        self.opening_posted = False

    # --- plants -------------------------------------------------------
    def nearest_plant(self, x, y):
        # ponytail: nearest open town hall by distance; no ownership or range check
        open_plants = [p for p in self.plants if p["ClosedAt"] is None]
        if not open_plants:
            return None
        return min(open_plants, key=lambda p: (p["PosX"] - x) ** 2 + (p["PosY"] - y) ** 2)["PlantUUID"]

    def found_plant(self, x, y, at, tag):
        plant = {"PlantUUID": new_id(), "PlantCode": f"{len(self.plants) + 1:04d}",
                 "PosX": x, "PosY": y, "FoundedAt": at, "ClosedAt": None}
        self.plants.append(plant)
        self.plant_by_tag[tag] = plant
        return plant["PlantUUID"]

    # --- ledger -------------------------------------------------------
    def post(self, mvt, matnr, qty, at, plant=None, order=None, tag=0):
        mat = self.materials[matnr]
        self.events.append({
            "EventUUID": new_id(), "PlantUUID": plant, "OrderUUID": order,
            "GameSeconds": at, "MovementType": mvt, "Material": matnr, "Quantity": qty,
            "MineralValue": qty * mat["mineral_cost"], "GasValue": qty * mat["gas_cost"],
            "EventSource": "REPLAY", "UnitTag": tag,
        })

    def opening_balance(self, stats):
        self.opening_posted = True
        at = seconds(stats.frame)
        if stats.minerals_current:
            self.post("561", "MINERAL", stats.minerals_current, at)
        if stats.vespene_current:
            self.post("561", "VESPENE", stats.vespene_current, at)

    def mine(self, stats):
        # ponytail: income = collection rate/min × stats interval, booked at division level
        at = seconds(stats.frame)
        for matnr, rate in (("MINERAL", stats.minerals_collection_rate),
                            ("VESPENE", stats.vespene_collection_rate)):
            qty = round(rate * STATS_INTERVAL_SECONDS / 60)
            if qty:
                self.post("501", matnr, qty, at)

    def produce(self, matnr, done_at, x, y, tag, initial=False):
        # Returns the plant it used (or None), so callers can remember a unit's birth plant for scrap().
        mat = self.materials.get(matnr)
        if mat is None:
            self.skipped[matnr] += 1
            return None
        plant = self.nearest_plant(x, y) if x is not None else None
        if matnr in TOWN_HALLS:
            plant = self.found_plant(x, y, done_at, tag)
        if initial:
            self.post("561", matnr, 1, done_at, plant, tag=tag)
            return plant
        order = new_id()
        released = max(0, done_at - mat["build_seconds"])   # ponytail: back-computed release
        self.orders.append({"OrderUUID": order, "PlantUUID": plant, "Material": matnr,
                            "Quantity": 1, "OrderStatus": "CONFIRMED",
                            "ReleasedAt": released, "ConfirmedAt": done_at, "UnitTag": tag})
        # Raw materials are booked at division level (plant=None): only the 101 below,
        # and the order itself, carry the plant. Keeps per-plant raw-material balances from
        # going negative when a unit is trained off minerals mined division-wide.
        if mat["mineral_cost"]:
            self.post("261", "MINERAL", mat["mineral_cost"], released, plant=None, order=order, tag=tag)
        if mat["gas_cost"]:
            self.post("261", "VESPENE", mat["gas_cost"], released, plant=None, order=order, tag=tag)
        self.post("101", matnr, 1, done_at, plant, order, tag)
        return plant

    def scrap(self, matnr, at, plant, tag):
        # `plant` is the unit's birth plant (recorded by produce(), see units dict in parse()),
        # not nearest_plant() at the death position: a unit can die far from where it was built.
        if matnr not in self.materials:
            self.skipped[matnr] += 1
            return
        self.post("551", matnr, 1, at, plant, tag=tag)
        if tag in self.plant_by_tag:
            self.plant_by_tag[tag]["ClosedAt"] = at

    def payload(self):
        return {**self.row,
                "_Plant": [clean(p) for p in self.plants],
                "_ProdOrder": [clean(o) for o in self.orders],
                "_Event": [clean(e) for e in self.events]}


def parse(path, materials=None):
    materials = materials or load_materials()
    path = Path(path)
    replay = sc2reader.load_replay(str(path), load_level=4)
    skipped = Counter()   # unit_type_name/upgrade_type_name not in materials.csv; exposed below
    divisions = {p.pid: Division(p, materials, skipped) for p in replay.players}
    units = {}   # unit_id -> (pid, type_name, x, y, plant_uuid); plant_uuid filled by produce()

    for e in replay.tracker_events:
        at = seconds(e.frame)
        if e.name == "PlayerStatsEvent" and e.pid in divisions:
            d = divisions[e.pid]
            d.mine(e) if d.opening_posted else d.opening_balance(e)
        elif e.name == "UnitBornEvent" and e.control_pid in divisions:
            # ponytail: starting units are born on frame 0; the first PlayerStatsEvent is frame 1
            plant = divisions[e.control_pid].produce(e.unit_type_name, at, e.x, e.y, e.unit_id,
                                                      initial=(e.frame == 0))
            units[e.unit_id] = (e.control_pid, e.unit_type_name, e.x, e.y, plant)
        elif e.name == "UnitInitEvent" and e.control_pid in divisions:
            units[e.unit_id] = (e.control_pid, e.unit_type_name, e.x, e.y, None)   # plant filled at UnitDoneEvent
        elif e.name == "UnitDoneEvent" and e.unit_id in units:
            pid, t, x, y, _ = units[e.unit_id]
            plant = divisions[pid].produce(t, at, x, y, e.unit_id)
            units[e.unit_id] = (pid, t, x, y, plant)
        elif e.name == "UnitDiedEvent" and e.unit_id in units:
            pid, t, _, _, plant = units[e.unit_id]
            divisions[pid].scrap(t, at, plant, e.unit_id)
        elif e.name == "UpgradeCompleteEvent" and e.pid in divisions:
            divisions[e.pid].produce(e.upgrade_type_name, at, None, None, 0)

    winners = [divisions[p.pid].uuid for p in replay.players if p.result == "Win"]
    result = clean({
        "GameUUID": new_id(),
        "ReplayHash": hashlib.sha1(path.read_bytes()).hexdigest(),
        "MapName": replay.map_name[:80],
        "PlayedAt": replay.date.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "DurationSeconds": seconds(replay.frames),
        "WinnerDivisionUUID": winners[0] if winners else None,
        "_Division": [d.payload() for d in divisions.values()],
    })
    parse.last_skipped = skipped   # dropped-material visibility: what produce()/scrap() skipped, and how often
    return result


def stock(payload):
    """Local stock balance per (division, plant or '', material); mirrors ZI_SCEStockBalance."""
    bal = {}
    for d in payload["_Division"]:
        for e in d["_Event"]:
            key = (d["DivisionUUID"], e.get("PlantUUID", ""), e["Material"])
            bal[key] = bal.get(key, 0) + SIGN[e["MovementType"]] * e["Quantity"]
    return bal


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    body = parse(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("payload.json")
    out.write_text(json.dumps(body, indent=1))
    print(f"{out}: {len(body['_Division'])} divisions, "
          f"{sum(len(d['_Event']) for d in body['_Division'])} events")
    if parse.last_skipped:
        top = ", ".join(f"{name}×{n}" for name, n in parse.last_skipped.most_common())
        print(f"skipped (not in materials.csv): {top}")
