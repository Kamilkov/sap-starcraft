"""Runnable check for live_bot's SC2-free parts. Run: .venv/bin/python ingest/test_live_bot.py"""
import asyncio
import subprocess
import sys
import time
from types import SimpleNamespace

from sc2.ids.ability_id import AbilityId
from sc2.ids.unit_typeid import UnitTypeId
from sc2.ids.upgrade_id import UpgradeId
from sc2.position import Point2

import live_bot
from live_bot import (ADDON_PARENT, LOCK_RETRIES, MATNR_BY_NAME, TRAIN_INFO, UNIT_TRAINED_FROM, UPGRADE_BY_ABILITY,
                      WALL_FALLBACK, ZONES, Inflight, Outpost, SapWorker, event, game_matnr, game_payload, grid_candidates,
                      in_mining_lane, is_structure, item_id, lost_orders, mining_qty, new_plant, overlaps, placement_target,
                      queued_by_material, refund, stop_sc2, turret_anchor, unit_excess, values)
from parse_replay import LOOPS_PER_SECOND, STATS_INTERVAL_SECONDS, load_materials
from push import SapError

terran = [m for m, r in load_materials().items() if r["bukrs"] == "1000"]
assert len(terran) == 45, len(terran)
for m in terran:
    ident = item_id(m)
    assert isinstance(ident, (UnitTypeId, UpgradeId)), m
    assert MATNR_BY_NAME[ident.name] == m, (m, ident.name)
mats = load_materials()
assert all(mats[m]["produced_by"] for m in terran), "every Terran material has a producer"
assert mats["Marauder"]["prerequisite"] == "BarracksTechLab" and mats["Barracks"]["prerequisite"] == "SupplyDepot" and mats["Thor"]["prerequisite"] == "Armory" and mats["Ghost"]["prerequisite"] == "GhostAcademy" and mats["Battlecruiser"]["prerequisite"] == "FusionCore"
assert mats["MINERAL"]["produced_by"] == "" and mats["MINERAL"]["prerequisite"] == ""
# ZC_SCEBuildableMaterial casts these to char(28) / char(16) / int2 so the F4 columns fit the dialog
assert max(len(m) for m in mats) <= 28, "material name too long for the value-help cast"
assert max(len(r[c]) for r in mats.values() for c in ("produced_by", "prerequisite")) <= 16
assert max(r[c] for r in mats.values() for c in ("mineral_cost", "gas_cost", "supply_cost")) <= 32767
assert item_id("MINERAL") is None and item_id("NotAUnit") is None
assert all(parent in terran for parent in ADDON_PARENT.values())
assert is_structure("Barracks") and is_structure("BarracksTechLab") and not is_structure("Marine")
assert MATNR_BY_NAME[UnitTypeId.BARRACKSTECHLAB.name] == "BarracksTechLab"

inflight = Inflight()
inflight.add("Marine", "a")
inflight.add("Marine", "b")
assert inflight.pending("Marine") == 2 and inflight.pending("SCV") == 0
assert inflight.pop("Marine") == "a" and inflight.pop("Marine") == "b"
assert inflight.pop("Marine") is None and inflight.pop("SCV") is None
assert inflight.pending("Marine") == 0


class Cost:
    minerals, vespene = 100, 25


assert values("Marauder", Cost, 1) == (100, 25)
assert values("MINERAL", None, 40) == (40, 0) and values("VESPENE", None, 7) == (0, 7)
assert mining_qty(600) == round(600 * STATS_INTERVAL_SECONDS / 60) and mining_qty(0) == 0

e = event("101", "Marine", 1, 12, (50, 0), plant="p", order="o", tag=7)
assert e["EventSource"] == "LIVE" and e["MovementType"] == "101" and e["GameSeconds"] == 12
assert e["MineralValue"] == 50 and e["GasValue"] == 0 and e["PlantUUID"] == "p" and e["OrderUUID"] == "o"
assert e["UnitTag"] == 7 and len(e["EventUUID"]) == 36
raw = event("501", "MINERAL", 40, 7, (40, 0))
assert "PlantUUID" not in raw and "OrderUUID" not in raw, "None values are dropped like the parser does"


class Pos:
    x, y = 33.5, 120.25


plant = new_plant(1, Pos, 0)
assert plant["PlantCode"] == "0001" and plant["PosX"] == 33 and plant["PosY"] == 120 and plant["ClosedAt"] is None
assert new_plant(2, None, 9)["PosX"] == 0
g = game_payload("g", "d", "AcropolisLE", plant)
assert g["GameUUID"] == "g" and len(g["ReplayHash"]) == 40 and g["DurationSeconds"] == 0
d = g["_Division"][0]
assert d["DivisionUUID"] == "d" and d["CompanyCode"] == "1000" and d["DivisionCode"] == "LIVE"
assert d["_Plant"][0]["PlantCode"] == "0001" and "ClosedAt" not in d["_Plant"][0]
assert d["_ProdOrder"] == [] and d["_Event"] == []


class FakeSap:
    def __init__(self):
        self.calls, self.rows = [], [{"OrderUUID": "o1", "Material": "Marine"}]

    def get(self, path):
        self.calls.append(("GET", path))
        return self.rows

    get_all = get           # the maintenance order poll (test_pm.py)

    def post(self, path, body):
        self.calls.append(("POST", path))

    def patch(self, path, body):
        self.calls.append(("PATCH", path))


fake = FakeSap()
worker = SapWorker(fake, "div-1", poll_seconds=0.1)
assert worker.take_released() is None, "no poll finished yet"
worker.start()
worker.q.put(lambda: fake.post("a", {}))
worker.q.put(lambda: 1 / 0)
worker.q.put(lambda: fake.patch("b", {}))
time.sleep(0.6)
assert worker.failed == 1, worker.failed
assert [c for c in fake.calls if c[0] != "GET"] == [("POST", "a"), ("PATCH", "b")], "FIFO, failure skipped"
assert any("OrderStatus eq 'RELEASED'" in c[1] and "div-1" in c[1] for c in fake.calls if c[0] == "GET")
assert any("OrderStatus eq 'CANCELLING'" in c[1] for c in fake.calls if c[0] == "GET"), "cancel requests are polled too"
worker.drain(5)                      # stop polling first, so the second take_released cannot be refilled
assert not worker.is_alive()
assert worker.take_released() == fake.rows and worker.take_released() is None, "handed over once"

# HTTP 423 (Game locked by a Fiori action) is retried; any other error is dropped at once (above)
live_bot.LOCK_WAIT = 0.01


class Locked:
    status_code, text = 423, "locked"


def failing(times):
    calls = []

    def job():
        calls.append(1)
        if len(calls) <= times:
            raise SapError("POST", "Division(d)/_Event", Locked)
    return job, calls


flaky, flaky_calls = failing(2)
worker = SapWorker(FakeSap(), "div-2", poll_seconds=60)
worker.start()
worker.q.put(flaky)
worker.drain(5)
assert worker.failed == 0 and len(flaky_calls) == 3, (worker.failed, flaky_calls)
locked, locked_calls = failing(99)
worker = SapWorker(FakeSap(), "div-2", poll_seconds=60)
worker.start()
worker.q.put(locked)
worker.drain(5)
assert worker.failed == 1 and len(locked_calls) == LOCK_RETRIES + 1, (worker.failed, locked_calls)

# queue_unit: shortest queue, never into a producer that builds an addon, finished techlabs only, supply
for m in terran:
    if mats[m]["category"] == "UNIT":
        assert all(item_id(m) in TRAIN_INFO[t] for t in UNIT_TRAINED_FROM[item_id(m)]), m
MARINE = TRAIN_INFO[UnitTypeId.BARRACKS][UnitTypeId.MARINE]["ability"]


class Structure:
    def __init__(self, tag, orders=(), add_on_tag=0, type_id=UnitTypeId.BARRACKS):
        self.tag, self.type_id, self.add_on_tag, self.trained = tag, type_id, add_on_tag, []
        self.orders = [SimpleNamespace(ability=SimpleNamespace(exact_id=a)) for a in orders]

    def train(self, item):
        self.trained.append(item)
        return True


def bot(*ready, techlab_tags=(), busy=()):
    # the BotAI attributes queue_unit reads; `ready` are finished structures (techlabs included)
    return SimpleNamespace(structures=SimpleNamespace(ready=list(ready)), techlab_tags=set(techlab_tags),
                           unit_tags_received_action=set(busy), supply_left=10,
                           calculate_supply_cost=lambda u: mats[MATNR_BY_NAME[u.name]]["supply_cost"])


b1, b2 = Structure(1, [MARINE] * 3), Structure(2, [MARINE] * 2)
b3 = Structure(3, [AbilityId.BUILD_TECHLAB_BARRACKS])
stub = bot(b1, b2, b3)
assert Outpost.queue_unit(stub, UnitTypeId.MARINE) is True
assert b2.trained == [UnitTypeId.MARINE] and not b1.trained and not b3.trained, "shortest queue, addon build skipped"
assert stub.supply_left == 10 - mats["Marine"]["supply_cost"]
naked, plain = Structure(1), Structure(2, add_on_tag=12)
stub = bot(naked, plain, Structure(12, type_id=UnitTypeId.BARRACKSTECHLAB), techlab_tags={12})
assert Outpost.queue_unit(stub, UnitTypeId.MARINE) is True and naked.trained and not plain.trained, "techlab kept free"
naked, unfinished, teched = Structure(1), Structure(2, add_on_tag=11), Structure(3, [MARINE] * 2, add_on_tag=12)
stub = bot(naked, unfinished, teched, Structure(12, type_id=UnitTypeId.BARRACKSTECHLAB), techlab_tags={11, 12})
assert Outpost.queue_unit(stub, UnitTypeId.MARAUDER) is True
assert teched.trained == [UnitTypeId.MARAUDER] and not naked.trained and not unfinished.trained
assert stub.supply_left == 10 - mats["Marauder"]["supply_cost"]
assert Outpost.queue_unit(bot(naked, unfinished, techlab_tags={11}), UnitTypeId.MARAUDER) is False
assert Outpost.queue_unit(bot(Structure(1), Structure(2), busy={1, 2}), UnitTypeId.MARINE) is None
full = bot(Structure(1, [MARINE] * 5), Structure(2, [MARINE] * 5))
assert Outpost.queue_unit(full, UnitTypeId.MARINE) is False and full.supply_left == 10

# refused commands: units STARTED in SAP but missing from every production queue are reversed (262) and retried
SCV_TRAIN = TRAIN_INFO[UnitTypeId.COMMANDCENTER][UnitTypeId.SCV]["ability"]
assert queued_by_material([Structure(1, [MARINE, MARINE]), Structure(2, [SCV_TRAIN], type_id=UnitTypeId.COMMANDCENTER),
                           Structure(3, [AbilityId.BUILD_TECHLAB_BARRACKS])]) == {"Marine": 2, "SCV": 1}
assert unit_excess({"Marine": 3, "SCV": 1, "Barracks": 1, "Stimpack": 1}, {"Marine": 1, "SCV": 1}) == {"Marine": 2}, \
    "structures and research are never in a unit queue: not excess"
line = Inflight()
for uuid in "abc":
    line.add("Marine", uuid)
assert line.drop_newest("Marine", 2) == ["c", "b"] and line.pending("Marine") == 1, "the oldest is the queued one"
assert line.drop_newest("Marine", 5) == ["a"] and line.drop_newest("SCV", 1) == []

calls = []
stub = SimpleNamespace(posted={"o1": (100, 25), "o2": (50, 0)}, started={"o1", "o2"}, reasons={"o1": None},
                       spent=[150, 25], post_event=lambda *a, **k: calls.append((a, k)),
                       patch_sap=lambda path, body: calls.append((path, body)), log=lambda text: None)
stub.post_262 = lambda *a: Outpost.post_262(stub, *a)
Outpost.reverse(stub, "o1", "Marauder")
assert calls == [(("262", "MINERAL", 100), {"order": "o1"}), (("262", "VESPENE", 25), {"order": "o1"}),
                 ("ProdOrder(o1)", {"OrderStatus": "RELEASED", "StatusText": "command refused, retried"})], calls
assert stub.started == {"o2"} and "o1" not in stub.reasons and "o1" not in stub.posted and stub.spent == [50, 0]
calls.clear()
Outpost.reverse(stub, "o2", "Marine")
assert [c[0] for c in calls] == [("262", "MINERAL", 50), "ProdOrder(o2)"], "no gas cost, no VESPENE 262"
stub.posted["o3"] = (50, 0)
Outpost.reverse(stub, "o3", "Marine", "producer destroyed, retried")
assert calls[-1] == ("ProdOrder(o3)", {"OrderStatus": "RELEASED", "StatusText": "producer destroyed, retried"})

reversed_orders = []
stub = SimpleNamespace(inflight=Inflight(), issued={}, last_excess={},
                       reverse=lambda uuid, matnr: reversed_orders.append(uuid))
for uuid in "abc":
    stub.inflight.add("Marine", uuid)
    stub.issued[uuid] = 0
Outpost.reverse_stuck(stub, {"Marine": 1}, 200)
assert reversed_orders == [] and stub.last_excess == {"Marine": 2}, "one check is not enough"
Outpost.reverse_stuck(stub, {"Marine": 1}, 312)
assert reversed_orders == ["c", "b"] and stub.inflight.pending("Marine") == 1 and stub.last_excess == {}, \
    "second check in a row: reverse, newest first"
# an order younger than one check interval may just not be in the observation yet: never a suspect
stub = SimpleNamespace(inflight=Inflight(), issued={"a": 995, "b": 1110}, last_excess={},
                       reverse=lambda uuid, matnr: reversed_orders.append(uuid))
stub.inflight.add("Marine", "a")
Outpost.reverse_stuck(stub, {}, 1000)                   # a issued 5 loops ago, not visible yet
stub.inflight.add("Marine", "b")
Outpost.reverse_stuck(stub, {"Marine": 1}, 1112)        # a is queued now; b issued 2 loops ago, not visible yet
assert reversed_orders == ["c", "b"] and stub.last_excess == {}, "two different lagging orders are not a refusal"

# placement timeout: a structure order is reversed only when no SCV is on its way any more
reversed_orders = []
en_route = {UnitTypeId.BARRACKS: 1}
stub = SimpleNamespace(placing={"Barracks": 0}, state=SimpleNamespace(game_loop=int(30 * LOOPS_PER_SECOND) + 1),
                       inflight=Inflight(), worker_en_route_to_build=lambda item: en_route.get(item, 0),
                       reverse=lambda uuid, matnr: reversed_orders.append(uuid), log=lambda text: None)
stub.inflight.add("Barracks", "o9")
Outpost.timeout_placements(stub)
assert reversed_orders == [] and stub.placing == {"Barracks": 0}, "the SCV is still walking: not refused"
en_route.clear()
stub.placing["SupplyDepot"] = stub.state.game_loop      # sent just now
Outpost.timeout_placements(stub)
assert reversed_orders == ["o9"] and stub.placing == {"SupplyDepot": stub.state.game_loop}, \
    "30 s and no SCV on its way: reversed; a fresh placement waits"


# in-game cancel (spike 2026-09-24): CANCEL_LAST on the last queue item, CANCEL_BUILDINPROGRESS on a building,
# stop() on a walking SCV; a building under construction refunds 75% rounded up, everything else 100%
assert game_matnr("TechLab") == "BarracksTechLab" and game_matnr("Reactor") == "BarracksReactor"
assert game_matnr("Marine") == "Marine"
assert refund(150, 0, True) == (113, 0) and refund(50, 25, True) == (38, 19) and refund(100, 100, False) == (100, 100)


class Thing:
    def __init__(self, tag, type_id, orders=(), ready=True):
        self.tag, self.type_id, self.is_ready, self.commands = tag, type_id, ready, []
        self.build_progress = 1.0 if ready else 0.5
        self.orders = [SimpleNamespace(ability=SimpleNamespace(exact_id=a)) for a in orders]

    def __call__(self, ability):
        self.commands.append(ability)
        return True

    def stop(self):
        self.commands.append("stop")
        return True


class Things(list):
    def __call__(self, type_id):
        return Things(u for u in self if u.type_id == type_id)

    @property
    def not_ready(self):
        return Things(u for u in self if not u.is_ready)

    @property
    def first(self):
        return self[0]


REAPER = TRAIN_INFO[UnitTypeId.BARRACKS][UnitTypeId.REAPER]["ability"]
STIM, DEPOT = AbilityId.BARRACKSTECHLABRESEARCH_STIMPACK, AbilityId.TERRANBUILD_SUPPLYDEPOT
GAME_DATA = SimpleNamespace(
    units={UnitTypeId.SUPPLYDEPOT.value: SimpleNamespace(creation_ability=SimpleNamespace(exact_id=DEPOT)),
           UnitTypeId.BARRACKSTECHLAB.value: SimpleNamespace(
               creation_ability=SimpleNamespace(exact_id=AbilityId.BUILD_TECHLAB_BARRACKS))},
    upgrades={UpgradeId.STIMPACK.value: SimpleNamespace(research_ability=SimpleNamespace(exact_id=STIM))})


def world(structures=(), workers=(), placing=None, busy=()):
    return SimpleNamespace(structures=Things(structures), workers=Things(workers), placing=placing or {},
                           unit_tags_received_action=set(busy), game_data=GAME_DATA, cancelled_sites=set())


one, two = Thing(1, UnitTypeId.BARRACKS, [MARINE]), Thing(2, UnitTypeId.BARRACKS, [MARINE, MARINE])
reaper_last = Thing(3, UnitTypeId.BARRACKS, [MARINE, REAPER])
assert Outpost.cancel_command(world([one, two, reaper_last]), "Marine") == (None, False)
assert two.commands == [AbilityId.CANCEL_LAST] and not one.commands and not reaper_last.commands, \
    "a queued Marine, not the one in progress, never the one behind a Reaper"
assert Outpost.cancel_command(world([Thing(3, UnitTypeId.BARRACKS, [MARINE, REAPER])]), "Marine") == \
    ("not last in any queue", False)
assert Outpost.cancel_command(world([Thing(2, UnitTypeId.BARRACKS, [MARINE, MARINE])], busy={2}), "Marine") == \
    ("", False), "the producer got a command this frame: next frame"
assert Outpost.cancel_command(world([]), "Marine") == ("not found in the game", False)
lab = Thing(4, UnitTypeId.BARRACKSTECHLAB, [STIM])
assert Outpost.cancel_command(world([lab]), "Stimpack") == (None, False) and lab.commands == [AbilityId.CANCEL_LAST]
walker, miner = Thing(5, UnitTypeId.SCV, [DEPOT]), Thing(6, UnitTypeId.SCV)
walking = world(workers=[walker, miner], placing={"SupplyDepot": 0})
assert Outpost.cancel_command(walking, "SupplyDepot") == (None, False)
assert walker.commands == ["stop"] and not miner.commands and walking.placing == {}, "backlog resumes, no timeout reversal"
site = Thing(7, UnitTypeId.BARRACKS, ready=False)
built = world([Thing(8, UnitTypeId.BARRACKS), site])
assert Outpost.cancel_command(built, "Barracks") == (None, True)
assert site.commands == [AbilityId.CANCEL_BUILDINPROGRESS] and built.cancelled_sites == {7}, \
    "its death event must not scrap the next Barracks order"
assert Outpost.cancel_command(world([Thing(8, UnitTypeId.BARRACKS)]), "Barracks") == ("not found in the game", False)
labsite = Thing(9, UnitTypeId.BARRACKSTECHLAB, ready=False)
assert Outpost.cancel_command(world([labsite]), "BarracksTechLab") == (None, True)
assert labsite.commands == [AbilityId.CANCEL_BUILDINPROGRESS], "an add-on is cancelled on itself, not on its Barracks"

# answering SAP: success books the refund as 262 and sets CANCELLED; otherwise the reason goes back with the status
def answering(result):
    stub = SimpleNamespace(started={"o1"}, inflight=Inflight(), posted={"o1": (150, 0)}, issued={"o1": 0},
                           cancelled=set(), scrapped={}, spent=[150, 0], cancel_command=lambda matnr: result,
                           log=lambda text: None,
                           post_event=lambda *a, **k: calls.append((a, k)),
                           patch_sap=lambda path, body: calls.append((path, body)))
    stub.inflight.add("Barracks", "o1")
    stub.post_262 = lambda *a: Outpost.post_262(stub, *a)
    return stub


calls = []
stub = answering((None, True))
assert Outpost.answer_cancel(stub, "o1", "Barracks") is True
assert calls == [(("262", "MINERAL", 113), {"order": "o1"}),
                 ("ProdOrder(o1)", {"OrderStatus": "CANCELLED", "StatusText": "cancelled in game, refund 75%"})], calls
assert stub.inflight.pending("Barracks") == 0 and stub.posted == {} and stub.issued == {} and stub.spent == [37, 0]
assert "o1" in stub.started and stub.cancelled == {"o1"}, "never back into the backlog, never answered again"
calls.clear()
Outpost.answer_cancel(answering((None, False)), "o1", "Barracks")
assert calls[-1] == ("ProdOrder(o1)", {"OrderStatus": "CANCELLED", "StatusText": "cancelled in game, refund 100%"})
assert calls[0] == (("262", "MINERAL", 150), {"order": "o1"})
calls.clear()
stub = answering(("not last in any queue", False))
assert Outpost.answer_cancel(stub, "o1", "Barracks") is True
assert calls == [("ProdOrder(o1)", {"OrderStatus": "STARTED", "StatusText": "cannot cancel: not last in any queue"})]
assert stub.inflight.pending("Barracks") == 1 and stub.spent == [150, 0] and not stub.cancelled, "nothing refunded"
calls.clear()
stub = answering(("", False))
assert Outpost.answer_cancel(stub, "o1", "Barracks") is False and calls == [], "producer busy: try again next frame"
stub.inflight = Inflight()                              # the unit appeared meanwhile: confirm popped it
assert Outpost.answer_cancel(stub, "o1", "Barracks") is True
assert calls == [("ProdOrder(o1)", {"OrderStatus": "CONFIRMED", "StatusText": "cannot cancel: already built"})]
calls.clear()
stub.started = set()                                    # reversed a moment ago: its RELEASED PATCH wins
assert Outpost.answer_cancel(stub, "o1", "Barracks") is True and calls == []
calls.clear()
stub = answering(("", False))
stub.inflight, stub.scrapped = Inflight(), {"o1": "destroyed under construction"}   # died before the click arrived
assert Outpost.answer_cancel(stub, "o1", "Barracks") is True
assert calls == [("ProdOrder(o1)", {"OrderStatus": "SCRAPPED", "StatusText": "destroyed under construction"})], \
    "never 'already built'"

answers = []
stub = SimpleNamespace(started={"s1"}, answered=set(), cancelled=set(), backlog={}, cancels={})
stub.answer_cancel = lambda uuid, matnr: answers.append((uuid, matnr)) or stub.cancelled.add(uuid) or True   # success
rows = [{"OrderUUID": "r1", "Material": "Marine", "OrderStatus": "RELEASED"},
        {"OrderUUID": "s1", "Material": "Marine", "OrderStatus": "RELEASED"},       # started here, poll lagging
        {"OrderUUID": "c1", "Material": "TechLab", "OrderStatus": "CANCELLING"}]
Outpost.take_orders(stub, rows)
assert list(stub.backlog) == ["r1"] and list(stub.cancels) == ["c1"]
Outpost.answer_cancels(stub)
assert answers == [("c1", "BarracksTechLab")] and stub.answered == {"c1"}, "game material name, answered"
Outpost.answer_cancels(stub)
assert answers == [("c1", "BarracksTechLab")], "answered once per poll"
Outpost.take_orders(stub, rows)                         # the next poll still says CANCELLING: CANCELLED not applied yet
Outpost.answer_cancels(stub)
assert answers == [("c1", "BarracksTechLab")], "a success is never answered again (it would say 'already built')"
Outpost.take_orders(stub, rows[:2])                     # SAP applied the answer
assert stub.answered == set() and stub.cancelled == set()
refused = []
stub.answer_cancel = lambda uuid, matnr: refused.append(uuid) or True                                    # refusal
Outpost.take_orders(stub, rows)
Outpost.answer_cancels(stub)
Outpost.answer_cancels(stub)
assert refused == ["c1"], "a refusal is answered once per poll"
Outpost.take_orders(stub, rows)                         # still CANCELLING: a re-click, or the STARTED PATCH was dropped
Outpost.answer_cancels(stub)
assert refused == ["c1", "c1"], "a refusal is answered again by the next poll"
busy = SimpleNamespace(answered=set(), cancelled=set(), cancels={"c2": {"Material": "Marine"}},
                       answer_cancel=lambda uuid, matnr: False)
Outpost.answer_cancels(busy)
assert busy.answered == set(), "not answered yet: retried next frame"

# destroyed structures (spike 2026-09-24): a dead producer's queue comes back in full (reversed, retried);
# a site under construction gives back nothing, an add-on dying with its parent 75%
assert UPGRADE_BY_ABILITY[STIM] == "Stimpack"
assert {m for m in terran if mats[m]["category"] == "UPGRADE"} <= set(UPGRADE_BY_ABILITY.values())
assert lost_orders(Thing(1, UnitTypeId.BARRACKS, [MARINE, MARINE, REAPER]).orders) == ["Marine", "Marine", "Reaper"]
assert lost_orders(Thing(2, UnitTypeId.BARRACKSTECHLAB, [STIM]).orders) == ["Stimpack"]
assert lost_orders(Thing(3, UnitTypeId.BARRACKS, [AbilityId.BUILD_TECHLAB_BARRACKS]).orders) == [], \
    "an add-on under construction is lost as a site, not as production"


def dying(*snapshots, dead=()):
    stub = SimpleNamespace(_structures_previous_map={s.tag: s for s in snapshots}, owned={}, inflight=Inflight(),
                           state=SimpleNamespace(dead_units=set(dead), upgrades=set()), posted={}, issued={}, scrapped={},
                           units=[], _units_previous_map={}, _previous_upgrades=set(),
                           cancelled_sites=set(), spent=[0, 0], game_data=GAME_DATA, log=lambda text: None,
                           post_event=lambda *a, **k: calls.append((a, k)),
                           patch_sap=lambda path, body: calls.append((path, body)),
                           reverse=lambda uuid, matnr, text: calls.append(("reverse", uuid, matnr, text)),
                           equipment_destroyed=lambda tag: None)      # Plant Maintenance: test_pm.py
    stub.post_262 = lambda *a: Outpost.post_262(stub, *a)
    stub.scrap_site = lambda tag, prev: Outpost.scrap_site(stub, tag, prev)
    stub.born_this_step = lambda: Outpost.born_this_step(stub)
    return stub


def destroy(stub, tag):
    calls.clear()
    asyncio.run(Outpost.on_unit_destroyed(stub, tag))
    return calls


LOST = "producer destroyed, retried"
stub = dying(Thing(20, UnitTypeId.BARRACKS, [MARINE, MARINE, REAPER]), dead={20})
for uuid, matnr in (("m1", "Marine"), ("m2", "Marine"), ("m3", "Marine"), ("r1", "Reaper")):
    stub.inflight.add(matnr, uuid)
assert destroy(stub, 20) == [("reverse", "m3", "Marine", LOST), ("reverse", "m2", "Marine", LOST),
                             ("reverse", "r1", "Reaper", LOST)], calls
assert stub.inflight.pending("Marine") == 1, "the oldest Marine is queued elsewhere"
stub = dying(Thing(21, UnitTypeId.BARRACKSTECHLAB, [STIM]), dead={21})
stub.inflight.add("Stimpack", "s1")
assert destroy(stub, 21) == [("reverse", "s1", "Stimpack", LOST)], "research is refunded too"
# python-sc2 reports deaths before births: the head of the queue may have come out in this very step
stub = dying(Thing(30, UnitTypeId.BARRACKS, [MARINE, MARINE]), dead={30})
stub.units = [Thing(31, UnitTypeId.MARINE)]
for uuid in ("f1", "f2"):
    stub.inflight.add("Marine", uuid)
assert destroy(stub, 30) == [("reverse", "f2", "Marine", LOST)], "the finished Marine is built, not refunded"
assert stub.inflight.pending("Marine") == 1, "f1 is left for confirm()"
stub = dying(Thing(32, UnitTypeId.BARRACKSTECHLAB, [STIM]), dead={32})
stub.state.upgrades = {UpgradeId.STIMPACK}
stub.inflight.add("Stimpack", "s2")
assert destroy(stub, 32) == [] and stub.inflight.pending("Stimpack") == 1, "research completed in the same step"
stub = dying(Thing(29, UnitTypeId.BARRACKS, [MARINE]), dead={29})
stub.owned[29], stub.calculate_cost, stub.plants = ("Barracks", "p1"), (lambda item: Cost), {}
stub.inflight.add("Marine", "m9")
assert [c[0] for c in destroy(stub, 29)] == ["reverse", ("551", "Barracks", 1)], "queue refunded and the building lost"

stub = dying(Thing(22, UnitTypeId.SUPPLYDEPOT, ready=False), dead={22})
stub.inflight.add("SupplyDepot", "d1")
stub.posted["d1"], stub.issued["d1"] = (100, 0), 5
assert destroy(stub, 22) == [("ProdOrder(d1)", {"OrderStatus": "SCRAPPED",
                                                "StatusText": "destroyed under construction"})], calls
assert stub.scrapped == {"d1": "destroyed under construction"} and stub.posted == {} and stub.issued == {}
assert stub.inflight.pending("SupplyDepot") == 0 and stub.spent == [0, 0], "nothing refunded, no 262"

stub = dying(Thing(23, UnitTypeId.BARRACKSTECHLAB, ready=False),
             Thing(24, UnitTypeId.BARRACKS, [AbilityId.BUILD_TECHLAB_BARRACKS]), dead={23, 24})
stub.inflight.add("BarracksTechLab", "t1")
stub.posted["t1"], stub.spent = (50, 25), [50, 25]
assert destroy(stub, 23) == [(("262", "MINERAL", 38), {"order": "t1"}), (("262", "VESPENE", 19), {"order": "t1"}),
                             ("ProdOrder(t1)", {"OrderStatus": "SCRAPPED",
                                                "StatusText": "destroyed with its Barracks, refund 75%"})], calls
assert stub.spent == [12, 6]
stub = dying(Thing(25, UnitTypeId.BARRACKSTECHLAB, ready=False),
             Thing(26, UnitTypeId.BARRACKS, [AbilityId.BUILD_TECHLAB_BARRACKS]), dead={25})
stub.inflight.add("BarracksTechLab", "t2")
assert destroy(stub, 25) == [("ProdOrder(t2)", {"OrderStatus": "SCRAPPED",
                                                "StatusText": "destroyed under construction"})], \
    "parent alive: the add-on alone gives nothing back"

stub = dying(Thing(27, UnitTypeId.BARRACKS, ready=False), dead={27})
stub.cancelled_sites.add(27)
stub.inflight.add("Barracks", "n1")                     # the next Barracks order is already in flight
assert destroy(stub, 27) == [] and stub.inflight.pending("Barracks") == 1 and stub.cancelled_sites == set(), \
    "our own cancel: answer_cancel booked it"
stub = dying(Thing(28, UnitTypeId.SUPPLYDEPOT, ready=False), dead={28})
assert destroy(stub, 28) == [] and stub.scrapped == {}, "a site without an order is only logged"

# return_idle_workers: each idle SCV goes to the minerals of its nearest base (positions on a line)
class Spot(SimpleNamespace):
    def gather(self, target):
        self.gathered = target
        return True


class Group(list):
    def closest_to(self, unit):
        return min(self, key=lambda other: abs(other.position - unit.position))


west, east = Spot(position=0), Spot(position=100)
west_minerals, east_minerals = Spot(position=5), Spot(position=95)
near_east, near_west = Spot(position=90, gathered=None), Spot(position=10, gathered=None)
Spot.tag = 0                # the selectors compare tags with the reserved SCVs (test_pm.py); nobody is reserved here
FREE = {"reserved": {}, "unit_tags_received_action": set()}
world = SimpleNamespace(workers=SimpleNamespace(idle=Group([near_east, near_west])), townhalls=Group([west, east]),
                        mineral_field=Group([west_minerals, east_minerals]), **FREE)
assert Outpost.return_idle_workers(world) == 2
assert near_east.gathered is east_minerals and near_west.gathered is west_minerals
world.workers.idle = Group([])
assert Outpost.return_idle_workers(world) == 0
lost = Spot(position=50, gathered=None)
assert Outpost.return_idle_workers(SimpleNamespace(workers=SimpleNamespace(idle=Group([lost])), townhalls=Group([]),
                                                   mineral_field=Group([west_minerals]), **FREE)) == 0 and lost.gathered is None

# staff_refineries: a ready refinery next to a base gets the nearest free mineral miners up to its ideal harvesters
Spot.distance_to = lambda self, other: abs(self.position - other.position)
Group.tags = property(lambda self: {u.tag for u in self})
Group.closest_distance_to = lambda self, unit: min(abs(o.position - unit.position) for o in self)
west_minerals.tag, east_minerals.tag = 1, 2
def miner(pos, **kw):
    return Spot(position=pos, gathered=None, **{"is_gathering": True, "order_target": 1, "is_carrying_resource": False, **kw})
short, full, lonely = (Spot(position=p, tag=t, assigned_harvesters=a, ideal_harvesters=3)
                       for p, t, a in ((7, 11, 1), (3, 12, 3), (60, 13, 0)))
m1, m2, far = miner(20), miner(30), miner(58)
carrying, builder, on_gas = miner(6, is_carrying_resource=True), miner(9, is_gathering=False), miner(10, order_target=11)
world = SimpleNamespace(townhalls=SimpleNamespace(ready=Group([west, east])), gas_buildings=SimpleNamespace(ready=Group([short, full, lonely])),
                        workers=Group([m1, m2, far, carrying, builder, on_gas]), mineral_field=Group([west_minerals, east_minerals]),
                        **FREE)
assert Outpost.staff_refineries(world) == 2
assert m1.gathered is short and m2.gathered is short, "the two nearest free miners go to the short refinery"
assert far.gathered is carrying.gathered is builder.gathered is on_gas.gathered is None, \
    "no base next to the lonely refinery; carriers, builders and gas workers stay"
m1.order_target = m2.order_target = short.tag           # SC2's assigned_harvesters lags the order by a check
m3 = miner(25)
world.workers = Group([m1, m2, m3, on_gas])                 # on_gas is the builder, already on the refinery
assert Outpost.staff_refineries(world) == 0 and m3.gathered is None, "SCVs already sent count as assigned"
world.workers = Group([])
assert Outpost.staff_refineries(world) == 0
world.townhalls.ready = Group([])
assert Outpost.staff_refineries(world) == 0

# trim_refineries: the SCV that built a refinery starts harvesting after the bot has sent three; the surplus goes back
# to minerals, one per refinery and check, and not again before the game's count has caught up
crowded = Spot(position=7, tag=21, assigned_harvesters=4, ideal_harvesters=3)
g1, g2, loaded = miner(8, order_target=21), miner(9, order_target=21), miner(7, order_target=21, is_carrying_resource=True)
world = SimpleNamespace(townhalls=Group([west, east]), gas_buildings=SimpleNamespace(ready=Group([crowded, full])),
                        workers=Group([loaded, g1, g2, m3]), mineral_field=Group([west_minerals, east_minerals]),
                        state=SimpleNamespace(game_loop=1000), gas_trimmed={}, **FREE)
assert Outpost.trim_refineries(world) == 1
assert g1.gathered is west_minerals and g2.gathered is loaded.gathered is None, "one SCV without cargo leaves"
assert Outpost.trim_refineries(world) == 0, "the game's count lags: no second trim right away"
world.state.game_loop = 1000 + live_bot.GAS_TRIM_WAIT_LOOPS
crowded.assigned_harvesters = 3
assert Outpost.trim_refineries(world) == 0 and g2.gathered is None, "three is what it needs"

# placement (spec 2026-09-25): zones, grid candidates, mining lanes, wall slots, turret base
def P(x, y):
    return Point2((x, y))


assert all(m in ZONES for m in terran if is_structure(m) and m not in ADDON_PARENT), "every Terran structure has a zone"
here = P(10.2, 10.7)
c3 = grid_candidates(here, 3, radius=2)
assert c3[0] == P(10.5, 10.5) and all(p.x % 1 == 0.5 and p.y % 1 == 0.5 for p in c3), "3x3 centres on .5"
assert c3 == sorted(c3, key=lambda p: p.distance_to(here)) and all(p.distance_to(here) <= 2 for p in c3)
c2 = grid_candidates(here, 2, radius=2)
assert c2[0] == P(10, 11) and all(p.x % 1 == 0 and p.y % 1 == 0 for p in c2), "2x2 centres on whole numbers"
cc, patch = P(0, 0), P(7, 0)
assert in_mining_lane(P(3.5, 0), 2, cc, [patch]), "between the Command Center and a patch"
assert not in_mining_lane(P(10, 0), 2, cc, [patch]), "3 tiles past the patch"
assert not in_mining_lane(P(3.5, 3.8), 2, cc, [patch]) and in_mining_lane(P(3.5, 3.8), 5, cc, [patch]), \
    "a bigger building widens the margin"
LAYOUT = {"WALL_DEPOTS": [P(10, 10), P(13, 7)], "WALL_BARRACKS": [P(9.5, 7.5)], "FRONT": P(20, 20),
          "NATURAL": P(45, 45), "NATURAL_FRONT": P(40, 40), "BEHIND_MINERALS": P(0, 0), "PRODUCTION": P(30, 30),
          "TECH": P(5, 5)}
T = P(1, 1)     # the turret anchor the bot computes
assert placement_target("SupplyDepot", LAYOUT, [], False, T) == ("WALL", P(10, 10), True)
assert placement_target("SupplyDepot", LAYOUT, [P(10, 10)], False, T) == ("WALL", P(13, 7), True)
assert placement_target("SupplyDepot", LAYOUT, [P(10, 10), P(13, 7)], False, T) == ("BEHIND_MINERALS", P(0, 0), False)
assert placement_target("SupplyDepot", LAYOUT, [P(13, 7), P(10.4, 9.6)], False, T)[0] == "BEHIND_MINERALS", \
    "a structure within 1 tile takes the slot"
assert placement_target("SupplyDepot", LAYOUT, [P(13, 7)], False, T) == ("WALL", P(10, 10), True), \
    "a destroyed wall depot's slot is rebuilt"
bare = dict(LAYOUT, WALL_DEPOTS=[], WALL_BARRACKS=[])
assert placement_target("SupplyDepot", bare, [], False, T) == ("BEHIND_MINERALS", P(0, 0), False), "no wall on this map"
assert placement_target("Barracks", bare, [], False, T) == ("PRODUCTION", P(30, 30), False)
assert placement_target("Barracks", LAYOUT, [], False, T) == ("WALL", P(9.5, 7.5), True)
assert placement_target("Barracks", LAYOUT, [P(9.5, 7.5)], False, T) == ("PRODUCTION", P(30, 30), False)
assert placement_target("Factory", LAYOUT, [], False, T) == ("PRODUCTION", P(30, 30), False)
assert placement_target("Starport", LAYOUT, [], False, T) == ("PRODUCTION", P(30, 30), False)
assert placement_target("Bunker", LAYOUT, [], False, T) == ("FRONT", P(20, 20), False), "behind the main wall"
assert placement_target("Bunker", LAYOUT, [], True, T) == ("FRONT", P(40, 40), False), "the natural is ours"
assert placement_target("Bunker", dict(LAYOUT, NATURAL_FRONT=None), [], True, T) == ("FRONT", P(20, 20), False), \
    "no natural front computed: the main front"
assert placement_target("MissileTurret", LAYOUT, [], False, T) == ("MINERAL_LINE", T, False)
for m in ("EngineeringBay", "Armory", "FusionCore", "GhostAcademy", "SensorTower"):
    assert placement_target(m, LAYOUT, [], False, T) == ("TECH", P(5, 5), False), m
bases = [(P(0, 0), P(8, 0)), (P(50, 0), P(58, 0))]
assert turret_anchor(bases, []) == P(4, 0), "main first"
assert turret_anchor(bases, [P(4, 0)]) == P(54, 0), "the base with the fewest turrets"
assert turret_anchor(bases, [P(4, 0), P(54, 0)]) == P(4, 0), "a tie goes to the main"

# placing a structure: exactly its zone's spot (max_distance=0), or the bot message why it waits
built = []


def placer(spot=None, ok=True, expansion=None):
    async def build(item, near, max_distance):
        built.append((item, near, max_distance))
        return ok

    async def find_spot(item, zone, target):
        return spot

    async def get_next_expansion():
        return expansion

    return SimpleNamespace(layout=LAYOUT, structures=Things(), natural_ours=lambda: False, turret_target=lambda: T,
                           build=build, find_spot=find_spot, get_next_expansion=get_next_expansion)


assert asyncio.run(Outpost.place(placer(), "SupplyDepot", UnitTypeId.SUPPLYDEPOT)) is True
assert built == [(UnitTypeId.SUPPLYDEPOT, P(10, 10), 0)], "the wall slot itself, no search"
built.clear()
assert asyncio.run(Outpost.place(placer(spot=P(6, 6)), "EngineeringBay", UnitTypeId.ENGINEERINGBAY)) is True
assert built == [(UnitTypeId.ENGINEERINGBAY, P(6, 6), 0)], "the searched spot, exactly"
built.clear()
assert asyncio.run(Outpost.place(placer(), "EngineeringBay", UnitTypeId.ENGINEERINGBAY)) == "no placement in TECH"
assert built == [], "no spot: nothing built"
assert asyncio.run(Outpost.place(placer(ok=False), "SupplyDepot", UnitTypeId.SUPPLYDEPOT)) == "no placement in WALL", \
    "an SCV on the slot: the order waits"
assert built == [(UnitTypeId.SUPPLYDEPOT, P(10, 10), 0)], "and the next pass tries the same slot"
built.clear()
assert asyncio.run(Outpost.place(placer(expansion=P(45, 45)), "CommandCenter", UnitTypeId.COMMANDCENTER)) is True
assert built == [(UnitTypeId.COMMANDCENTER, P(45, 45), 0)]
assert asyncio.run(Outpost.place(placer(), "CommandCenter", UnitTypeId.COMMANDCENTER)) == "no free expansion"
assert max(len(f"no placement in {z}") for z in set(ZONES.values()) | set(WALL_FALLBACK.values())) <= 50


async def no_spot(matnr, item):
    return "no placement in WALL"


waiting = SimpleNamespace(started=set(), reasons={}, inflight=Inflight(), can_afford=lambda item: True,
                          tech_requirement_progress=lambda item: 1, issue_unit=no_spot)
assert asyncio.run(Outpost.execute(waiting, {"OrderUUID": "p1", "Material": "SupplyDepot"})) == "no placement in WALL"
assert waiting.started == set(), "stays RELEASED, retried next pass"

depot, rax = Thing(60, UnitTypeId.SUPPLYDEPOT), Thing(61, UnitTypeId.BARRACKS)
finisher = SimpleNamespace(plants={}, confirm=lambda unit: None)
asyncio.run(Outpost.on_building_construction_complete(finisher, depot))
asyncio.run(Outpost.on_building_construction_complete(finisher, rax))
assert depot.commands == [AbilityId.MORPH_SUPPLYDEPOT_LOWER] and rax.commands == [], "every finished depot is lowered"
stub = dying(Thing(62, UnitTypeId.SUPPLYDEPOTLOWERED), dead={62})
stub.owned, stub.plants, stub.calculate_cost = {62: ("SupplyDepot", "p")}, {}, lambda item: Cost
assert destroy(stub, 62)[0][0][:2] == ("551", "SupplyDepot"), "a lowered depot dies as a SupplyDepot (by tag)"

# final review fixes: the add-on goes on the building's right (add_on_position), and searches keep it free
checked = []


async def room_at(item, pos):
    checked.append(pos)
    return pos == P(45, 124)


wall_rax = SimpleNamespace(has_add_on=False, add_on_position=P(45, 124), add_on_land_position=P(40, 125),
                           build=lambda item: True)
barracks_only = SimpleNamespace(structures=lambda t: SimpleNamespace(ready=SimpleNamespace(idle=[wall_rax])),
                                can_place_single=room_at)
assert asyncio.run(Outpost.issue_unit(barracks_only, "BarracksTechLab", UnitTypeId.BARRACKSTECHLAB)) is True
assert checked == [P(45, 124)], "room is checked where the add-on goes, not where a Barracks would land on it"
assert overlaps(P(139.5, 39.5), 3, P(139, 39), 2) and not overlaps(P(139.5, 41.5), 3, P(139, 39), 2)


def searching(has_add_on):
    async def can_place(item, spots):
        return [True] * len(spots)

    rax2 = SimpleNamespace(add_on_position=P(139, 39), has_add_on=has_add_on)
    return SimpleNamespace(game_data=SimpleNamespace(units={UnitTypeId.STARPORT.value: SimpleNamespace(footprint_radius=1.5)}),
                           townhalls=SimpleNamespace(closest_to=lambda t: SimpleNamespace(position=P(0, 0))),
                           resources=SimpleNamespace(closer_than=lambda d, b: []), can_place=can_place,
                           structures=SimpleNamespace(of_type=lambda types: [rax2]))


spot = asyncio.run(Outpost.find_spot(searching(False), UnitTypeId.STARPORT, "PRODUCTION", P(139.5, 39.5)))
assert spot is not None and not overlaps(spot, 3, P(139, 39), 2), f"a Barracks' add-on spot stays free: {spot}"
assert asyncio.run(Outpost.find_spot(searching(True), UnitTypeId.STARPORT, "PRODUCTION", P(139.5, 39.5))) == \
    P(139.5, 39.5), "once its add-on stands, the spot is free again"

# stop_sc2: a leftover process that ignores SIGTERM (like the macOS SC2 client) still gets killed
stubborn = subprocess.Popen([sys.executable, "-c", "import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN);"
                             " print('ready', flush=True); time.sleep(30)"], stdout=subprocess.PIPE, text=True)
stubborn.stdout.readline()
stop_sc2(stubborn, grace=0.5)
assert stubborn.poll() is not None, "SIGTERM-ignoring process must be killed after the grace period"
stubborn.stdout.close()
done = subprocess.Popen([sys.executable, "-c", "pass"])
done.wait()
stop_sc2(done)          # already exited: no-op
stop_sc2(None)          # on_start never ran: no-op

print("ok: 45 materials mapped, inflight, values, payloads, worker, 423 retry, queue_unit, reversal, cancel, destroyed, stop_sc2, placement")
