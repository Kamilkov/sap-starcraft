#!/usr/bin/env python3
"""SAP-driven StarCraft II outpost: polls RELEASED (and CANCELLING) production orders from ZSD_SCE, builds them
with python-sc2 (Terran vs the built-in Zerg AI) and posts LIVE goods movements as they happen.
Plant Maintenance (spec 2026-09-27): damaged structures raise notifications, an SCV executes the repair orders
created in Fiori, and the exact repair cost is posted as 261 on the maintenance order.

  live_bot.py [--minutes 20] [--map AcropolisLE] [--difficulty VeryEasy]

Release orders with the "Release Order" action on the LIVE division's Fiori page. The replay is
saved to replays/<GameUUID>.SC2Replay when the game ends.
"""
import argparse
import asyncio
import hashlib
import math
import queue
import re
import subprocess
import sys
import threading
import time
from collections import Counter, defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path

from sc2.ids.unit_typeid import UnitTypeId
from sc2.ids.upgrade_id import UpgradeId
from sc2.ids.ability_id import AbilityId

from parse_replay import LOOPS_PER_SECOND, STATS_INTERVAL_SECONDS, clean, load_materials, new_id

HERE = Path(__file__).parent
MATERIALS = load_materials()
MATNR_BY_NAME = {m.upper(): m for m in MATERIALS}          # UnitTypeId.MARINE.name -> "Marine"
ADDON_PARENT = {"BarracksTechLab": "Barracks", "BarracksReactor": "Barracks",
                "TechLab": "Barracks", "Reactor": "Barracks",
                "FactoryTechLab": "Factory", "FactoryReactor": "Factory",
                "StarportTechLab": "Starport", "StarportReactor": "Starport"}
RESULT_NAMES = {"Victory": "WIN", "Defeat": "LOSS", "Tie": "TIE"}   # sc2reader spelling, as Phase A stores it
POLL_SECONDS = 5
QUEUE_LIMIT = 5         # SC2 production queue slots per structure (a Reactor allows more; 5 is always safe)
BACKLOG_LOOPS = 11      # retry waiting orders every ~0.5 game s instead of once per 5 s SAP poll
IDLE_CHECK_LOOPS = 22   # look for idle SCVs about once per game second
GAS_TRIM_WAIT_LOOPS = 110    # ~5 s between two trims of one refinery: the game's harvester count lags
LOCK_RETRIES, LOCK_WAIT = 5, 0.5   # HTTP 423: the Game-wide lock is held by a Fiori action for a moment
MINING_TICKS_PER_POST = 4      # one 501 pair per ~28 s instead of four: fewer Game-lock collisions
STUCK_CHECK_LOOPS = 112        # ~5 game s; a unit order missing from every queue on two checks in a row was refused
REPAIR_GRACE_LOOPS = 22        # ~1 game s: a repair order shows in the next observation (spike 2026-09-27, 18 of 18)
REPAIR_STALL_LOOPS = 672       # 30 game s: no progress after the command, and the wait before an unreachable target is retried
REPAIR_IDS = {AbilityId.EFFECT_REPAIR, AbilityId.EFFECT_REPAIR_SCV}   # order id and exact id of a repair (spike)
ACTION = "com.sap.gateway.srvd.zsd_sce.v0001."     # namespace of the bound actions of ZSD_SCE
FINAL = ("CONFIRMED", "CANCELLED")
ZERO_GUID = "00000000-0000-0000-0000-000000000000"


def item_id(matnr):
    """python-sc2 id for a material number; None for raw materials and unknown names."""
    if matnr not in MATERIALS:
        return None
    key = matnr.upper()
    if key in UnitTypeId.__members__:
        return UnitTypeId[key]
    if key in UpgradeId.__members__:
        return UpgradeId[key]
    return None


def is_structure(matnr):
    return MATERIALS.get(matnr, {}).get("category") == "STRUCTURE"


def game_matnr(matnr):
    """The material as the game builds it: a TechLab/Reactor order completes as BarracksTechLab/BarracksReactor."""
    return "Barracks" + matnr if matnr in ("TechLab", "Reactor") else matnr


def refund(minerals, gas, partial):
    """What SC2 gives back for a cancel (spike 2026-09-24): 75% rounded up for a building under construction, else all."""
    return (minerals - minerals // 4, gas - gas // 4) if partial else (minerals, gas)


def values(matnr, cost, qty):
    """(MineralValue, GasValue) of a movement; raw materials are worth themselves, as in the parser."""
    if matnr == "MINERAL":
        return qty, 0
    if matnr == "VESPENE":
        return 0, qty
    return cost.minerals * qty, cost.vespene * qty


def mining_qty(rate_per_minute):
    return round(rate_per_minute * STATS_INTERVAL_SECONDS / 60)


def event(mvt, matnr, qty, at, value, plant=None, order=None, tag=0):
    return clean({"EventUUID": new_id(), "PlantUUID": plant, "OrderUUID": order,
                  "GameSeconds": at, "MovementType": mvt, "Material": matnr, "Quantity": qty,
                  "MineralValue": value[0], "GasValue": value[1],
                  "EventSource": "LIVE", "UnitTag": tag})


def new_plant(number, pos, at):
    return {"PlantUUID": new_id(), "PlantCode": f"{number:04d}",
            "PosX": int(pos.x) if pos else 0, "PosY": int(pos.y) if pos else 0,
            "FoundedAt": at, "ClosedAt": None}


def game_payload(game_uuid, division_uuid, map_name, plant):
    return {"GameUUID": game_uuid,
            "ReplayHash": hashlib.sha1(f"live:{game_uuid}".encode()).hexdigest(),
            "MapName": map_name[:80],
            "PlayedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "DurationSeconds": 0,
            "_Division": [{"DivisionUUID": division_uuid, "CompanyCode": "1000",
                           "DivisionCode": "LIVE", "PlayerName": "SAP Outpost",
                           "GameResult": "UNKNOWN",
                           "_Plant": [clean(plant)], "_ProdOrder": [], "_Event": []}]}


class Inflight:
    """Orders whose command was issued, per material, oldest first; popped when the unit appears."""

    def __init__(self):
        self.by_matnr = defaultdict(deque)

    def add(self, matnr, order_uuid):
        self.by_matnr[matnr].append(order_uuid)

    def pop(self, matnr):
        pending = self.by_matnr.get(matnr)
        return pending.popleft() if pending else None

    def pending(self, matnr):
        return len(self.by_matnr.get(matnr, ()))

    def drop_newest(self, matnr, n):
        """Remove and return the n most recent orders of a material, newest first: SC2 refuses the latest command."""
        pending = self.by_matnr.get(matnr, deque())
        return [pending.pop() for _ in range(min(n, len(pending)))]


def unit_excess(pending, queued):
    """Unit orders STARTED beyond what the producers really queue, per material: SC2 refused them silently."""
    return {m: n - queued.get(m, 0) for m, n in pending.items()
            if MATERIALS.get(m, {}).get("category") == "UNIT" and n > queued.get(m, 0)}


def pick_last(structures, ability, busy):
    """Where to CANCEL_LAST one `ability` order: (structure, "") or (None, why); why "" = candidates busy this frame.

    Only the last queue item can be cancelled over the raw API (CANCELSLOT does nothing, spike 2026-09-24); a
    structure with more orders is preferred, so the one in progress keeps its progress.
    """
    last = [s for s in structures if s.orders and s.orders[-1].ability.exact_id == ability]
    free = [s for s in last if s.tag not in busy]
    if free:
        return max(free, key=lambda s: len(s.orders)), ""
    if last:
        return None, ""
    if any(o.ability.exact_id == ability for s in structures for o in s.orders):
        return None, "not last in any queue"
    return None, "not found in the game"


def priority(health, health_max):
    """Priority of a notification: 1 below a third of the health (the structure burns), 2 below two thirds, else 3."""
    return "1" if health * 3 < health_max else "2" if health * 3 < health_max * 2 else "3"


def measure(opening, common, score):
    """The exact measure R per resource: opening bank + collected - spent - bank, all of one observation.

    Only a repair moves it (spike 2026-09-27: 75 control cases with no change), so its change over a repair
    segment is that segment's cost. Read from state.common, not from BotAI.minerals, which commands reduce.
    """
    return (opening[0] + round(score.collected_minerals) - round(score.spent_minerals) - common.minerals,
            opening[1] + round(score.collected_vespene) - round(score.spent_vespene) - common.vespene)


def holds_repair(unit, target):
    """The SCV holds a repair order on this target. Full health of the target is no end: only the order's absence is."""
    return any(o.ability.exact_id in REPAIR_IDS and o.target == target for o in unit.orders)


def free_workers(workers, reserved, busy):
    """SCVs a selector may take: not reserved for a repair and without a command in this frame, compared by tag."""
    return [w for w in workers if w.tag not in reserved and w.tag not in busy]


def is_final(fact):
    body = fact["body"]
    return body.get("OrderStatus") in FINAL or body.get("NotificationStatus") == "CLOSED"


def norm(value):
    """A value as the identity read compares it: nothing, 0 and the empty GUID are one; numbers by value."""
    if value in (None, "", 0, ZERO_GUID):
        return ""
    try:
        return int(value)
    except (TypeError, ValueError):
        return str(value).lower()


def sap_message(text):
    """The message of an OData error answer, else the first 200 characters of what came."""
    found = re.search(r'"message"\s*:\s*"([^"]*)"', text)
    return found.group(1) if found else text[:200]


IDENTITY = {"create": ("UnitTag", "Material", "ReportedAt"),
            "event": ("OrderUUID", "MovementType", "Material", "Quantity", "MineralValue", "GasValue", "GameSeconds",
                      "UnitTag", "EventSource", "PlantUUID")}
PM_SETS = {"event": ("Event", "EventUUID"), "create": ("Notification", "NotificationUUID"),
           "notify": ("Notification", "NotificationUUID"), "repair": ("MaintOrder", "OrderUUID")}


class PmOutbox:
    """PM facts on their way to SAP: acknowledged or sent again, never waited for by the game (spec 2026-09-27).

    The game thread puts facts into `inbox` and reads `acks`; everything else runs on the SAP worker thread.
    A fact is {"kind": event | create | notify | repair, "key": uuid, "gen": n, "body": {...}}; key and body are
    made when the game decides the fact, so a retry sends the same UUID and the same body.
    ponytail: in memory, durable for this run only; a restart adopts nothing (spec, out of scope).
    """

    def __init__(self, sap, division_uuid):
        self.sap, self.division_uuid = sap, division_uuid
        self.inbox, self.acks = queue.Queue(), queue.Queue()
        self.events = []        # accounting lane: repair cost in the order it was made, waits for no status
        self.slots = {}         # notification or order uuid -> {"create": fact, "report": fact}: the latest only
        self.parked = []        # rejected by SAP or in conflict with what SAP holds: never sent again, counted
        self.adopted = {}       # proposed notification uuid -> the uuid of the open notification SAP holds instead
        self.shown = set()      # pending reasons already printed

    def take(self):
        """Move the game's new facts into the lanes. A newer report replaces an unsent older one, but a pending
        close stays: it takes the newer generation, so its answer counts for the latest state."""
        while True:
            try:
                fact = self.inbox.get_nowait()
            except queue.Empty:
                return
            if fact["kind"] == "event":
                self.events.append(fact)
                continue
            fact["key"] = self.adopted.get(fact["key"], fact["key"])    # made before the game knew of the adoption
            slot = self.slots.setdefault(fact["key"], {})
            part = "create" if fact["kind"] == "create" else "report"
            held = slot.get(part)
            if part == "report" and held and is_final(held):
                held["gen"] = fact["gen"]
            else:
                slot[part] = fact

    def unacknowledged(self):
        return self.inbox.qsize() + len(self.events) + sum(len(slot) for slot in self.slots.values())

    def pump(self, retry):
        """Send what is new, with retry also what failed before. Ends at the first call SAP did not answer."""
        self.take()
        for fact in list(self.events):
            if (retry or not fact.get("tried")) and not self.deliver(fact):
                return
        for key, slot in list(self.slots.items()):
            for part in ("create", "report"):
                fact = slot.get(part)
                if fact and (retry or not fact.get("tried")) and not self.deliver(fact):
                    return
                if slot.get(part):
                    break       # a report waits for the create of its notification
        self.slots = {key: slot for key, slot in self.slots.items() if slot}

    def deliver(self, fact):
        """One attempt. False = SAP did not answer; the fact stays and the round ends."""
        fact["tried"] = True
        outcome, row = self.send(fact)
        if outcome == "away":
            self.show(f"PM not answered, sent again: {row}")
            return False
        if outcome == "pending":
            self.show(f"PM pending, sent again at each poll: {row}")
            return True
        if fact["kind"] == "event":
            self.events.remove(fact)
        else:
            slot = self.slots[fact["key"]]
            part = "create" if fact["kind"] == "create" else "report"
            if outcome in ("rejected", "conflict"):
                slot.clear()    # the report of a notification that SAP does not hold goes with it
            else:
                del slot[part]
            if outcome == "adopt":      # SAP never held the proposed uuid: its waiting report goes to the adopted one
                uuid = self.adopted[fact["key"]] = row["NotificationUUID"]
                for waiting in slot.values():
                    waiting["key"] = uuid
                self.slots[uuid] = self.slots.pop(fact["key"])
        if outcome in ("rejected", "conflict"):
            self.parked.append((fact, outcome, row))
            print(f"PM {outcome}, not sent again: {fact['kind']} {fact['key']}: {row}")
        self.acks.put(("fact", fact, outcome, row))
        return True

    def show(self, text):
        if text not in self.shown:
            self.shown.add(text)
            print(text)

    def post(self, path, body):
        for attempt in range(LOCK_RETRIES + 1):
            try:
                return self.sap.post(path, body)
            except Exception as e:
                if getattr(e, "status", None) != 423 or attempt == LOCK_RETRIES:
                    raise
            time.sleep(LOCK_WAIT)

    def read(self, kind, key):
        entity, field = PM_SETS[kind]
        rows = self.sap.get(f"{entity}?$filter={field} eq {key}")
        return rows[0] if rows else None

    def send(self, fact):
        """(outcome, SAP's row or its answer): ack, noop (SAP held a final status, nothing was written), refused
        (a repair report, with SAP's current row), adopt, rejected, conflict, pending (a receipt is missing),
        away (no answer)."""
        kind, key, body = fact["kind"], fact["key"], fact["body"]
        division = f"Division({self.division_uuid})/"
        path = {"event": division + "_Event", "create": division + "_Notification",
                "notify": f"Notification({key})/{ACTION}reportNotification",
                "repair": f"MaintOrder({key})/{ACTION}reportRepair"}[kind]
        status = text = None
        try:
            row = self.post(path, body)
            if kind in ("notify", "repair") and not row:
                row = self.read(kind, key)      # HTTP 2xx says nothing: the row does
        except Exception as e:                  # SapError, timeout, connection lost
            status, text = getattr(e, "status", 0), str(e)
        if status is None:
            if kind == "repair" and row and not self.applied(body, row):
                return "noop", row
            return "ack", row
        definitive = 400 <= status < 500 and status != 423     # SAP said no; anything else, nobody knows
        text = sap_message(text)
        if definitive and re.search(r"(Equipment|SCV) \d+ unknown", text):
            # the receipt of the equipment or of the SCV lags, or production dropped it: visible, never given up
            return "pending", text
        try:
            if kind in ("notify", "repair"):
                if not definitive:
                    return "away", text         # a report is repeatable: the same one goes again
                current = self.read(kind, key) if kind == "repair" else None
                return ("refused", current) if current else ("rejected", text)
            if kind == "create" and definitive and "Open notification exists" in text:
                held = self.sap.get(f"Notification?$filter=DivisionUUID eq {self.division_uuid} and UnitTag eq "
                                    f"{body['UnitTag']} and NotificationStatus ne 'CLOSED'")
                if held:
                    same = norm(held[0]["NotificationUUID"]) == norm(key)
                    return ("ack" if same else "adopt"), held[0]
            found = self.read(kind, key)
        except Exception as e:
            return "away", sap_message(str(e))
        if found:
            same = norm(found.get("DivisionUUID")) == norm(self.division_uuid) and all(
                norm(found.get(f)) == norm(body.get(f)) for f in IDENTITY[kind])
            return ("ack" if same else "conflict"), found
        return ("rejected" if definitive else "away"), text

    @staticmethod
    def applied(body, row):
        """SAP's order row is what this report says. A final status reported again answers 2xx without writing."""
        return (row["OrderStatus"] == body["OrderStatus"] and row["StatusText"] == body["StatusText"]
                and (body["OrderStatus"] != "CONFIRMED" or row["ConfirmedAt"] == body["AtSeconds"]))

    def poll(self):
        """Maintenance orders in RELEASED and CANCELLING, every page the service makes of them (its nextLink is
        followed); handed to the game with the answers. Rows can move between two pages, so an order missing here
        is not proven gone: take_repairs only parks it."""
        rows = self.sap.get_all(f"MaintOrder?$filter=DivisionUUID eq {self.division_uuid} and (OrderStatus eq "
                                f"'RELEASED' or OrderStatus eq 'CANCELLING')&$orderby=OrderUUID")
        self.acks.put(("poll", rows))


class SapWorker(threading.Thread):
    """Runs every SAP call off the game thread, FIFO; polls RELEASED and CANCELLING orders every poll_seconds."""

    def __init__(self, sap, division_uuid, poll_seconds=POLL_SECONDS):
        super().__init__(daemon=True, name="sap")
        self.sap, self.division_uuid, self.poll_seconds = sap, division_uuid, poll_seconds
        self.q = queue.Queue()
        self.released, self.lock = None, threading.Lock()
        self.stopping = threading.Event()
        self.failed = 0
        self.pm = PmOutbox(sap, division_uuid)

    def run(self):
        next_poll = 0
        while not (self.stopping.is_set() and self.q.empty() and not self.pm.unacknowledged()):
            try:
                job = self.q.get(timeout=0.2)
            except queue.Empty:
                job = None
            if job:
                self.call(job)
            self.pump(retry=False)
            if time.monotonic() >= next_poll:
                if not self.stopping.is_set():
                    self.call(self.poll)
                    self.call(self.pm.poll)
                self.pump(retry=True)           # also while draining, inside the drain's time
                next_poll = time.monotonic() + self.poll_seconds

    def pump(self, retry):
        try:
            self.pm.pump(retry)
        except Exception as e:                  # a PM fault must not end the thread production posts through
            print(f"PM: {e!r}")

    def call(self, job):
        for attempt in range(LOCK_RETRIES + 1):
            try:
                return job()
            except Exception as e:
                err = e
            if getattr(err, "status", None) != 423 or attempt == LOCK_RETRIES:
                break
            time.sleep(LOCK_WAIT)          # worker thread only; the game thread never waits
        self.failed += 1                   # ponytail: log and drop; the next poll re-reads truth from SAP
        print(f"SAP: {err}")

    def poll(self):
        rows = self.sap.get(f"ProdOrder?$filter=DivisionUUID eq {self.division_uuid} "
                            f"and (OrderStatus eq 'RELEASED' or OrderStatus eq 'CANCELLING')&$top=100")
        with self.lock:
            self.released = rows

    def take_released(self):
        """The latest polled orders (RELEASED and CANCELLING), or None when no poll finished since the last call."""
        with self.lock:
            rows, self.released = self.released, None
        return rows

    def drain(self, timeout=60):
        self.stopping.set()
        self.join(timeout)
        if self.is_alive():
            print(f"SAP: drain timed out, {self.q.qsize()} calls dropped, PM unacknowledged {self.pm.unacknowledged()}")

def stop_sc2(proc, grace=3):
    """Close the StarCraft II process this bot launched if it outlived the game.

    python-sc2 skips its quit command when it errors at game end (defeat: game-loop overflow,
    surrender: replay save), and its own cleanup only sends SIGTERM for 1.5 s without ever killing,
    so the macOS client stays open as a black window.
    """
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    print("closed the StarCraft II window python-sc2 left open")


# --- the bot (needs a running SC2; everything above is testable without one) -------------------
from sc2 import maps                              # noqa: E402
from sc2.bot_ai import BotAI                      # noqa: E402
from sc2.data import Difficulty, Race, Result     # noqa: E402
from sc2.main import run_game                     # noqa: E402
from sc2.protocol import ProtocolError            # noqa: E402
from sc2.player import Bot, Computer              # noqa: E402
from sc2.position import Point2                   # noqa: E402
from sc2.sc2process import KillSwitch             # noqa: E402
from sc2.dicts.unit_train_build_abilities import TRAIN_INFO   # noqa: E402
from sc2.dicts.unit_trained_from import UNIT_TRAINED_FROM     # noqa: E402
from sc2.constants import TERRAN_TECH_REQUIREMENT             # noqa: E402
from sc2.dicts.unit_research_abilities import RESEARCH_INFO   # noqa: E402

TRAIN_ABILITIES = {t: {info["ability"] for u, info in TRAIN_INFO[t].items()
                       if MATERIALS.get(MATNR_BY_NAME.get(u.name, ""), {}).get("category") == "UNIT"}
                   for t in TRAIN_INFO}   # unit trains only: addon builds, CC morphs and lift-offs are not in it
UNIT_BY_ABILITY = {info["ability"]: MATNR_BY_NAME[u.name] for t in TRAIN_INFO for u, info in TRAIN_INFO[t].items()
                   if MATERIALS.get(MATNR_BY_NAME.get(u.name, ""), {}).get("category") == "UNIT"}
ABILITY_BY_UNIT = {m: a for a, m in UNIT_BY_ABILITY.items()}


def queued_by_material(structures):
    """Units of each material in the production queues right now, the one in progress included."""
    return Counter(UNIT_BY_ABILITY[o.ability.exact_id] for s in structures for o in s.orders
                   if o.ability.exact_id in UNIT_BY_ABILITY)


UPGRADE_BY_ABILITY = {info["ability"]: MATNR_BY_NAME[u.name] for t in RESEARCH_INFO for u, info in RESEARCH_INFO[t].items()
                      if MATERIALS.get(MATNR_BY_NAME.get(u.name, ""), {}).get("category") == "UPGRADE"}


def lost_orders(orders):
    """Materials in a dead structure's queue: units and research, which SC2 refunds in full (spike 2026-09-24)."""
    found = (UNIT_BY_ABILITY.get(o.ability.exact_id) or UPGRADE_BY_ABILITY.get(o.ability.exact_id) for o in orders)
    return [m for m in found if m]


# --- structure placement (spec 2026-09-25) ------------------------------------------------------
ZONES = {"SupplyDepot": "WALL", "Barracks": "WALL", "Factory": "PRODUCTION", "Starport": "PRODUCTION",
         "Bunker": "FRONT", "MissileTurret": "MINERAL_LINE", "CommandCenter": "EXPANSION", "Refinery": "GEYSER",
         **dict.fromkeys(("EngineeringBay", "Armory", "FusionCore", "GhostAcademy", "SensorTower"), "TECH")}
WALL_SLOTS = {"SupplyDepot": "WALL_DEPOTS", "Barracks": "WALL_BARRACKS"}
WALL_FALLBACK = {"SupplyDepot": "BEHIND_MINERALS", "Barracks": "PRODUCTION"}   # wall full, or no wall on this map
ADDON_PRODUCERS = {UnitTypeId.BARRACKS, UnitTypeId.FACTORY, UnitTypeId.STARPORT}
ADDON_OFFSET = (2.5, -0.5)      # python-sc2 Unit.add_on_position: where the add-on goes


def grid_candidates(target, size, radius=12):
    """Building centres on the game grid within radius of target, nearest first: odd sizes on .5, even on whole."""
    half = 0.5 if size % 2 else 0
    x0, y0 = round(target.x - half) + half, round(target.y - half) + half
    r = int(radius)
    points = (Point2((x0 + dx, y0 + dy)) for dx in range(-r, r + 1) for dy in range(-r, r + 1))
    return sorted((p for p in points if p.distance_to(target) <= radius), key=lambda p: p.distance_to(target))


def overlaps(p, size, q, qsize):
    """Two square footprints centred on p and q overlap."""
    return abs(p.x - q.x) < (size + qsize) / 2 and abs(p.y - q.y) < (size + qsize) / 2


def in_mining_lane(p, size, base, resources):
    """p sits on an SCV's path between base and one of its mineral patches or geysers (spike 2026-09-25)."""
    return any(p.distance_to(base) + p.distance_to(m) <= base.distance_to(m) + 1.5 + size / 2 for m in resources)


def placement_target(matnr, layout, taken, natural_ours, turret):
    """(zone, target, exact) of a structure; taken = positions of our structures, a wall slot within 1 tile is taken."""
    zone = ZONES[matnr]
    if zone == "WALL":
        slot = next((s for s in layout[WALL_SLOTS[matnr]] if all(s.distance_to(t) > 1 for t in taken)), None)
        if slot is not None:
            return zone, slot, True
        zone = WALL_FALLBACK[matnr]
    if zone == "FRONT" and natural_ours and layout["NATURAL_FRONT"] is not None:
        return zone, layout["NATURAL_FRONT"], False
    if zone == "MINERAL_LINE":
        return zone, turret, False
    return zone, layout.get(zone), False


def turret_anchor(bases, turrets):
    """bases: [(command center, mineral centre)], main first; 4 tiles into the line of the base with the fewest turrets."""
    cc, minerals = min(bases, key=lambda b: sum(t.distance_to(b[0]) <= 10 for t in turrets))
    return cc.towards(minerals, 4)


from push import Sap, SapError                    # noqa: E402


class Outpost(BotAI):
    def __init__(self, sap, map_name, minutes):
        super().__init__()
        self.sap, self.map_name, self.minutes = sap, map_name, minutes
        self.game_uuid, self.division_uuid = new_id(), new_id()
        self.main_plant = new_plant(1, None, 0)
        self.plants = {}            # town hall tag -> plant dict
        self.owned = {}             # unit tag -> (matnr, birth plant uuid)
        self.inflight, self.started = Inflight(), set()   # order UUIDs already handled this run (STARTED or CANCELLED)
        self.spent = [0, 0]         # 261 − 262 minerals / gas posted, for the reconciliation line
        self.next_mining_loop = 160
        self.mining = [0, 0, 0]     # 501 minerals and gas accumulated, stats ticks counted
        self.placing = {}           # structure matnr -> game loop its worker was sent (SC2 deducts at the command, refunds if dropped)
        self.leaving = False
        self.ended = False          # on_end ran (python-sc2 may die before calling it)
        self.reasons = {}           # order uuid -> last logged blocking reason, to log changes only
        self.backlog = {}           # RELEASED orders waiting for the game: uuid -> SAP row (refreshed by each poll)
        self.cancels = {}           # CANCELLING orders from the last poll: uuid -> SAP row
        self.answered = set()       # CANCELLING uuids answered since the last poll (a refusal is answered again next poll)
        self.cancelled = set()      # cancelled in game: never answered again while SAP still shows CANCELLING
        self.cancelled_sites = set()  # tags our CANCEL_BUILDINPROGRESS hit: their death is booked by answer_cancel
        self.scrapped = {}          # order uuid -> why it ended SCRAPPED, to answer a Cancel Order that comes late
        self.next_backlog_loop = 0
        self.next_idle_loop = 0
        self.gas_trimmed = {}       # refinery tag -> game loop before which it is not trimmed again
        self.next_stuck_loop = 0
        self.last_excess = {}       # unit matnr -> orders missing from every queue at the last stuck check
        self.posted = {}            # order uuid -> (minerals, gas) posted as 261 at STARTED, reversed by 262 if refused
        self.issued = {}            # order uuid -> game loop its command was issued (the stuck check ignores young ones)
        # Plant Maintenance (spec 2026-09-27); changed on the game thread only
        self.reserved = {}          # SCV tag -> maintenance order uuid, from the repair command until the segment is settled
        self.notified = {}          # equipment tag -> its notification that is not closed; game decisions only
        self.closing = {}           # equipment tag -> the notification being closed and the key of the report that closes it
        self.repairs = {}           # maintenance order uuid -> {"row", "state": waiting | work | ended, "reason", "released"}
        self.segment = None         # the one repair in work: SCV, target, R at the command
        self.pm_gen = {}            # notification or order uuid -> generation of its latest fact, until SAP answered it
        self.pm_seq = 0
        self.opening = (0, 0)       # opening bank of the exact measure
        self.repair_posted = [0, 0]  # repair cost posted as 261, minerals / gas
        self.next_pm_loop = 0
        self.sap_worker = None
        self.sc2_proc = None        # the SC2 Popen python-sc2 launched, kept so main() can close a leftover window

    # --- SAP plumbing -------------------------------------------------------------------------
    def bootstrap(self):
        """Deep-create Game + Division + Plant 0001 before SC2 launches; raises SapError on failure."""
        self.sap.post("Game", game_payload(self.game_uuid, self.division_uuid, self.map_name, self.main_plant))
        print(f"game     {self.game_uuid}\ndivision {self.division_uuid}")

    @property
    def game_seconds(self):
        return int(self.state.game_loop / LOOPS_PER_SECOND)

    def enqueue(self, job):
        self.sap_worker.q.put(job)

    def post_event(self, mvt, matnr, qty, plant=None, order=None, tag=0, cost=None):
        row = event(mvt, matnr, qty, self.game_seconds, values(matnr, cost, qty), plant, order, tag)
        self.enqueue(lambda: self.sap.post(f"Division({self.division_uuid})/_Event", row))

    def patch_sap(self, path, body):
        self.enqueue(lambda: self.sap.patch(path, body))

    def nearest_plant(self, pos):
        open_plants = [p for p in self.plants.values() if p["ClosedAt"] is None]
        if not open_plants:
            return None
        return min(open_plants, key=lambda p: (p["PosX"] - pos.x) ** 2 + (p["PosY"] - pos.y) ** 2)["PlantUUID"]

    def log(self, text):
        print(f"{self.game_seconds:>5}s  {text}")

    # --- game lifecycle -----------------------------------------------------------------------
    async def on_start(self):
        # ponytail: python-sc2 internals (KillSwitch registry, SC2Process._process); it clears its own
        # reference at cleanup, so grab the Popen now. Upgrade path: a public pid API if python-sc2 adds one.
        self.sc2_proc = getattr(KillSwitch._to_kill[-1], "_process", None) if KillSwitch._to_kill else None
        cc = self.townhalls.first
        self.main_plant["PosX"], self.main_plant["PosY"] = int(cc.position.x), int(cc.position.y)
        self.plants[cc.tag] = self.main_plant
        self.sap_worker = SapWorker(self.sap, self.division_uuid)
        self.sap_worker.start()
        plant = self.main_plant["PlantUUID"]
        self.patch_sap(f"Plant({plant})", {"PosX": self.main_plant["PosX"], "PosY": self.main_plant["PosY"]})
        for unit in [cc, *self.workers]:
            matnr = MATNR_BY_NAME[unit.type_id.name]
            self.owned[unit.tag] = (matnr, plant)
            self.post_event("561", matnr, 1, plant=plant, tag=unit.tag, cost=self.calculate_cost(unit.type_id))
        if self.minerals:
            self.post_event("561", "MINERAL", self.minerals)
        self.opening = tuple(-r for r in measure((0, 0), self.state.common, self.state.score))   # R starts at 0
        await self.plan_layout()

    async def on_step(self, iteration):
        if self.leaving:
            return
        if self.time >= self.minutes * 60:
            self.leaving = True
            await self.client.leave()
            return
        self.pm_answers()
        self.watch_repair()         # every observation: the segment ends with the first one without the repair order
        if self.state.game_loop >= self.next_pm_loop:
            self.next_pm_loop = self.state.game_loop + IDLE_CHECK_LOOPS
            self.check_damage()
            self.start_repairs()
        if self.state.game_loop >= self.next_idle_loop:
            self.next_idle_loop = self.state.game_loop + IDLE_CHECK_LOOPS
            sent = self.return_idle_workers()
            if sent:
                self.log(f"{sent} idle SCV{'s' if sent > 1 else ''} back to mining")
            sent = self.staff_refineries()
            if sent:
                self.log(f"{sent} SCV{'s' if sent > 1 else ''} to gas")
            sent = self.trim_refineries()
            if sent:
                self.log(f"{sent} SCV{'s' if sent > 1 else ''} off gas")
        if self.state.game_loop >= self.next_stuck_loop:
            self.next_stuck_loop = self.state.game_loop + STUCK_CHECK_LOOPS
            self.reverse_stuck(queued_by_material(self.structures), self.state.game_loop)
        rows = self.sap_worker.take_released()
        if rows is not None:        # SAP is the truth: orders deleted or cancelled there leave the backlog
            self.take_orders(rows)
        self.answer_cancels()
        self.timeout_placements()
        if self.backlog and not self.placing and self.state.game_loop >= self.next_backlog_loop:
            # ponytail: every ~0.5 s, not every frame — structure placement asks SC2 over the API
            self.next_backlog_loop = self.state.game_loop + BACKLOG_LOOPS
            for uuid, order in list(self.backlog.items()):
                reason = await self.execute(order)
                if uuid in self.started:
                    del self.backlog[uuid]
                if reason == "":
                    continue        # no news this frame; keep the last reason
                if reason != self.reasons.get(uuid):
                    self.reasons[uuid] = reason
                    if reason:      # None = started
                        self.log(f"{order['Material']}: {reason}")
                        self.patch_sap(f"ProdOrder({uuid})", {"StatusText": reason[:80]})
        if self.state.game_loop >= self.next_mining_loop:
            self.next_mining_loop += 160
            score = self.state.score
            self.mining[0] += mining_qty(score.collection_rate_minerals)
            self.mining[1] += mining_qty(score.collection_rate_vespene)
            self.mining[2] += 1
            if self.mining[2] >= MINING_TICKS_PER_POST:
                self.post_mining()

    def post_mining(self):
        """Post the 501 minerals and gas summed since the last post (division level), then start over."""
        for matnr, qty in (("MINERAL", self.mining[0]), ("VESPENE", self.mining[1])):
            if qty:
                self.post_event("501", matnr, qty)
        self.mining = [0, 0, 0]

    async def execute(self, order):
        """Issue the command for one RELEASED order. None on success, else why it stays RELEASED."""
        uuid, matnr = order["OrderUUID"], game_matnr(order["Material"])
        item = item_id(matnr)
        if item is None:
            self.started.add(uuid)
            self.reasons[uuid] = "unknown material"     # sent with CANCELLED; the backlog loop must not PATCH it again
            self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "CANCELLED", "StatusText": "unknown material"})
            self.log(f"{matnr}: unknown material, cancelled")
            return "unknown material"
        if isinstance(item, UnitTypeId) and not is_structure(matnr) \
                and not self.structures.ready.of_type(UNIT_TRAINED_FROM.get(item, ())):
            return f"no {MATERIALS[matnr]['produced_by']} on hand yet"     # same words as the release warning
        if not self.can_afford(item):
            return "cannot afford (minerals, gas or supply)"
        if isinstance(item, UnitTypeId):
            if self.tech_requirement_progress(item) < 1:
                return f"requires {MATNR_BY_NAME.get(TERRAN_TECH_REQUIREMENT[item].name, 'a tech structure')}"
            if is_structure(matnr) and self.inflight.pending(matnr):
                # one order per structure material in flight: the placement timeout and the in-game cancel find it by material
                return f"waiting for the previous {matnr} to finish"
            issued = await self.issue_unit(matnr, item)
        else:
            issued = self.research(item)
        if isinstance(issued, str):
            return issued       # a structure without a spot: the bot message says why, the next pass retries
        if issued is None:
            return ""       # a producer has room but already got a command this frame
        if not issued:
            if isinstance(item, UnitTypeId) and not is_structure(matnr):
                return f"{MATERIALS[matnr]['produced_by']} queues full or busy"
            return "no idle producer, free worker or placement"
        self.started.add(uuid)
        self.inflight.add(matnr, uuid)
        cost = self.calculate_cost(item)
        self.posted[uuid] = (cost.minerals, cost.vespene)
        self.issued[uuid] = self.state.game_loop
        self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "STARTED", "ReleasedAt": self.game_seconds,
                                              "StatusText": ""})
        if is_structure(matnr) and matnr not in ADDON_PARENT:
            self.placing[matnr] = self.state.game_loop     # addons are placed by their parent at once
        if cost.minerals:
            self.post_event("261", "MINERAL", cost.minerals, order=uuid)
        if cost.vespene:
            self.post_event("261", "VESPENE", cost.vespene, order=uuid)
        self.spent[0] += cost.minerals
        self.spent[1] += cost.vespene
        self.log(f"{matnr}: started")
        return None

    def post_262(self, uuid, minerals, gas):
        """Resources back to the ledger for an order (262, order set, no plant), off the reconciliation counters."""
        for matnr, qty in (("MINERAL", minerals), ("VESPENE", gas)):
            if qty:
                self.post_event("262", matnr, qty, order=uuid)
        self.spent[0] -= minerals
        self.spent[1] -= gas

    def take_orders(self, rows):
        """Split a poll: RELEASED orders feed the backlog, CANCELLING ones the cancels.

        A refusal is answered again by each poll that still shows CANCELLING (a re-click, or its PATCH was dropped);
        a success is not: its uuid left `inflight`, so answering again would wrongly say "already built".
        """
        self.backlog = {o["OrderUUID"]: o for o in rows
                        if o["OrderStatus"] == "RELEASED" and o["OrderUUID"] not in self.started}
        self.cancels = {o["OrderUUID"]: o for o in rows if o["OrderStatus"] == "CANCELLING"}
        self.cancelled.intersection_update(self.cancels)
        self.answered = set(self.cancelled)

    def answer_cancels(self):
        """Answer each CANCELLING order once per poll; False from answer_cancel (producer busy) retries next frame."""
        for uuid, order in self.cancels.items():
            if uuid not in self.answered and self.answer_cancel(uuid, game_matnr(order["Material"])):
                self.answered.add(uuid)

    def answer_cancel(self, uuid, matnr):
        """Cancel one CANCELLING order in the game and tell SAP. False = try again next frame.

        ponytail: game commands are fire-and-forget (the spike proved each one); a silently failed cancel
        would show as a 101 without order and a reconciliation mismatch.
        """
        if uuid in self.scrapped:   # its site died before the click arrived
            self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "SCRAPPED", "StatusText": self.scrapped[uuid]})
            return True
        if uuid not in self.started:
            return True         # reversed a moment ago: its RELEASED PATCH wins
        if uuid not in self.inflight.by_matnr.get(matnr, ()):
            self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "CONFIRMED", "StatusText": "cannot cancel: already built"})
            return True
        why, partial = self.cancel_command(matnr)
        if why == "":
            return False
        if why:
            self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "STARTED", "StatusText": f"cannot cancel: {why}"})
            self.log(f"{matnr}: cannot cancel: {why}")
            return True
        self.inflight.by_matnr[matnr].remove(uuid)
        self.issued.pop(uuid, None)
        self.cancelled.add(uuid)
        self.post_262(uuid, *refund(*self.posted.pop(uuid, (0, 0)), partial))
        text = f"cancelled in game, refund {75 if partial else 100}%"
        self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "CANCELLED", "StatusText": text})
        self.log(f"{matnr}: {text}")
        return True

    def reverse(self, uuid, matnr, text="command refused, retried"):
        """SC2 refused the command or refunded the order: 262 for exactly its 261, back to RELEASED; the next poll retries it."""
        self.post_262(uuid, *self.posted.pop(uuid, (0, 0)))
        self.started.discard(uuid)
        self.reasons.pop(uuid, None)
        self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "RELEASED", "StatusText": text})
        self.log(f"{matnr}: {text}, 262 posted")

    def scrap_site(self, tag, prev):
        """A structure died under construction: SC2 gives back nothing, or 75% for an add-on dying with its parent."""
        if tag in self.cancelled_sites:
            self.cancelled_sites.discard(tag)
            return              # our own CANCEL_BUILDINPROGRESS: answer_cancel booked it
        matnr = MATNR_BY_NAME.get(prev.type_id.name)
        uuid = self.inflight.pop(matnr)     # one order per structure material is in flight
        if uuid is None:
            self.log(f"{matnr}: site lost without order")
            return
        build = self.game_data.units[prev.type_id.value].creation_ability.exact_id
        partial = any(o.ability.exact_id == build for t in self.state.dead_units
                      if (parent := self._structures_previous_map.get(t)) for o in parent.orders)
        minerals, gas = self.posted.pop(uuid, (0, 0))
        self.issued.pop(uuid, None)
        if partial:
            self.post_262(uuid, *refund(minerals, gas, True))
            text = f"destroyed with its {ADDON_PARENT[matnr]}, refund 75%"
        else:
            text = "destroyed under construction"
        self.scrapped[uuid] = text
        self.patch_sap(f"ProdOrder({uuid})", {"OrderStatus": "SCRAPPED", "StatusText": text})
        self.log(f"{matnr}: {text}")

    def timeout_placements(self):
        """Reverse a structure order whose SCV has not started building after 30 s and is no longer on its way."""
        for matnr, sent in list(self.placing.items()):
            if self.state.game_loop - sent <= 30 * LOOPS_PER_SECOND or self.worker_en_route_to_build(item_id(matnr)):
                continue        # still walking (detour, blocked path): not refused, a retry would build it twice
            self.log(f"placement of {matnr} never started")
            for uuid in self.inflight.drop_newest(matnr, 1):   # execute allows one order per structure material
                self.reverse(uuid, matnr)
            del self.placing[matnr]

    def reverse_stuck(self, queued, now):
        """Reverse unit orders missing from every production queue on two checks in a row, newest first.

        Only orders older than one check interval count: a younger one may just not be observed yet. Orders of a
        material are interchangeable (the next unit confirms the oldest), so reversing the newest is enough.
        ponytail: addons and research are not watched; a refused one stays STARTED (reconciliation shows it).
        """
        old = {m: sum(now - self.issued.get(u, now) >= STUCK_CHECK_LOOPS for u in q)
               for m, q in self.inflight.by_matnr.items()}
        excess = unit_excess(old, queued)
        for matnr in excess.keys() & self.last_excess.keys():
            n = min(excess[matnr], self.last_excess[matnr])
            for uuid in self.inflight.drop_newest(matnr, n):
                self.reverse(uuid, matnr)
            excess[matnr] -= n
        self.last_excess = {m: n for m, n in excess.items() if n}

    def cancel_command(self, matnr):
        """Issue the game command that cancels one order of matnr (spike 2026-09-24).

        (None, partial) = issued, partial = SC2 refunds 75%; ("", False) = producer busy, try next frame;
        (why, False) = the game cannot cancel it.
        """
        item = item_id(matnr)
        if isinstance(item, UpgradeId):
            ability = self.game_data.upgrades[item.value].research_ability.exact_id
        elif not is_structure(matnr):
            ability = ABILITY_BY_UNIT.get(matnr)
        else:
            if matnr in self.placing:
                build = self.game_data.units[item.value].creation_ability.exact_id
                walkers = [w for w in self.workers if any(o.ability.exact_id == build for o in w.orders)]
                if walkers:
                    for w in walkers:
                        w.stop()        # SC2 took the cost at the build command and gives it all back
                    del self.placing[matnr]
                    return None, False
            site = self.structures(item).not_ready
            if not site:
                return "not found in the game", False
            site.first(AbilityId.CANCEL_BUILDINPROGRESS)   # one order per structure material is in flight
            self.cancelled_sites.add(site.first.tag)       # its death event is not a loss: answer_cancel books it
            return None, True
        producer, why = pick_last(self.structures, ability, self.unit_tags_received_action)
        if producer is None:
            return why, False
        producer(AbilityId.CANCEL_LAST)
        return None, False

    async def issue_unit(self, matnr, item):
        if matnr in ADDON_PARENT:
            parents = [s for s in self.structures(UnitTypeId[ADDON_PARENT[matnr].upper()]).ready.idle
                       if not s.has_add_on]
            if not parents:
                return False
            # the addon footprint is 2x2 like a depot; SC2 refuses a blocked placement silently
            if not await self.can_place_single(UnitTypeId.SUPPLYDEPOT, parents[0].add_on_position):
                return False
            return bool(parents[0].build(item))
        if not self.townhalls:
            return False
        if item == UnitTypeId.REFINERY:
            free = [g for g in self.vespene_geyser if not self.gas_buildings.closer_than(1.0, g)]
            if not free:
                return False
            return await self.build(item, near=min(free, key=lambda g: g.distance_to(self.townhalls.first)))
        # one structure per material in flight (see execute), and no backlog pass while an SCV walks to place
        # one (on_step, self.placing): BotAI.build subtracts the cost locally for the current frame only
        if is_structure(matnr):
            return await self.place(matnr, item)
        return self.queue_unit(item)

    async def plan_layout(self):
        """Zone targets from the main, its ramp and the natural, once per game (spec 2026-09-25)."""
        start, center = self.start_location, self.game_info.map_center
        minerals = self.mineral_field.closer_than(10, start).center
        self.layout = {"WALL_DEPOTS": [], "WALL_BARRACKS": [], "FRONT": start.towards(center, 8), "NATURAL": None,
                       "NATURAL_FRONT": None, "BEHIND_MINERALS": minerals.towards(start, -3),
                       "PRODUCTION": start.towards(center, 8), "TECH": start.towards(center, -8)}
        try:
            ramp = self.main_base_ramp
            if ramp.barracks_correct_placement and ramp.corner_depots:
                self.layout["WALL_DEPOTS"] = sorted(ramp.corner_depots)
                self.layout["WALL_BARRACKS"] = [ramp.barracks_correct_placement]
            self.layout["FRONT"] = ramp.top_center.towards(start, 5)
            self.layout["TECH"] = start.towards(ramp.top_center, -8)
            natural = self.layout["NATURAL"] = await self.get_next_expansion()
            enemy = self.enemy_start_locations[0]
            # the enemy start is inside its town hall (no path): aim at its natural instead (spike 2026-09-25)
            goal = min((e for e in self.expansion_locations_list if e.distance_to(enemy) > 5),
                       key=lambda e: e.distance_to(enemy))
            ring = [p for p in (natural + Point2((7 * math.cos(a), 7 * math.sin(a)))
                                for a in (i * math.pi / 8 for i in range(16))) if self.in_pathing_grid(p)]
            paths = await self.client.query_pathings([[p, goal] for p in ring])
            self.layout["NATURAL_FRONT"] = min((d, p) for p, d in zip(ring, paths) if d)[1]
        except Exception as e:      # ponytail: a map this analysis cannot read keeps the fallback targets set so far
            self.log(f"placement layout fallback: {e!r}")

    def natural_ours(self):
        natural = self.layout["NATURAL"]
        return natural is not None and any(t.distance_to(natural) <= 3 for t in self.townhalls)

    def turret_target(self):
        """Mineral-line target of the own base with the fewest turrets, main first."""
        bases = [(t.position, self.mineral_field.closer_than(10, t).center)
                 for t in sorted(self.townhalls, key=lambda t: t.distance_to(self.start_location))
                 if self.mineral_field.closer_than(10, t)]
        if not bases:
            return self.layout["BEHIND_MINERALS"]      # every base mined out: any spot beats none
        return turret_anchor(bases, [s.position for s in self.structures(UnitTypeId.MISSILETURRET)])

    async def find_spot(self, item, zone, target):
        """Nearest grid spot to target the game accepts: off the mining lanes (not MINERAL_LINE), add-on room for PRODUCTION."""
        size = round(self.game_data.units[item.value].footprint_radius * 2)
        base = self.townhalls.closest_to(target)
        resources = [r.position for r in self.resources.closer_than(12, base)]
        # a production building's add-on spot stays free until its add-on stands (final review 2026-09-25)
        addons = [s.add_on_position for s in self.structures.of_type(ADDON_PRODUCERS) if not s.has_add_on]
        spots = [p for p in grid_candidates(target, size)
                 if (zone == "MINERAL_LINE" or not in_mining_lane(p, size, base.position, resources))
                 and not any(overlaps(p, size, a, 2) for a in addons)]
        if not spots:
            return None
        ok = await self.can_place(item, spots)
        if zone == "PRODUCTION":
            room = await self.can_place(UnitTypeId.SUPPLYDEPOT, [p.offset(ADDON_OFFSET) for p in spots])
            ok = [a and b for a, b in zip(ok, room)]
        return next((p for p, good in zip(spots, ok) if good), None)

    async def place(self, matnr, item):
        """Build a structure in its zone (spec 2026-09-25): True when issued, else the bot message why it waits."""
        if matnr == "CommandCenter":
            spot, why = await self.get_next_expansion(), "no free expansion"
        else:
            zone, target, exact = placement_target(matnr, self.layout, [s.position for s in self.structures],
                                                   self.natural_ours(), self.turret_target())
            spot = target if exact else await self.find_spot(item, zone, target)
            why = f"no placement in {zone}"
        # max_distance=0: exactly this spot or nothing; python-sc2 still picks the SCV and subtracts the cost
        if spot is None or not await self.build(item, near=spot, max_distance=0):
            return why
        return True

    def select_build_worker(self, pos, force=False):
        """python-sc2's choice (near, idle first, then the nearest; only SCVs that idle, move or gather), without
        the SCVs reserved for a repair or commanded in this frame. Every build goes through it (BotAI.build).

        python-sc2 tests a Unit against its set of integer tags, which never matches, so its own same-frame
        guard excludes nobody (sc2/bot_ai.py, Unit.__eq__).
        """
        free = free_workers(self.workers, self.reserved, self.unit_tags_received_action)
        near = [w for w in free if (w.is_gathering or w.is_idle) and w.distance_to(pos) < 20] or free
        for worker in sorted(near, key=lambda w: (not w.is_idle, w.distance_to(pos))):
            if not worker.orders or (len(worker.orders) == 1 and worker.orders[0].ability.id
                                     in (AbilityId.MOVE, AbilityId.HARVEST_GATHER)):
                return worker
        return near[0] if force and near else None

    def return_idle_workers(self):
        """Send idle SCVs to the minerals of their nearest base; returns how many were sent.

        SC2 leaves an SCV idle after it finishes a building. The bot does this without an SAP order
        (Kamil, 2026-09-24): otherwise every ordered structure costs a miner for good.
        """
        idle = free_workers(self.workers.idle, self.reserved, self.unit_tags_received_action)
        if not idle or not self.townhalls or not self.mineral_field:
            return 0
        for worker in idle:
            worker.gather(self.mineral_field.closest_to(self.townhalls.closest_to(worker)))
        return len(idle)

    def staff_refineries(self):
        """Fill each ready refinery next to a base up to its ideal harvesters (3) with the nearest free mineral miners.

        SC2 staffs only the SCV that built it, so gas orders waited all game. Also without an SAP order (Kamil,
        2026-09-26); a gas SCV pulled off to build is replaced on the next check. Returns how many were sent.
        """
        bases = self.townhalls.ready
        minerals = self.mineral_field.tags
        miners = [w for w in free_workers(self.workers, self.reserved, self.unit_tags_received_action)
                  if w.is_gathering and w.order_target in minerals and not w.is_carrying_resource]
        sent = 0
        for refinery in self.gas_buildings.ready:
            if not bases or bases.closest_distance_to(refinery) > 10:
                continue
            # assigned_harvesters lags a gather order by a check or two: count the SCVs already sent as well
            on_the_way = sum(1 for w in self.workers if w.order_target == refinery.tag)
            for _ in range(refinery.ideal_harvesters - max(refinery.assigned_harvesters, on_the_way)):
                if not miners:
                    return sent
                worker = min(miners, key=lambda w: w.distance_to(refinery))
                miners.remove(worker)
                worker.gather(refinery)
                sent += 1
        return sent

    def trim_refineries(self):
        """Send one surplus SCV per over-staffed refinery back to minerals; returns how many were sent.

        The SCV that built a refinery starts harvesting it a moment after the bot has sent three (seen 2026-09-27:
        4 on a refinery all game). Whatever the cause, more than ideal is trimmed; an empty geyser (ideal 0) empties.
        """
        loop = self.state.game_loop
        sent = 0
        for refinery in self.gas_buildings.ready:
            if refinery.assigned_harvesters <= refinery.ideal_harvesters or loop < self.gas_trimmed.get(refinery.tag, 0):
                continue
            extra = [w for w in free_workers(self.workers, self.reserved, self.unit_tags_received_action)
                     if w.order_target == refinery.tag and not w.is_carrying_resource]
            if extra and self.townhalls and self.mineral_field:
                extra[0].gather(self.mineral_field.closest_to(self.townhalls.closest_to(refinery)))
                self.gas_trimmed[refinery.tag] = loop + GAS_TRIM_WAIT_LOOPS
                sent += 1
        return sent

    def queue_unit(self, item):
        """Queue a unit in the producer with the shortest queue. True issued, None retry next pass, False no room.

        python-sc2's train() only uses idle producers, or with train_only_idle_buildings=False ignores
        the queue limit (SC2 then refuses silently and the order would sit in STARTED with its 261 posted).
        """
        types = UNIT_TRAINED_FROM[item]
        needs_techlab = any(TRAIN_INFO[t][item].get("requires_techlab", False) for t in types)
        ready = self.structures.ready
        techlabs = {s.tag for s in ready if s.tag in self.techlab_tags}   # finished ones; techlab_tags has unfinished too
        room = [s for s in ready
                if s.type_id in types and len(s.orders) < QUEUE_LIMIT
                # SC2 refuses a train while the producer builds an addon, morphs or lifts off
                and all(o.ability.exact_id in TRAIN_ABILITIES.get(s.type_id, ()) for o in s.orders)
                and (not needs_techlab or s.add_on_tag in techlabs)]
        if not room:
            return False
        free = [s for s in room if s.tag not in self.unit_tags_received_action]
        if not free:
            return None     # python-sc2 sends one command per structure per frame
        ok = bool(min(free, key=lambda s: (len(s.orders), s.add_on_tag in self.techlab_tags)).train(item))
        if ok:
            self.supply_left -= self.calculate_supply_cost(item)   # Unit.train subtracts cost but not supply
        return ok

    # --- Plant Maintenance (spec 2026-09-27) ----------------------------------------------------
    def pm_fact(self, kind, key, body):
        """Hand a fact to the outbox. Its generation fences the answers: only the latest one's counts."""
        self.pm_seq += 1
        if kind != "event":
            self.pm_gen[key] = self.pm_seq
        self.sap_worker.pm.inbox.put({"kind": kind, "key": key, "gen": self.pm_seq, "body": body})

    def report_repair(self, uuid, status, text, outcome="", scv=0, started=0):
        """reportRepair with the whole payload, so a status that was never delivered loses nothing."""
        self.pm_fact("repair", uuid, {"OrderStatus": status, "WorkerTag": scv, "StartedAt": started,
                                      "AtSeconds": self.game_seconds, "StatusText": text[:80],
                                      "NotificationOutcome": outcome})

    def report_notification(self, n, status, text):
        self.pm_fact("notify", n["uuid"], {"NotificationStatus": status, "Priority": n["priority"],
                                           "Health": n["health"], "HealthMax": n["max"],
                                           "AtSeconds": self.game_seconds, "StatusText": text[:80]})

    def check_damage(self):
        """A notification for every finished structure of ours that is damaged and has none; one update when its
        priority gets worse. `notified` follows the game only: no answer of SAP, and no missing one, changes it."""
        for unit in self.structures.ready:
            tag = unit.tag
            health, top = int(unit.health), int(unit.health_max)
            if tag not in self.owned or tag in self.closing or top < 1:
                continue        # closing: new damage waits until SAP has confirmed the close of the old notification
            n = self.notified.get(tag)
            if n is None:
                if health >= top:
                    continue
                matnr, plant = self.owned[tag]
                n = self.notified[tag] = {"uuid": new_id(), "priority": priority(health, top), "health": health, "max": top}
                self.pm_fact("create", n["uuid"], clean(
                    {"NotificationUUID": n["uuid"], "UnitTag": tag, "Material": matnr, "PlantUUID": plant,
                     "Priority": n["priority"], "Health": health, "HealthMax": top,
                     "ReportedAt": self.game_seconds, "StatusText": "damaged"}))
                self.log(f"{matnr}: damaged ({health} of {top}), notification priority {n['priority']}")
                continue
            n["health"], n["max"] = health, top
            if health >= top:
                self.close_recovered(tag, n)
            elif priority(health, top) < n["priority"]:
                n["priority"] = priority(health, top)
                self.report_notification(n, "", "damage got worse")

    def close_recovered(self, tag, n):
        """The damage is gone and no repair order will say so: the notification is closed by itself.

        Not while a repair of the equipment is in work or being settled (its segment ends with the repair order,
        not with full health), not while SAP has not answered an order's last report, and not for an order the
        latest poll shows RELEASED: that one ends as `no damage left` in start_repairs. An order the player
        released a moment ago ends with the notification in SAP's same LUW; a repair in work makes SAP refuse.
        """
        if self.segment and self.segment["target"] == tag:
            return
        for uuid, order in self.repairs.items():
            if order["state"] != "ended" and int(order["row"]["UnitTag"]) == tag \
                    and (order["state"] == "work" or order["released"] or uuid in self.pm_gen):
                return
        del self.notified[tag]
        self.closing[tag] = {**n, "key": n["uuid"], "text": "no damage found"}
        self.report_notification(n, "CLOSED", "no damage found")
        self.log(f"{self.owned[tag][0]}: no damage found, notification closed")

    def pm_answers(self):
        """Apply SAP's answers and polls in the order the worker made them; nothing else reads that queue."""
        while True:
            try:
                answer = self.sap_worker.pm.acks.get_nowait()
            except queue.Empty:
                return
            if answer[0] == "poll":
                self.take_repairs(answer[1])
            else:
                self.pm_answer(*answer[1:])

    def pm_answer(self, fact, outcome, row):
        kind, key, body = fact["kind"], fact["key"], fact["body"]
        if kind == "event":
            return              # the worker counts what it parked
        if outcome == "adopt":
            # SAP holds another open notification of the equipment: that one is tracked on, also by what was
            # decided on the proposed uuid meanwhile (the worker sends those reports to the adopted one)
            uuid = row["NotificationUUID"]
            for n in (*self.notified.values(), *self.closing.values()):
                if n["uuid"] == key:
                    n["uuid"] = uuid
                    if n.get("key") == key:
                        n["key"] = uuid
            if self.pm_gen.get(key) == fact["gen"]:
                del self.pm_gen[key]
            elif key in self.pm_gen:
                self.pm_gen[uuid] = self.pm_gen.pop(key)
            return
        dead = outcome in ("rejected", "conflict")      # SAP will never hold this key's facts
        if self.pm_gen.get(key) != fact["gen"] and not dead:
            return              # an older answer never clears the latest pending state
        self.pm_gen.pop(key, None)
        if kind == "repair" and (dead or outcome != "ack"):
            self.repair_refused(key, None if dead else row["OrderStatus"])
        if dead or not is_final(fact):
            return              # a close that SAP rejected keeps its equipment blocked, visible as parked
        closes = kind == "notify" or body["OrderStatus"] == "CONFIRMED" or body["NotificationOutcome"] == "CLOSED"
        tag = next((t for t, n in self.closing.items() if n["key"] == key), None)
        if tag is None or not closes:
            return
        if outcome == "ack":    # also a notification that was closed before: SAP answers with the closed row
            del self.closing[tag]
            if kind == "notify":    # definitive: SAP cancelled the RELEASED orders of the notification with it
                for order in self.repairs.values():
                    if order["state"] == "waiting" and int(order["row"]["UnitTag"]) == tag:
                        order["state"] = "ended"
        else:
            self.close_after(tag)

    def close_after(self, tag):
        """The order's final report closed nothing, because SAP had ended the order before (cancelled there).
        The notification is closed by itself when the equipment is destroyed, or at full health with no repair
        in work; otherwise it stays open in SAP and is tracked on."""
        n = self.closing[tag]
        unit = self.structures.find_by_tag(tag)
        in_work = self.segment is not None and self.segment["target"] == tag
        if tag not in self.owned:
            n.update(health=0, priority="1")
        elif in_work or unit is None or unit.health < unit.health_max:
            del self.closing[tag]
            self.notified[tag] = n
            return
        n["key"] = n["uuid"]
        self.report_notification(n, "CLOSED", n["text"])

    def take_repairs(self, rows):
        """A poll of the maintenance orders. SAP's status alone starts nothing: only an order that waits here is
        refreshed, and one in work or ended here ignores a RELEASED that lags. An order missing from a poll is
        not executed until a poll shows it RELEASED again; only a definitive answer of SAP or the bot's own
        final report ends an order."""
        seen = {row["OrderUUID"]: row for row in rows}
        for uuid, row in seen.items():
            order = self.repairs.setdefault(uuid, {"row": row, "state": "waiting", "reason": None, "released": False})
            if row["OrderStatus"] == "CANCELLING":
                self.cancel_repair(uuid)
            elif order["state"] == "waiting":
                order["row"] = row
        for uuid, order in self.repairs.items():
            released = uuid in seen and seen[uuid]["OrderStatus"] == "RELEASED"
            if order["state"] == "waiting" and order["released"] and not released and uuid not in self.pm_gen:
                self.log(f"repair of {order['row']['Material']}: not released in this poll, waits")
            order["released"] = released

    def cancel_repair(self, uuid):
        """Cancel Order in SAP (CANCELLING), also as the answer to a refused report: never back to RELEASED."""
        order = self.repairs[uuid]
        if order["state"] == "work" and self.segment and self.segment["order"] == uuid:
            self.stop_repair("cancel")          # the watch books the segment, then answers CANCELLED
        elif order["state"] != "ended":
            unit = self.structures.find_by_tag(int(order["row"]["UnitTag"]))
            self.end_order(uuid, "CANCELLED", "cancelled in game",
                           closes=unit is not None and unit.health >= unit.health_max)

    def repair_refused(self, uuid, status):
        """SAP holds another status than the bot reported (None: it holds nothing the bot can report on)."""
        order = self.repairs.get(uuid)
        if order is None:
            return
        if status == "CANCELLING":
            return self.cancel_repair(uuid)
        self.log(f"repair of {order['row']['Material']}: ended, SAP holds {status or 'no such order'}")
        order["state"] = "ended"
        if self.segment and self.segment["order"] == uuid:
            self.stop_repair("sap")             # the SCV goes back to mining; what it spent is still booked

    def end_order(self, uuid, status, text, closes, scv=0, started=0):
        """The final report of an order; with `closes` the notification closes with it in SAP's same LUW."""
        order = self.repairs[uuid]
        order["state"] = "ended"
        tag = int(order["row"]["UnitTag"])
        closes = closes or status == "CONFIRMED"
        self.report_repair(uuid, status, text, "" if status == "CONFIRMED" else "CLOSED" if closes else "OPEN",
                           scv, started)
        self.log(f"repair of {order['row']['Material']}: {status} {text}")
        if closes:
            n = self.notified.pop(tag, None) or {"uuid": order["row"]["NotificationUUID"], "priority": "3",
                                                 "health": 1, "max": 1}
            self.closing[tag] = {**n, "key": uuid, "text": text}

    def equipment_destroyed(self, tag):
        """A destroyed equipment ends its repair, its waiting orders and its notification."""
        seg = self.segment
        if seg and seg["target"] == tag and seg["ending"] != "sap":
            seg["ending"] = "destroyed"         # CANCELLED wins over a cancel request; booked by the watch
            return
        for uuid, order in self.repairs.items():
            if order["state"] == "waiting" and int(order["row"]["UnitTag"]) == tag:
                self.end_order(uuid, "CANCELLED", "equipment destroyed", closes=True)
        n = self.notified.pop(tag, None)
        if n:
            n.update(health=0, priority="1")
            self.closing[tag] = {**n, "key": n["uuid"], "text": "equipment destroyed"}
            self.report_notification(n, "CLOSED", "equipment destroyed")

    def start_repairs(self):
        """Waiting orders by priority, then age. One is tried only when SAP answered its last report and the
        latest poll shows it RELEASED; why it waits goes to SAP when it changes."""
        waiting = [o for o in self.repairs.values() if o["state"] == "waiting"]
        for order in sorted(waiting, key=lambda o: (o["row"]["Priority"], o["row"]["ReportedAt"])):
            uuid = order["row"]["OrderUUID"]
            if uuid in self.pm_gen or not order["released"] or int(order["row"]["UnitTag"]) in self.closing:
                continue        # a close of its notification is on its way: SAP's answer decides
            reason = self.try_repair(order)
            if reason and reason != order["reason"]:
                order["reason"] = reason
                self.log(f"repair of {order['row']['Material']}: {reason}")
                self.report_repair(uuid, "RELEASED", reason)

    def try_repair(self, order):
        """Start one repair order: None when it started or ended, "" without news, else why it waits."""
        row = order["row"]
        uuid, tag = row["OrderUUID"], int(row["UnitTag"])
        if tag not in self.owned:
            return self.end_order(uuid, "CANCELLED", "equipment destroyed", closes=True)
        target = self.structures.find_by_tag(tag)
        if target is None:
            return ""           # missing from this observation without a death event: no decision
        if target.health >= target.health_max:
            return self.end_order(uuid, "CONFIRMED", "no damage left", closes=True)
        if target.is_flying:
            return "equipment is flying"
        if self.segment:
            return f"waiting for the repair of {self.segment['material']}"
        common = self.state.common      # the first unit is charged with the first HP (spike)
        if common.minerals < 1 or (common.vespene < 1 and MATERIALS.get(row["Material"], {}).get("gas_cost")):
            return "cannot afford repair"
        if self.state.game_loop < order.get("retry_at", 0):
            return "cannot reach equipment"
        minerals = self.mineral_field.tags
        free = [w for w in free_workers(self.workers, self.reserved, self.unit_tags_received_action)
                if w.tag in self.owned and w.is_gathering and w.order_target in minerals and not w.is_carrying_resource]
        if not free:
            return "no free SCV"
        scv = min(free, key=lambda w: w.distance_to(target))
        self.reserved[scv.tag] = uuid   # at once: no selector of this frame or a later one takes it
        self.segment = {"order": uuid, "scv": scv.tag, "target": tag, "material": row["Material"],
                        "r0": measure(self.opening, common, self.state.score),   # before the command
                        "loop": self.state.game_loop, "started": self.game_seconds, "health": target.health,
                        "held": False, "progress": False, "ending": None, "stopped": False}
        scv.repair(target)
        order["state"], order["reason"] = "work", None
        self.report_repair(uuid, "STARTED", "SCV on its way", scv=scv.tag, started=self.game_seconds)
        self.log(f"repair of {row['Material']}: SCV {scv.tag} on its way")

    def stop_repair(self, ending):
        """Send the repairing SCV back to mining. It stays reserved until the watch has seen it without the
        repair order and booked the segment: a charge can still arrive before the command takes effect."""
        seg = self.segment
        if seg["ending"] not in ("destroyed", "sap"):
            seg["ending"] = ending
        scv = self.workers.find_by_tag(seg["scv"])
        if scv is None or (seg["held"] and not holds_repair(scv, seg["target"])):
            return              # the repair has ended by itself: nothing to stop
        if seg["stopped"] or scv.tag in self.unit_tags_received_action:
            return              # one command per unit and frame: the watch tries again
        if self.townhalls and self.mineral_field:
            scv.gather(self.mineral_field.closest_to(self.townhalls.closest_to(scv)))
        else:
            scv.stop()
        seg["stopped"] = True

    def watch_repair(self):
        """Follow the repair in work. Its segment ends with the first observation in which the reserved SCV no
        longer holds the repair order (spike); the target at full health is no end."""
        seg = self.segment
        if seg is None:
            return
        scv = self.workers.find_by_tag(seg["scv"])
        if scv is not None and holds_repair(scv, seg["target"]):
            seg["held"] = True
            target = self.structures.find_by_tag(seg["target"])
            moved = measure(self.opening, self.state.common, self.state.score) != seg["r0"] \
                or (target is not None and target.health > seg["health"])
            if moved and not seg["progress"]:
                seg["progress"] = True
                if not seg["ending"]:
                    self.report_repair(seg["order"], "STARTED", "repairing", scv=seg["scv"], started=seg["started"])
            if not seg["progress"] and not seg["ending"] and self.state.game_loop - seg["loop"] > REPAIR_STALL_LOOPS:
                seg["ending"] = "stall"
            if seg["ending"] in ("cancel", "sap", "stall") and not seg["stopped"]:
                self.stop_repair(seg["ending"])
            return
        if scv is not None and not seg["held"] and self.state.game_loop - seg["loop"] <= REPAIR_GRACE_LOOPS:
            return              # the order of a command shows in the next observation
        self.settle()

    def settle(self):
        """End of a segment: book the change of the exact measure once, free the SCV, report what happened."""
        seg, self.segment = self.segment, None
        self.reserved.pop(seg["scv"], None)
        uuid, order = seg["order"], self.repairs[seg["order"]]
        r = measure(self.opening, self.state.common, self.state.score)
        cost = (r[0] - seg["r0"][0], r[1] - seg["r0"][1])
        for i, (matnr, qty) in enumerate((("MINERAL", cost[0]), ("VESPENE", cost[1]))):
            if qty > 0:         # 261 on the maintenance order, no plant; accepted by SAP in every order status
                row = event("261", matnr, qty, self.game_seconds, values(matnr, None, qty), order=uuid)
                self.pm_fact("event", row["EventUUID"], row)
                self.repair_posted[i] += qty
        scv = self.workers.find_by_tag(seg["scv"])
        target = self.structures.find_by_tag(seg["target"])
        worker = {"scv": seg["scv"], "started": seg["started"]}
        self.log(f"repair of {seg['material']}: segment cost minerals {cost[0]} gas {cost[1]}")
        if seg["ending"] == "sap":
            return              # SAP ended the order itself: nothing to report
        full = target is not None and target.health >= target.health_max
        if seg["ending"] == "destroyed" or seg["target"] not in self.owned:
            return self.end_order(uuid, "CANCELLED", "equipment destroyed", closes=True, **worker)
        if seg["ending"] == "cancel" and full and not seg["stopped"]:
            return self.end_order(uuid, "CONFIRMED", "cannot cancel: already repaired", closes=True, **worker)
        if seg["ending"] == "cancel":
            return self.end_order(uuid, "CANCELLED", "cancelled in game", closes=full, **worker)
        if full:
            return self.end_order(uuid, "CONFIRMED", "repaired", closes=True, **worker)
        common = self.state.common
        dry = common.minerals < 1 or (common.vespene < 1 and MATERIALS.get(seg["material"], {}).get("gas_cost"))
        if seg["ending"] == "end":
            text = "interrupted: game over"
        elif scv is None:
            text = "interrupted: SCV lost"
        elif seg["ending"] == "stall" or (not seg["progress"] and not any(cost)):
            text = "cannot reach equipment"     # the game dropped the order without a single HP
            order["retry_at"] = self.state.game_loop + REPAIR_STALL_LOOPS
        else:
            text = "interrupted: bank empty" if dry else "interrupted: SCV stopped"
        order.update(state="waiting", reason=text, released=False)     # RELEASED again once a poll shows it
        self.report_repair(uuid, "RELEASED", text, **worker)
        self.log(f"repair of {seg['material']}: {text}")

    # --- events from the game -----------------------------------------------------------------
    async def on_unit_created(self, unit):
        self.confirm(unit)

    async def on_building_construction_started(self, unit):
        self.placing.pop(MATNR_BY_NAME.get(unit.type_id.name), None)

    async def on_building_construction_complete(self, unit):
        if unit.type_id == UnitTypeId.COMMANDCENTER and unit.tag not in self.plants:
            plant = new_plant(len(self.plants) + 1, unit.position, self.game_seconds)
            self.plants[unit.tag] = plant
            body = clean(plant)          # build on the game thread now; the worker thread must not touch game state
            self.enqueue(lambda: self.sap.post(f"Division({self.division_uuid})/_Plant", body))
        if unit.type_id == UnitTypeId.SUPPLYDEPOT:
            # ponytail: lowered for good, so the ramp wall stops no enemy either; raise on attack when it matters
            unit(AbilityId.MORPH_SUPPLYDEPOT_LOWER)
        self.confirm(unit)

    async def on_upgrade_complete(self, upgrade):
        matnr = MATNR_BY_NAME.get(upgrade.name)
        if matnr:
            self.confirm_item(matnr, 0, None, self.calculate_cost(upgrade))

    def confirm(self, unit):
        matnr = MATNR_BY_NAME.get(unit.type_id.name)
        if matnr is None or unit.tag in self.owned:     # not a material (MULE, larva…) or a starting unit
            return
        plant = self.nearest_plant(unit.position)
        self.owned[unit.tag] = (matnr, plant)
        self.confirm_item(matnr, unit.tag, plant, self.calculate_cost(unit.type_id))

    def confirm_item(self, matnr, tag, plant, cost):
        order = self.inflight.pop(matnr)
        self.post_event("101", matnr, 1, plant=plant, order=order, tag=tag, cost=cost)
        if order is None:
            self.log(f"{matnr}: unordered, 101 without order")
            return
        body = {"OrderStatus": "CONFIRMED", "ConfirmedAt": self.game_seconds, "UnitTag": tag}
        if plant:
            body["PlantUUID"] = plant
        self.patch_sap(f"ProdOrder({order})", body)
        self.log(f"{matnr}: confirmed, tag {tag}")

    def born_this_step(self):
        """Materials that appeared in this observation: python-sc2 reports deaths before births and upgrades."""
        return ({MATNR_BY_NAME.get(u.type_id.name) for u in self.units if u.tag not in self._units_previous_map}
                | {MATNR_BY_NAME.get(u.name) for u in self.state.upgrades - self._previous_upgrades})

    async def on_unit_destroyed(self, tag):
        """551 for what we owned; a dead producer's queue comes back in full; a site under construction is scrap.

        python-sc2 keeps the last snapshot (type, build progress, queue) in _structures_previous_map (spike 2026-09-24).
        """
        prev = self._structures_previous_map.get(tag)
        lost = lost_orders(prev.orders if prev else ())
        if lost and lost[0] in self.born_this_step():
            # ponytail: the head of the queue came out in this very step (built, not refunded); a same-type unit
            # born elsewhere this step also skips it, and reverse_stuck reverses that one 5-10 s later
            lost.pop(0)
        for matnr in lost:
            for uuid in self.inflight.drop_newest(matnr, 1):
                self.reverse(uuid, matnr, "producer destroyed, retried")
        if tag in self.owned:
            matnr, plant = self.owned.pop(tag)
            self.post_event("551", matnr, 1, plant=plant, tag=tag, cost=self.calculate_cost(item_id(matnr)))
            self.equipment_destroyed(tag)
            if tag in self.plants:
                self.plants[tag]["ClosedAt"] = self.game_seconds
                self.patch_sap(f"Plant({self.plants[tag]['PlantUUID']})", {"ClosedAt": self.game_seconds})
        elif prev is not None and prev.build_progress < 1:
            self.scrap_site(tag, prev)

    async def on_end(self, game_result):
        self.ended = True
        if self.sap_worker is None:
            print("no SAP worker (on_start failed)")
            return
        self.post_mining()              # income since the last 4-tick post
        self.pm_answers()
        if self.segment:                # a repair in work: what it cost up to the last observation is booked
            self.segment["ending"] = self.segment["ending"] or "end"
            self.settle()
        body = {"DurationSeconds": self.game_seconds}
        if game_result == Result.Victory:
            body["WinnerDivisionUUID"] = self.division_uuid
        self.patch_sap(f"Game({self.game_uuid})", body)
        result_name = "UNKNOWN" if self.leaving else RESULT_NAMES.get(game_result.name, "UNKNOWN")
        self.patch_sap(f"Division({self.division_uuid})", {"GameResult": result_name})
        self.sap_worker.drain()
        score = self.state.score
        print(f"reconciliation: 261-262 posted minerals {self.spent[0]} gas {self.spent[1]} | "
              f"game spent minerals {int(score.spent_minerals)} gas {int(score.spent_vespene)} | "
              f"SAP failures {self.sap_worker.failed} | queued {self.sap_worker.q.qsize()}")
        measured = measure(self.opening, self.state.common, score)
        pm = self.sap_worker.pm
        print(f"+ repair posted minerals {self.repair_posted[0]} gas {self.repair_posted[1]} | "
              f"exact measure minerals {measured[0]} gas {measured[1]}")
        print(f"+ PM unacknowledged {pm.unacknowledged()} | parked {len(pm.parked)}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--minutes", type=int, default=20, help="leave the game after this many game minutes")
    ap.add_argument("--map", default="AcropolisLE", help="map name under /Applications/StarCraft II/Maps")
    ap.add_argument("--difficulty", default="VeryEasy", choices=[d.name for d in Difficulty])
    args = ap.parse_args(argv)
    bot = Outpost(Sap(), args.map, args.minutes)
    try:
        bot.bootstrap()
    except SapError as e:
        sys.exit(str(e))
    replays = HERE.parent / "replays"
    replays.mkdir(exist_ok=True)
    try:
        run_game(maps.get(args.map),
                 [Bot(Race.Terran, bot), Computer(Race.Zerg, Difficulty[args.difficulty])],
                 realtime=True, save_replay_as=str(replays / f"{bot.game_uuid}.SC2Replay"))
    except ProtocolError as e:      # a surrendered game is already closed when python-sc2 asks for the replay
        print(f"replay not saved: {e}")
    except Exception as e:          # python-sc2 died mid-game (seen: ValueError on game end in realtime mode)
        print(f"python-sc2 failed: {e!r}")
    stop_sc2(bot.sc2_proc)
    if not bot.ended and bot.sap_worker is not None and hasattr(bot, "state"):
        asyncio.run(bot.on_end(Result.Undecided))   # still patch duration/result and drain the queue


if __name__ == "__main__":
    main()
