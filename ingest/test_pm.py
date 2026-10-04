"""Runnable check of Plant Maintenance in live_bot (spec 2026-09-27): SCV reservation, the PM outbox against a
fake SAP that fails on demand, damage check, eligibility, the repair watch and its exact cost.
No SAP, no StarCraft II. Run: .venv/bin/python ingest/test_pm.py
"""
import asyncio
import re
from types import SimpleNamespace

from sc2.data import Result
from sc2.ids.ability_id import AbilityId

import live_bot
from live_bot import (REPAIR_GRACE_LOOPS, REPAIR_STALL_LOOPS, Outpost, PmOutbox, SapWorker, free_workers,
                      holds_repair, is_final, measure, norm, priority, sap_message)
from push import Sap, SapError

live_bot.LOCK_WAIT = 0.01
DIV = "11111111-1111-1111-1111-111111111111"
GATHER, REPAIR = AbilityId.HARVEST_GATHER, AbilityId.EFFECT_REPAIR_SCV

# --- helpers ------------------------------------------------------------------------------------
assert [priority(h, 400) for h in (0, 133, 134, 266, 267, 399)] == ["1", "1", "2", "2", "3", "3"], "thirds of the health"
assert norm(None) == norm("") == norm(0) == norm("00000000-0000-0000-0000-000000000000") == ""
assert norm("13") == norm(13) == 13 and norm("AB-cd") == "ab-cd"
assert sap_message('POST x -> HTTP 400\n{"error":{"code":"A/1","message":"Order already CANCELLED"}}') == "Order already CANCELLED"
assert is_final({"body": {"OrderStatus": "CONFIRMED"}}) and is_final({"body": {"NotificationStatus": "CLOSED"}})
assert not is_final({"body": {"OrderStatus": "STARTED"}}) and not is_final({"body": {"NotificationStatus": ""}})


def bank(minerals, gas, collected=(0, 0), spent=(0, 0)):
    return (SimpleNamespace(minerals=minerals, vespene=gas),
            SimpleNamespace(collected_minerals=collected[0], collected_vespene=collected[1],
                            spent_minerals=spent[0], spent_vespene=spent[1]))


assert measure((50, 0), *bank(50, 0)) == (0, 0)
assert measure((50, 0), *bank(180, 40, collected=(400, 60), spent=(250, 20))) == (20, 0), "mined 400, spent 250, repaired 20"
assert measure((50, 0), *bank(80, 40, collected=(400, 60), spent=(350, 20))) == (20, 0), "production moves no R"


def order(ability, target=None):
    return SimpleNamespace(ability=SimpleNamespace(id=ability, exact_id=ability), target=target)


assert holds_repair(SimpleNamespace(orders=[order(REPAIR, 7)]), 7)
assert holds_repair(SimpleNamespace(orders=[order(AbilityId.EFFECT_REPAIR, 7)]), 7)
assert not holds_repair(SimpleNamespace(orders=[order(REPAIR, 8)]), 7), "a repair of something else"
assert not holds_repair(SimpleNamespace(orders=[order(GATHER, 7)]), 7) and not holds_repair(SimpleNamespace(orders=[]), 7)


# --- the game, faked ------------------------------------------------------------------------------
class Unit(SimpleNamespace):
    """A structure, an SCV or a mineral field on a line; commands are recorded, not executed."""

    def __init__(self, tag, position=0, **kw):
        super().__init__(**{"tag": tag, "position": position, "commands": [], "orders": [], "health": 400,
                            "health_max": 400, "is_flying": False, "is_ready": True, "is_carrying_resource": False,
                            **kw})

    is_idle = property(lambda self: not self.orders)
    is_gathering = property(lambda self: bool(self.orders) and self.orders[0].ability.exact_id == GATHER)
    order_target = property(lambda self: self.orders[0].target if self.orders else None)

    def distance_to(self, other):
        return abs(self.position - getattr(other, "position", other))

    def repair(self, target):
        self.commands.append(("repair", target.tag))

    def gather(self, target):
        self.commands.append(("gather", target.tag))

    def stop(self):
        self.commands.append(("stop",))


class Units(list):
    ready = property(lambda self: Units(u for u in self if u.is_ready))
    idle = property(lambda self: Units(u for u in self if u.is_idle))
    tags = property(lambda self: {u.tag for u in self})

    def find_by_tag(self, tag):
        return next((u for u in self if u.tag == tag), None)

    def closest_to(self, unit):
        return min(self, key=lambda other: abs(other.position - unit.position))

    def closest_distance_to(self, unit):
        return min(abs(other.position - unit.position) for other in self)


PATCH = 900         # tag of the mineral field


def miner(tag, position):
    return Unit(tag, position, orders=[order(GATHER, PATCH)])


# --- SAP, faked: the rules of the backend the bot depends on, and faults on demand -----------------
class Lost(Exception):
    """No answer: timeout or connection lost."""


def refusal(status, message):
    text = '{"error":{"code":"SABP_BEHV/100","message":"%s"}}' % message
    return SapError("POST", "x", SimpleNamespace(status_code=status, text=text))


class FakeSap:
    def __init__(self, receipts=()):
        self.notifications, self.orders, self.events = {}, {}, {}
        self.receipts = set(receipts)   # tags with a receipt in the ledger
        self.calls = []                 # every POST: (path, body)
        self.gets = []
        self.faults = []                # per POST, in order: "lost" (not applied), "late" (applied, no answer), HTTP status
        self.away = False               # SAP does not answer at all

    def post(self, path, body):
        self.calls.append((path, dict(body)))
        fault = self.faults.pop(0) if self.faults else None
        if self.away or fault == "lost":
            raise Lost("no answer")
        if isinstance(fault, int):
            raise refusal(fault, "fault")
        row = self.apply(path, body)
        if fault == "late":
            raise Lost("answer lost")
        return dict(row) if row else None

    def patch(self, path, body):
        pass

    def get_all(self, path):
        return self.get(path)       # the pages themselves: see the check of Sap.get_all

    def get(self, path):
        self.gets.append(path)
        if self.away:
            raise Lost("no answer")
        entity = path.split("?")[0]
        rows = list({"Notification": self.notifications, "MaintOrder": self.orders, "Event": self.events,
                     "ProdOrder": {}}[entity].values())
        key = re.search(r"(NotificationUUID|OrderUUID|EventUUID) eq ([\w-]+)", path)
        if key:
            rows = [r for r in rows if r[key.group(1)] == key.group(2)]
        tag = re.search(r"UnitTag eq (\d+)", path)
        if tag:
            rows = [r for r in rows if r["UnitTag"] == int(tag.group(1)) and r["NotificationStatus"] != "CLOSED"]
        if "OrderStatus eq 'RELEASED'" in path:
            rows = sorted((r for r in rows if r["OrderStatus"] in ("RELEASED", "CANCELLING")), key=lambda r: r["OrderUUID"])
        page = re.search(r"\$top=(\d+)&\$skip=(\d+)", path)
        if page:
            rows = rows[int(page.group(2)):int(page.group(2)) + int(page.group(1))]
        return [dict(r) for r in rows]

    def apply(self, path, body):
        if path.endswith("/_Event"):
            if body["EventUUID"] in self.events:
                raise refusal(400, "Resource already exists")
            self.events[body["EventUUID"]] = {"DivisionUUID": DIV, "PlantUUID": None, "OrderUUID": None, **body}
            return self.events[body["EventUUID"]]
        if path.endswith("/_Notification"):
            uuid, tag = body["NotificationUUID"], body["UnitTag"]
            if uuid in self.notifications:
                raise refusal(400, "Resource already exists")
            if tag not in self.receipts:
                raise refusal(400, f"Equipment {tag} unknown")
            if any(n["UnitTag"] == tag and n["NotificationStatus"] != "CLOSED" for n in self.notifications.values()):
                raise refusal(400, "Open notification exists")
            self.notifications[uuid] = {"DivisionUUID": DIV, "ClosedAt": 0, **body, "NotificationStatus": "OPEN"}
            return self.notifications[uuid]
        key = re.search(r"\(([\w-]+)\)", path).group(1)
        if path.endswith("reportNotification"):
            return self.report_notification(key, body)
        return self.report_repair(key, body)

    def report_notification(self, key, body):
        row = self.notifications.get(key)
        if row is None:
            raise refusal(404, "Not found")
        mine = [o for o in self.orders.values() if o["NotificationUUID"] == key]
        if body["NotificationStatus"] not in ("", "CLOSED") or not 0 <= body["Health"] <= body["HealthMax"] \
                or body["Priority"] not in "123":
            raise refusal(400, "cannot be reported")
        if row["NotificationStatus"] == "CLOSED":
            if body["NotificationStatus"] == "CLOSED":
                return row
            raise refusal(400, "Notification already CLOSED")
        if body["NotificationStatus"] == "CLOSED":
            if any(o["OrderStatus"] in ("STARTED", "CANCELLING") for o in mine):
                raise refusal(400, "Repair in work: report the repair")
            for o in mine:
                if o["OrderStatus"] == "RELEASED":
                    o.update(OrderStatus="CANCELLED", StatusText=body["StatusText"])
            row.update(NotificationStatus="CLOSED", ClosedAt=body["AtSeconds"])
        row.update(Priority=body["Priority"], Health=body["Health"], StatusText=body["StatusText"])
        return row

    def report_repair(self, key, body):
        row = self.orders.get(key)
        if row is None:
            raise refusal(404, "Not found")
        old, new, outcome = row["OrderStatus"], body["OrderStatus"], body["NotificationOutcome"]
        if new not in ("RELEASED", "STARTED", "CONFIRMED", "CANCELLED"):
            raise refusal(400, f"Status {new} cannot be reported")
        if old != new and old in ("CONFIRMED", "CANCELLED"):
            raise refusal(400, f"Order already {old}")
        if old != new and old == "CANCELLING" and new not in ("CANCELLED", "CONFIRMED"):
            raise refusal(400, f"Cancel requested: {new} refused")
        if outcome not in {"CONFIRMED": ("", "CLOSED"), "CANCELLED": ("OPEN", "CLOSED")}.get(new, ("",)):
            raise refusal(400, f"Outcome {outcome} does not fit {new}")
        if body["WorkerTag"] and body["WorkerTag"] not in self.receipts:
            raise refusal(400, f"SCV {body['WorkerTag']} unknown")
        if old == new and old in ("CONFIRMED", "CANCELLED"):
            return row          # a finished order reported again: HTTP 200, nothing written
        row.update(OrderStatus=new, StatusText=body["StatusText"], WorkerTag=body["WorkerTag"] or row["WorkerTag"],
                   StartedAt=body["StartedAt"] or row["StartedAt"],
                   ConfirmedAt=body["AtSeconds"] if new == "CONFIRMED" else row["ConfirmedAt"])
        n = self.notifications[row["NotificationUUID"]]
        if new in ("CONFIRMED", "CANCELLED") and n["NotificationStatus"] != "CLOSED":
            closes = new == "CONFIRMED" or outcome == "CLOSED"
            n.update(NotificationStatus="CLOSED" if closes else "OPEN", ClosedAt=body["AtSeconds"] if closes else 0,
                     StatusText="repaired" if new == "CONFIRMED" else body["StatusText"])
        return row

    # what the player does in Fiori
    def create_order(self, notification, uuid):
        n = self.notifications[notification]
        assert n["NotificationStatus"] == "OPEN", n
        n["NotificationStatus"] = "IN_PROCESS"
        self.orders[uuid] = {"OrderUUID": uuid, "DivisionUUID": DIV, "NotificationUUID": notification,
                             "UnitTag": n["UnitTag"], "Material": n["Material"], "OrderStatus": "RELEASED",
                             "Priority": n["Priority"], "ReportedAt": n["ReportedAt"], "WorkerTag": 0, "StartedAt": 0,
                             "ConfirmedAt": 0, "StatusText": ""}
        return uuid

    def cancel_order(self, uuid):
        o = self.orders[uuid]
        if o["OrderStatus"] == "STARTED":
            o.update(OrderStatus="CANCELLING", StatusText="cancel requested")
        else:
            assert o["OrderStatus"] == "RELEASED", o
            o.update(OrderStatus="CANCELLED", StatusText="cancelled in SAP")
            self.notifications[o["NotificationUUID"]]["NotificationStatus"] = "OPEN"

    def posted(self, kind):
        """POST bodies of one kind, in the order they were sent."""
        return [b for p, b in self.calls if p.endswith(kind)]

    def open_notifications(self, tag):
        return [n for n in self.notifications.values() if n["UnitTag"] == tag and n["NotificationStatus"] != "CLOSED"]


def answers(pm):
    out = []
    while not pm.acks.empty():
        out.append(pm.acks.get_nowait())
    return [(a[1]["key"], a[1]["gen"], a[2]) for a in out if a[0] == "fact"]


def notification(uuid, tag=7, at=100):
    return {"kind": "create", "key": uuid, "gen": 1,
            "body": {"NotificationUUID": uuid, "UnitTag": tag, "Material": "SupplyDepot", "Priority": "2",
                     "Health": 200, "HealthMax": 400, "ReportedAt": at, "StatusText": "damaged"}}


def cost(uuid, qty=13, order_uuid="o1"):
    return {"kind": "event", "key": uuid, "gen": 0,
            "body": {"EventUUID": uuid, "OrderUUID": order_uuid, "GameSeconds": 150, "MovementType": "261",
                     "Material": "MINERAL", "Quantity": qty, "MineralValue": qty, "GasValue": 0,
                     "EventSource": "LIVE", "UnitTag": 0}}


def repair(uuid, status, gen, text="", outcome="", scv=0):
    return {"kind": "repair", "key": uuid, "gen": gen,
            "body": {"OrderStatus": status, "WorkerTag": scv, "StartedAt": 110 if scv else 0, "AtSeconds": 200,
                     "StatusText": text, "NotificationOutcome": outcome}}


def health(uuid, gen, status="", text="damage got worse"):
    return {"kind": "notify", "key": uuid, "gen": gen,
            "body": {"NotificationStatus": status, "Priority": "1", "Health": 100, "HealthMax": 400,
                     "AtSeconds": 300, "StatusText": text}}


def outbox(faults=(), receipts=(7, 51)):
    sap = FakeSap(receipts)
    sap.faults = list(faults)
    return sap, PmOutbox(sap, DIV)


# --- outbox: acknowledged, ambiguous, rejected ----------------------------------------------------
sap, pm = outbox()
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "ack")] and pm.unacknowledged() == 0 and list(sap.notifications) == ["n1"]

sap, pm = outbox(["late"])              # SAP created it, the answer was lost
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "ack")] and len(sap.calls) == 1, "found by the identity read: no second POST"

sap, pm = outbox(["lost"])              # the request never arrived
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [] and pm.unacknowledged() == 1 and not sap.notifications
pm.pump(retry=False)
assert len(sap.calls) == 1, "sent again at the poll, not in between"
pm.pump(retry=True)
assert answers(pm) == [("n1", 1, "ack")] and sap.calls[0] == sap.calls[1], "the same UUID and the same body again"

sap, pm = outbox(["lost"])              # present with another payload: never overwritten, never sent again
sap.notifications["n1"] = {"NotificationUUID": "n1", "DivisionUUID": DIV, "UnitTag": 7, "Material": "SupplyDepot",
                           "ReportedAt": 55, "NotificationStatus": "OPEN"}
pm.inbox.put(notification("n1", at=100))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "conflict")] and len(pm.parked) == 1 and pm.unacknowledged() == 0
pm.pump(retry=True)
assert len(sap.calls) == 1

for fault, posts in (("late", 1), ("lost", 2)):
    sap, pm = outbox([fault])
    pm.inbox.put(cost("e1"))
    pm.pump(retry=False)
    pm.pump(retry=True)
    assert list(sap.events) == ["e1"] and len(sap.calls) == posts and pm.unacknowledged() == 0, (fault, sap.calls)
    assert all(b["EventUUID"] == "e1" for b in sap.posted("_Event")), "one EventUUID, no duplicate in the ledger"
sap, pm = outbox(["lost"])
sap.events["e1"] = {**cost("e1", qty=99)["body"], "DivisionUUID": DIV}
pm.inbox.put(cost("e1", qty=13))
pm.pump(retry=False)
assert len(pm.parked) == 1 and pm.parked[0][1] == "conflict", "another quantity under this EventUUID"
sap, pm = outbox()
sap.events["e1"] = {**cost("e1")["body"], "DivisionUUID": "another-division"}
pm.inbox.put(cost("e1"))
pm.pump(retry=False)
assert pm.parked[0][1] == "conflict", "the division belongs to the identity"

# a transport error is no rejection: HTTP 500 and 423 keep the fact, HTTP 400 parks it
sap, pm = outbox([500, 423, 423, 423, 423, 423, 423])
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [] and pm.unacknowledged() == 1 and not pm.parked, "HTTP 500: nobody knows"
pm.pump(retry=True)
assert len(sap.calls) == 1 + live_bot.LOCK_RETRIES + 1 and pm.unacknowledged() == 1, "HTTP 423 is retried, then waits"
pm.pump(retry=True)
assert answers(pm) == [("n1", 1, "ack")]
sap, pm = outbox([400])
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "rejected")] and len(pm.parked) == 1 and pm.unacknowledged() == 0
sap, pm = outbox([423, 423])
pm.inbox.put(cost("e1"))
pm.pump(retry=False)
assert list(sap.events) == ["e1"] and len(sap.calls) == 3, "the Game lock of a Fiori action passes"

# SAP away: the round ends at the first call without an answer
sap, pm = outbox()
sap.away = True
for uuid in ("e1", "e2", "e3"):
    pm.inbox.put(cost(uuid))
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert len(sap.calls) == 1 and pm.unacknowledged() == 4, "no queue of timeouts"
sap.away = False
pm.pump(retry=True)
assert list(sap.events) == ["e1", "e2", "e3"] and pm.unacknowledged() == 0, "in the order they were made"

# a dropped or late production receipt: the notification stays pending and visible, and is never given up
sap, pm = outbox(receipts=())
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
pm.pump(retry=True)
pm.pump(retry=True)
assert answers(pm) == [] and pm.unacknowledged() == 1 and not pm.parked and len(sap.calls) == 3
assert pm.shown == {"PM pending, sent again at each poll: Equipment 7 unknown"}, pm.shown
sap.receipts.add(7)
pm.pump(retry=True)
assert answers(pm) == [("n1", 1, "ack")] and pm.unacknowledged() == 0

# SAP holds another open notification of the equipment: adopted
sap, pm = outbox()
sap.notifications["old"] = {"NotificationUUID": "old", "DivisionUUID": DIV, "UnitTag": 7, "NotificationStatus": "OPEN"}
pm.inbox.put(notification("n1"))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "adopt")] and list(sap.notifications) == ["old"]

# status slots: the latest report only; a report waits for the create of its notification
sap, pm = outbox(["lost"])
sap.notifications["n1"] = {"NotificationUUID": "n1", "UnitTag": 7, "NotificationStatus": "IN_PROCESS"}
sap.orders["o1"] = {"OrderUUID": "o1", "NotificationUUID": "n1", "OrderStatus": "RELEASED", "WorkerTag": 0,
                    "StartedAt": 0, "ConfirmedAt": 0, "StatusText": ""}
pm.inbox.put(repair("o1", "STARTED", 1, "SCV on its way", scv=51))
pm.pump(retry=False)                    # lost
pm.inbox.put(cost("e1"))
pm.inbox.put(repair("o1", "CONFIRMED", 2, "repaired", scv=51))
pm.pump(retry=False)
assert [b["OrderStatus"] for b in sap.posted("reportRepair")] == ["STARTED", "CONFIRMED"], "the STARTED is never sent again"
assert list(sap.events) == ["e1"], "the cost of the segment waits for no status"
assert answers(pm) == [("e1", 0, "ack"), ("o1", 2, "ack")]
assert sap.orders["o1"]["OrderStatus"] == "CONFIRMED" and sap.orders["o1"]["WorkerTag"] == 51 \
    and sap.orders["o1"]["StartedAt"] == 110, "RELEASED to CONFIRMED stores the whole payload"

sap, pm = outbox(["lost"])
sap.notifications["n1"] = {"NotificationUUID": "n1", "UnitTag": 7, "NotificationStatus": "OPEN"}
pm.inbox.put(health("n1", 1, "CLOSED", "equipment destroyed"))
pm.pump(retry=False)                    # lost
pm.inbox.put(health("n1", 2))           # a health update made later
pm.pump(retry=True)
assert [b["NotificationStatus"] for b in sap.posted("reportNotification")] == ["CLOSED", "CLOSED"]
assert answers(pm) == [("n1", 2, "ack")], "the close stays and answers for the latest generation"
assert sap.notifications["n1"]["NotificationStatus"] == "CLOSED"

sap, pm = outbox(["lost"])
pm.inbox.put(notification("n1"))
pm.inbox.put(health("n1", 2))
pm.pump(retry=False)
assert len(sap.calls) == 1, "no report on a notification SAP does not hold yet"
pm.pump(retry=True)
assert [p.split("/")[-1].split(".")[-1] for p, _ in sap.calls] == ["_Notification", "_Notification", "reportNotification"]

# a refused report comes back with SAP's current row; a finished order reported again is a no-op, not an ack
sap, pm = outbox()
sap.notifications["n1"] = {"NotificationUUID": "n1", "UnitTag": 7, "NotificationStatus": "OPEN"}
sap.orders["o1"] = {"OrderUUID": "o1", "NotificationUUID": "n1", "OrderStatus": "CANCELLED", "WorkerTag": 0,
                    "StartedAt": 0, "ConfirmedAt": 0, "StatusText": "cancelled in SAP"}
pm.inbox.put(repair("o1", "STARTED", 1, "SCV on its way", scv=51))
pm.pump(retry=False)
fact, outcome, row = pm.acks.get_nowait()[1:]
assert outcome == "refused" and row["OrderStatus"] == "CANCELLED" and not pm.parked
pm.inbox.put(repair("o1", "CANCELLED", 2, "equipment destroyed", outcome="CLOSED"))
pm.pump(retry=False)
fact, outcome, row = pm.acks.get_nowait()[1:]
assert outcome == "noop" and row["StatusText"] == "cancelled in SAP", "HTTP 200 alone proves nothing"
assert sap.notifications["n1"]["NotificationStatus"] == "OPEN"
pm.inbox.put(repair("o9", "STARTED", 3, scv=51))
pm.pump(retry=False)
assert answers(pm) == [("o9", 3, "rejected")], "SAP holds no such order"

# a close SAP refuses is parked and counted; nothing takes it for closed
sap, pm = outbox()
sap.notifications["n1"] = {"NotificationUUID": "n1", "UnitTag": 7, "NotificationStatus": "IN_PROCESS"}
sap.orders["o1"] = {"OrderUUID": "o1", "NotificationUUID": "n1", "OrderStatus": "STARTED"}
pm.inbox.put(health("n1", 1, "CLOSED", "equipment destroyed"))
pm.pump(retry=False)
assert answers(pm) == [("n1", 1, "rejected")] and pm.parked[0][2] == "Repair in work: report the repair"
assert sap.notifications["n1"]["NotificationStatus"] == "IN_PROCESS" and pm.unacknowledged() == 0

# the poll follows the pages the service makes: a short page with a nextLink is not the end
class Pages:
    """A requests session whose service answers in pages of its own size, relative or absolute nextLink."""

    def __init__(self, rows, sizes, absolute=False):
        self.rows, self.sizes, self.absolute, self.urls = rows, list(sizes), absolute, []

    def get(self, url, params=None, timeout=None):
        self.urls.append(url)
        if "sap-client=" in url and not (params and "sap-client" in params and params["sap-client"] is None):
            # the session adds its sap-client to every request: twice is a URI syntax error (seen on A4H)
            return SimpleNamespace(status_code=400, text="URI syntax error", json=dict)
        skip = int(re.search(r"skiptoken=(\d+)", url).group(1)) if "skiptoken" in url else 0
        size = self.sizes.pop(0) if self.sizes else len(self.rows)
        data = {"value": self.rows[skip:skip + size]}
        if skip + size < len(self.rows):
            link = f"MaintOrder?sap-client=001&$filter=x&$skiptoken={skip + size}"       # as A4H writes it
            data["@odata.nextLink"] = ("https://sap/odata/" + link) if self.absolute else link
        return SimpleNamespace(status_code=200, json=lambda: data)


def paged(rows, sizes, absolute=False):
    real = Sap.__new__(Sap)             # the real get_all, without a logon
    real.base, real.s = "https://sap/odata/", Pages(rows, sizes, absolute)
    return real


orders = [{"OrderUUID": f"o{i:04d}", "OrderStatus": "RELEASED" if i % 2 else "CANCELLING"} for i in range(203)]
for sizes, absolute in (([100, 100], False), ([100, 3, 40], False), ([1], True), ([], False)):
    real = paged(orders, sizes, absolute)
    assert real.get_all("MaintOrder?$filter=x") == orders, (sizes, "a short page with a nextLink is followed")
    assert real.s.urls[0] == "https://sap/odata/MaintOrder?$filter=x" and \
        all(u.startswith("https://sap/odata/MaintOrder?") for u in real.s.urls), real.s.urls[:3]
assert len(paged(orders, [100, 3, 40]).get_all("x")) == 203 and paged([], []).get_all("x") == []
broken = paged(orders, [])
broken.s.get = lambda url, params=None, timeout=None: SimpleNamespace(status_code=500, text="down", json=dict)
try:
    broken.get_all("MaintOrder")
    raise AssertionError("an error page must not pass for the end of the list")
except SapError as e:
    assert e.status == 500
pm = PmOutbox(paged(orders, [100, 3, 40]), DIV)
pm.poll()
kind, rows = pm.acks.get_nowait()
assert kind == "poll" and rows == orders and DIV in pm.sap.s.urls[0] and "$top" not in pm.sap.s.urls[0]

# the proposed uuid of a notification is never used once SAP named another: its waiting close goes to that one
sap, pm = outbox()
sap.notifications["old"] = {"NotificationUUID": "old", "DivisionUUID": DIV, "UnitTag": 7, "NotificationStatus": "OPEN"}
pm.inbox.put(notification("n1"))
pm.inbox.put(health("n1", 2, "CLOSED", "equipment destroyed"))
pm.pump(retry=False)
assert [p for p, _ in sap.calls] == [f"Division({DIV})/_Notification", f"Notification(old)/{live_bot.ACTION}reportNotification"]
assert answers(pm) == [("n1", 1, "adopt"), ("old", 2, "ack")] and not pm.parked and pm.unacknowledged() == 0
assert sap.notifications["old"]["NotificationStatus"] == "CLOSED" and not pm.slots
pm.inbox.put(health("n1", 3, "CLOSED", "late"))     # decided by the game before it heard of the adoption
pm.pump(retry=False)
assert answers(pm) == [("old", 3, "ack")] and not pm.parked, "no report ever goes to the proposed uuid"


# --- the bot on the fake game and the fake SAP ------------------------------------------------------
def game(structures=(), workers=(), receipts=None, minerals=500, gas=100):
    """An Outpost without StarCraft II: the base and its minerals at 0, the depot at 100, SCV 51 nearest to it."""
    workers = list(workers) or [miner(51, 90), miner(52, 80), miner(53, 70)]
    sap = FakeSap(receipts if receipts is not None else [u.tag for u in [*structures, *workers]])
    bot = Outpost(sap, "test", 20)
    bot.division_uuid = DIV
    bot.sap_worker = SimpleNamespace(pm=PmOutbox(sap, DIV))
    bot.state = SimpleNamespace(game_loop=2240, common=SimpleNamespace(minerals=minerals, vespene=gas),
                                score=SimpleNamespace(collected_minerals=0, collected_vespene=0, spent_minerals=0,
                                                      spent_vespene=0, ))
    bot.opening = (minerals, gas)
    bot.structures, bot.workers = Units(structures), Units(workers)
    bot.townhalls, bot.mineral_field = Units([Unit(1, 0)]), Units([Unit(PATCH, 0)])
    bot.gas_buildings = Units()
    bot.unit_tags_received_action = set()
    bot.owned = {u.tag: (getattr(u, "matnr", "SCV"), "plant-1") for u in [*structures, *workers]}
    bot.logs = []
    bot.log = bot.logs.append
    return bot, sap


def depot(tag=7, health=200, position=100, matnr="SupplyDepot", **kw):
    return Unit(tag, position, health=health, matnr=matnr, **kw)


def tick(bot, loops=4, sap=True):
    """One observation: python-sc2 forgets the commanded tags, SAP answers, the PM pass runs."""
    bot.state.game_loop += loops
    bot.unit_tags_received_action = set()
    if sap:
        bot.sap_worker.pm.pump(retry=False)
    bot.pm_answers()
    bot.watch_repair()
    bot.check_damage()
    bot.start_repairs()


def poll(bot):
    bot.sap_worker.pm.poll()
    bot.sap_worker.pm.pump(retry=True)


def commanded(bot, unit):
    """What python-sc2 does with a command: the tag is taken for this frame."""
    bot.unit_tags_received_action.add(unit.tag)


def released(bot, sap, tag=7, uuid="o1"):
    """Damage seen, notification in SAP, the player's repair order polled."""
    tick(bot)
    tick(bot)
    n = sap.open_notifications(tag)[0]["NotificationUUID"]
    sap.create_order(n, uuid)
    poll(bot)
    bot.pm_answers()
    return n


def in_work(bot, sap, tag=7, uuid="o1"):
    """As released, and the repair started: the nearest SCV holds the repair order from the next observation on."""
    n = released(bot, sap, tag, uuid)
    tick(bot)
    scv = bot.workers.find_by_tag(bot.segment["scv"])
    assert scv.commands == [("repair", tag)], scv.commands
    scv.orders = [order(REPAIR, tag)]
    tick(bot)
    return n, scv


def charge(bot, minerals, gas=0):
    bot.state.common.minerals -= minerals
    bot.state.common.vespene -= gas


# damage check and deduplication
site = depot(8, health=50, is_ready=False)
bot, sap = game([depot(), depot(9, health=400), site])
tick(bot)
tick(bot)
assert [n["UnitTag"] for n in sap.notifications.values()] == [7], "the damaged one; not the intact one, not the site"
n = list(sap.notifications.values())[0]
assert n["Material"] == "SupplyDepot" and n["Priority"] == "2" and n["Health"] == 200 and n["HealthMax"] == 400 \
    and n["PlantUUID"] == "plant-1" and n["ReportedAt"] == 100, n
assert len(sap.posted("_Notification")) == 1, "once"
bot.structures[0].health = 190
tick(bot)
assert not sap.posted("reportNotification"), "same priority: no update"
bot.structures[0].health = 120.6
tick(bot)
tick(bot)
assert [(b["Priority"], b["Health"]) for b in sap.posted("reportNotification")] == [("1", 120)], "one update when it got worse"
bot.structures[0].health = 300
tick(bot)
tick(bot)
assert len(sap.posted("reportNotification")) == 1 and len(sap.notifications) == 1

# SAP away: `notified` follows the game, and nothing is posted twice when SAP is back
bot, sap = game([depot()])
sap.away = True
for _ in range(5):
    tick(bot)
assert len(bot.notified) == 1 and bot.sap_worker.pm.unacknowledged() == 1
sap.away = False
poll(bot)
tick(bot)
assert len(sap.notifications) == 1 and bot.sap_worker.pm.unacknowledged() == 0 and not bot.pm_gen

# --- SCV reservation: every selector honours it, and the command of this frame -------------------
bot, sap = game([depot()])
n = released(bot, sap)
tick(bot)
near, second, third = bot.workers
assert near.commands == [("repair", 7)] and bot.reserved == {51: "o1"} and bot.segment["scv"] == 51, "the nearest free SCV"
assert near.is_gathering and not holds_repair(near, 7), "on its way, it still looks like a miner"
assert bot.select_build_worker(95) is second, "reserved: not the nearest"
bot.unit_tags_received_action = {51}
assert bot.select_build_worker(95) is second, "reserved and commanded in this frame"
bot.unit_tags_received_action = {52}
assert bot.select_build_worker(95) is third, "commanded in this frame: python-sc2's own guard never excludes it"
bot.unit_tags_received_action = {52, 53}
assert bot.select_build_worker(95) is None and bot.select_build_worker(95, force=True) is None, "nobody is free"
bot.unit_tags_received_action = set()
builder = miner(54, 96)
builder.orders = [order(AbilityId.TERRANBUILD_SUPPLYDEPOT)]
bot.workers.append(builder)
assert bot.select_build_worker(95) is second, "an SCV that builds is not taken, as in python-sc2"
near.orders = []                        # the repair is over, the segment not yet settled
bot.workers[1].orders, bot.workers[2].orders = [], []
bot.unit_tags_received_action = {53}
assert bot.return_idle_workers() == 1 and second.commands == [("gather", PATCH)] and not third.commands \
    and near.commands == [("repair", 7)], "idle, but reserved or commanded in this frame"
bot.unit_tags_received_action = set()
near.orders, second.orders, third.orders = [order(GATHER, PATCH)], [order(GATHER, PATCH)], [order(GATHER, PATCH)]
refinery = Unit(70, 5, assigned_harvesters=0, ideal_harvesters=2)
bot.gas_buildings = Units([refinery])
bot.townhalls = Units([Unit(1, 0)])
bot.unit_tags_received_action = {52}
second.commands.clear()
assert bot.staff_refineries() == 1 and third.commands == [("gather", 70)] and not second.commands \
    and near.commands == [("repair", 7)], "gas staffing takes neither"
refinery.assigned_harvesters, refinery.ideal_harvesters = 3, 2
near.orders = [order(GATHER, 70)]       # contrived: the reserved SCV's order still points at the refinery
second.orders = [order(GATHER, 70)]
bot.unit_tags_received_action = set()
assert bot.trim_refineries() == 1 and second.commands == [("gather", PATCH)] and near.commands == [("repair", 7)], \
    "the surplus SCV is never the reserved one"
assert free_workers(bot.workers, bot.reserved, {52}) == [third, builder]

# the repair choice: a free miner of ours, empty-handed, the nearest
loaded, stranger, gas_scv, walker = miner(51, 99), miner(52, 98), miner(53, 97), Unit(54, 96)
loaded.is_carrying_resource = True
gas_scv.orders = [order(GATHER, 70)]
busy, far, nearer = miner(55, 95), miner(56, 10), miner(57, 60)
bot, sap = game([depot()], [loaded, stranger, gas_scv, walker, busy, far, nearer])
del bot.owned[52]                       # its receipt is not in the ledger: SAP would not know the SCV
released(bot, sap)
bot.state.game_loop += 4
bot.unit_tags_received_action = {55}
bot.pm_answers()
bot.start_repairs()
assert nearer.commands == [("repair", 7)] and not any(u.commands for u in (loaded, stranger, gas_scv, walker, busy, far))

# --- eligibility, in the spec's order ---------------------------------------------------------------
def waits(bot, sap, uuid="o1"):
    tick(bot)
    tick(bot)
    return sap.orders[uuid]["OrderStatus"], sap.orders[uuid]["StatusText"]


bot, sap = game([depot(is_flying=True)])
released(bot, sap)
assert waits(bot, sap) == ("RELEASED", "equipment is flying") and not bot.reserved
for _ in range(3):
    poll(bot)
    tick(bot)
assert len(sap.posted("reportRepair")) == 1, "the reason goes to SAP when it changes"
bot.structures[0].is_flying = False
poll(bot)
assert waits(bot, sap) == ("STARTED", "SCV on its way") and sap.orders["o1"]["WorkerTag"] == 51 \
    and sap.orders["o1"]["StartedAt"] == bot.segment["started"]

bot, sap = game([depot()], minerals=0)
released(bot, sap)
assert waits(bot, sap) == ("RELEASED", "cannot afford repair"), "the first unit is charged with the first HP"
bot, sap = game([depot(matnr="Factory")], gas=0)
released(bot, sap)
assert waits(bot, sap) == ("RELEASED", "cannot afford repair"), "a Factory costs gas"
bot, sap = game([depot()], gas=0)
released(bot, sap)
assert waits(bot, sap)[0] == "STARTED", "a Supply Depot costs none"

carrier = miner(51, 10)
carrier.is_carrying_resource = True
bot, sap = game([depot()], [carrier])
released(bot, sap)
assert waits(bot, sap) == ("RELEASED", "no free SCV")

bot, sap = game([depot(), depot(8, health=100, matnr="Barracks")])
tick(bot)
tick(bot)
for n in list(sap.notifications.values()):
    sap.create_order(n["NotificationUUID"], "o-" + n["Material"])
poll(bot)
tick(bot)
tick(bot)
assert bot.segment["material"] == "Barracks", "priority 1 before priority 2"
assert (sap.orders["o-Barracks"]["OrderStatus"], sap.orders["o-SupplyDepot"]["StatusText"]) == \
    ("STARTED", "waiting for the repair of Barracks")
assert len(bot.reserved) == 1, "one repair in work, one SCV"

bot, sap = game([depot()])
released(bot, sap)
bot.structures[0].health = 400
assert waits(bot, sap) == ("CONFIRMED", "no damage left") and not bot.reserved and not sap.events
assert not sap.open_notifications(7) and not bot.notified and not bot.closing, "closed with the order, confirmed by SAP"

bot, sap = game([depot()])
released(bot, sap)
hidden, bot.structures = bot.structures, Units()
tick(bot)
tick(bot)
assert sap.orders["o1"]["OrderStatus"] == "RELEASED" and not sap.posted("reportRepair"), \
    "missing from an observation without a death event: no decision"
bot.structures = hidden

# destroyed while its order waits, and with no order at all
bot, sap = game([depot()])
released(bot, sap)
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "equipment destroyed")
assert not sap.open_notifications(7) and not bot.closing
# ... and before the bot has seen the order the player created a moment ago: it ends with its notification
bot, sap = game([depot()])
tick(bot)
tick(bot)
sap.create_order(sap.open_notifications(7)[0]["NotificationUUID"], "o1")
bot.sap_worker.pm.poll()                # the poll is on its way to the game
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "equipment destroyed")
assert not sap.open_notifications(7) and not bot.closing and not bot.pm_gen and not bot.reserved
bot, sap = game([depot()])
tick(bot)
tick(bot)
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
closed = list(sap.notifications.values())[0]
assert (closed["NotificationStatus"], closed["StatusText"], closed["Health"]) == ("CLOSED", "equipment destroyed", 0)
bot.equipment_destroyed(51)             # an SCV is no equipment
assert len(sap.posted("reportNotification")) == 1

# --- the watch: a segment ends with the repair order, and costs the change of R ----------------------
bot, sap = game([depot()])
released(bot, sap)
tick(bot)
scv, target = bot.workers[0], bot.structures[0]
tick(bot, loops=REPAIR_GRACE_LOOPS - 4)
assert bot.segment and bot.reserved, "the order of a command shows in the next observation"
scv.orders = [order(REPAIR, 7)]
tick(bot)
assert sap.orders["o1"]["StatusText"] == "SCV on its way"
target.health = 230
charge(bot, 2)
tick(bot)
tick(bot)
assert sap.orders["o1"]["StatusText"] == "repairing"
bot.state.common.minerals -= 100        # a Supply Depot is ordered meanwhile: bank and score move together
bot.state.score.spent_minerals += 100
bot.state.common.minerals += 35         # and the miners deliver
bot.state.score.collected_minerals += 35
target.health = 400
charge(bot, 11)
tick(bot)
assert bot.segment and bot.reserved == {51: "o1"} and sap.orders["o1"]["OrderStatus"] == "STARTED", \
    "full health with the repair order still held is no end"
target.health = 396                     # hit again; the same order repairs on
charge(bot, 1)
tick(bot)
target.health = 400
scv.orders = []
tick(bot)
tick(bot)
assert bot.segment is None and not bot.reserved
assert [(e["Material"], e["Quantity"], e["MineralValue"], e["GasValue"], e["OrderUUID"], e["MovementType"])
        for e in sap.events.values()] == [("MINERAL", 14, 14, 0, "o1", "261")], "the exact cost, the late charge included"
assert all(e["PlantUUID"] is None and e["EventSource"] == "LIVE" for e in sap.events.values())
o = sap.orders["o1"]
assert (o["OrderStatus"], o["StatusText"], o["WorkerTag"]) == ("CONFIRMED", "repaired", 51) and o["ConfirmedAt"] >= o["StartedAt"]
assert not sap.open_notifications(7) and bot.repair_posted == [14, 0] and bot.spent == [0, 0]
assert bot.sap_worker.pm.unacknowledged() == 0 and not bot.pm_gen and not bot.closing
for _ in range(3):
    poll(bot)
    tick(bot)
assert scv.commands == [("repair", 7)] and len(sap.events) == 1, "booked once, repaired once"

# gas: a Factory costs both
bot, sap = game([depot(matnr="Factory", health=625, health_max=1250)])
n, scv = in_work(bot, sap)
charge(bot, 19, 13)
bot.structures[0].health = 1250
scv.orders = []
tick(bot)
tick(bot)
assert sorted((e["Material"], e["Quantity"], e["MineralValue"], e["GasValue"]) for e in sap.events.values()) == \
    [("MINERAL", 19, 19, 0), ("VESPENE", 13, 0, 13)] and bot.repair_posted == [19, 13]

# the bank runs dry: the game drops the order; a new command once SAP shows RELEASED and the bank has filled
bot, sap = game([depot()], minerals=5)
n, scv = in_work(bot, sap)
bot.structures[0].health = 280
charge(bot, 5)
tick(bot)
scv.orders = []
tick(bot)
tick(bot)
o = sap.orders["o1"]
assert (o["OrderStatus"], o["StatusText"], o["WorkerTag"]) == ("RELEASED", "interrupted: bank empty", 51)
assert [e["Quantity"] for e in sap.events.values()] == [5] and not bot.reserved
assert sap.open_notifications(7)[0]["NotificationUUID"] == n and len(sap.notifications) == 1, "still the one notification"
scv.orders = [order(GATHER, PATCH)]     # the idle check sent it back to mining
bot.state.common.minerals = 40
bot.state.score.collected_minerals += 40
tick(bot)
assert len(scv.commands) == 1, "not before a poll shows the order RELEASED again"
bot.state.common.minerals = 0
bot.state.score.spent_minerals += 40
poll(bot)
assert waits(bot, sap) == ("RELEASED", "cannot afford repair")
bot.state.common.minerals = 40
bot.state.score.collected_minerals += 40
assert waits(bot, sap) == ("STARTED", "SCV on its way") and len(scv.commands) == 2
scv.orders = [order(REPAIR, 7)]
tick(bot)
bot.structures[0].health = 400
charge(bot, 8)
scv.orders = []
tick(bot)
tick(bot)
assert [e["Quantity"] for e in sap.events.values()] == [5, 8] and sap.orders["o1"]["OrderStatus"] == "CONFIRMED", \
    "two segments, two bookings"

# the SCV dies
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
bot.structures[0].health = 230
charge(bot, 2)
tick(bot)
bot.workers.remove(scv)
bot.owned.pop(51)
bot.equipment_destroyed(51)
tick(bot)
tick(bot)
o = sap.orders["o1"]
assert (o["OrderStatus"], o["StatusText"]) == ("RELEASED", "interrupted: SCV lost") and not bot.reserved
assert [e["Quantity"] for e in sap.events.values()] == [2]
poll(bot)
assert waits(bot, sap) == ("STARTED", "SCV on its way") and sap.orders["o1"]["WorkerTag"] == 52, "the next free SCV"

# somebody else stops the SCV
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
bot.structures[0].health = 230
charge(bot, 2)
tick(bot)
scv.orders = [order(GATHER, PATCH)]
tick(bot)
tick(bot)
assert sap.orders["o1"]["StatusText"] == "interrupted: SCV stopped"

# out of reach: the game drops the order without a single HP; the retry waits 30 s
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
scv.orders = []
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("RELEASED", "cannot reach equipment")
assert not sap.events and not bot.reserved, "nothing spent, nothing booked"
scv.orders = [order(GATHER, PATCH)]
poll(bot)
tick(bot)
assert len(scv.commands) == 1, "not at once"
tick(bot, loops=REPAIR_STALL_LOOPS)
assert scv.commands == [("repair", 7), ("repair", 7)]

# no progress 30 s after the command while the order is held: back to mining, reserved until the order is gone
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
tick(bot, loops=REPAIR_STALL_LOOPS)
assert scv.commands == [("repair", 7), ("gather", PATCH)] and bot.reserved == {51: "o1"}
commanded(bot, scv)
assert bot.select_build_worker(11) is not scv
tick(bot)
assert len(scv.commands) == 2, "stopped once"
scv.orders = [order(GATHER, PATCH)]
tick(bot)
tick(bot)
assert sap.orders["o1"]["StatusText"] == "cannot reach equipment" and not bot.reserved and not sap.events

# the repair command is lost (never shows): the grace ends the segment
bot, sap = game([depot()])
released(bot, sap)
tick(bot)
tick(bot, loops=REPAIR_GRACE_LOOPS + 1)
tick(bot)
assert not bot.reserved and sap.orders["o1"]["OrderStatus"] == "RELEASED"

# --- cancel in SAP while the repair runs -----------------------------------------------------------
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
bot.structures[0].health = 260
charge(bot, 4)
tick(bot)
sap.cancel_order("o1")
poll(bot)
tick(bot)
assert scv.commands == [("repair", 7), ("gather", PATCH)]
assert bot.reserved == {51: "o1"} and not sap.events, "reserved until settled: the repair order is still held"
charge(bot, 1)                          # one more charge arrives before the command takes effect
poll(bot)                               # and SAP still shows CANCELLING
tick(bot)
assert len(scv.commands) == 2 and sap.orders["o1"]["OrderStatus"] == "CANCELLING"
scv.orders = [order(GATHER, PATCH)]
tick(bot)
tick(bot)
o = sap.orders["o1"]
assert (o["OrderStatus"], o["StatusText"]) == ("CANCELLED", "cancelled in game") and not bot.reserved
assert [e["Quantity"] for e in sap.events.values()] == [5], "the actual change, booked once"
assert sap.open_notifications(7)[0]["NotificationStatus"] == "OPEN" and 7 in bot.notified and not bot.closing
poll(bot)
tick(bot)
assert len(sap.notifications) == 1 and len(sap.posted("reportRepair")) == 3, "no second notification, no second answer"
sap.create_order(n, "o2")               # the player orders the repair again
poll(bot)
assert waits(bot, sap, "o2") == ("STARTED", "SCV on its way")

# cancelled at full health: the notification closes
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 13)
bot.structures[0].health = 400
sap.cancel_order("o1")
poll(bot)
tick(bot)
scv.orders = [order(GATHER, PATCH)]
tick(bot)
tick(bot)
assert sap.orders["o1"]["OrderStatus"] == "CANCELLED" and not sap.open_notifications(7)

# --- the cancel ordering table ----------------------------------------------------------------------
# STARTED against CANCELLED: cancelled in SAP while the SCV was being sent
bot, sap = game([depot()])
released(bot, sap)
sap.cancel_order("o1")                  # after the poll
tick(bot)
scv = bot.workers[0]
assert scv.commands == [("repair", 7)], "the poll could not prevent it"
scv.orders = [order(REPAIR, 7)]
charge(bot, 1)
tick(bot)                               # the refusal arrives: Order already CANCELLED
assert scv.commands == [("repair", 7), ("gather", PATCH)] and bot.reserved == {51: "o1"}
assert bot.repairs["o1"]["state"] == "ended"
charge(bot, 1)
tick(bot)
scv.orders = [order(GATHER, PATCH)]
tick(bot)
tick(bot)
assert not bot.reserved and [e["Quantity"] for e in sap.events.values()] == [2], "what was spent is still posted"
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "cancelled in SAP")
assert [b["OrderStatus"] for b in sap.posted("reportRepair")] == ["STARTED"], "no report on an order SAP has ended"
assert 7 in bot.notified and sap.open_notifications(7)[0]["NotificationStatus"] == "OPEN"
for _ in range(3):
    poll(bot)
    tick(bot)
assert len(scv.commands) == 2 and len(sap.notifications) == 1

# RELEASED after an interruption against CANCELLING: answered as a cancel, never back to RELEASED
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 3)
bot.structures[0].health = 250
sap.cancel_order("o1")                  # not polled yet
scv.orders = [order(GATHER, PATCH)]     # and the SCV was stopped by somebody
tick(bot)
tick(bot)
tick(bot)
assert [(b["OrderStatus"], b["StatusText"]) for b in sap.posted("reportRepair")][-2:] == \
    [("RELEASED", "interrupted: SCV stopped"), ("CANCELLED", "cancelled in game")]
assert sap.orders["o1"]["OrderStatus"] == "CANCELLED" and [e["Quantity"] for e in sap.events.values()] == [3]
assert len(scv.commands) == 1 and sap.open_notifications(7)[0]["NotificationStatus"] == "OPEN"

# CONFIRMED against CANCELLING: the repair was done, CONFIRMED wins
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 13)
bot.structures[0].health = 400
scv.orders = []
sap.away = True
tick(bot)                               # decided: CONFIRMED, not delivered yet
sap.away = False
sap.cancel_order("o1")
poll(bot)                               # CANCELLING reaches the game after the decision
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CONFIRMED", "repaired")
assert not sap.open_notifications(7) and [b["OrderStatus"] for b in sap.posted("reportRepair")][-1] == "CONFIRMED"
assert len(scv.commands) == 1 and [e["Quantity"] for e in sap.events.values()] == [13]
# ... and when the cancel request is seen in the observation in which the repair has ended by itself
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 13)
bot.structures[0].health = 400
scv.orders = []
sap.cancel_order("o1")
poll(bot)
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CONFIRMED", "cannot cancel: already repaired")
assert not sap.open_notifications(7) and len(scv.commands) == 1

# CANCELLED `equipment destroyed` against CANCELLING: CANCELLED wins
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 4)
sap.cancel_order("o1")
poll(bot)
tick(bot)                               # cancel requested: SCV sent back, segment open
bot.structures.remove(bot.structures[0])
bot.owned.pop(7)
bot.equipment_destroyed(7)
scv.orders = []
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "equipment destroyed")
assert not sap.open_notifications(7) and [e["Quantity"] for e in sap.events.values()] == [4] and not bot.reserved

# destroyed while in work
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 4)
bot.structures.remove(bot.structures[0])
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
assert bot.reserved, "the order is gone one observation later"
scv.orders = []
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "equipment destroyed")
assert sap.notifications[n]["NotificationStatus"] == "CLOSED" and [e["Quantity"] for e in sap.events.values()] == [4]

# --- cancelled in SAP, then the equipment is destroyed ----------------------------------------------
# the poll came first: the order is gone here, the OPEN notification is closed by itself
bot, sap = game([depot()])
n = released(bot, sap)
sap.cancel_order("o1")
poll(bot)
tick(bot)
assert bot.repairs["o1"]["state"] == "waiting" and not bot.repairs["o1"]["released"], "missing from a poll: parked"
assert not bot.reserved and 7 in bot.notified and not sap.posted("reportRepair")
bot.owned.pop(7)
bot.equipment_destroyed(7)
for _ in range(3):
    tick(bot)
assert (sap.notifications[n]["NotificationStatus"], sap.notifications[n]["StatusText"]) == ("CLOSED", "equipment destroyed")
assert sap.orders["o1"]["StatusText"] == "cancelled in SAP" and bot.repairs["o1"]["state"] == "ended"
assert not bot.closing and not bot.pm_gen and not bot.sap_worker.pm.parked
# the death came first: CANCELLED / CLOSED is a no-op in SAP (HTTP 200), so the notification is closed after it
bot, sap = game([depot()])
n = released(bot, sap)
sap.cancel_order("o1")
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
assert sap.orders["o1"]["StatusText"] == "cancelled in SAP" and sap.notifications[n]["NotificationStatus"] == "OPEN"
assert 7 in bot.closing, "not confirmed: the returned row is not what was reported"
tick(bot)
tick(bot)
assert (sap.notifications[n]["NotificationStatus"], sap.notifications[n]["StatusText"]) == ("CLOSED", "equipment destroyed")
assert not bot.closing and not bot.pm_gen
# ... and with a newer order of the player on it: destroyed is destroyed, it ends with its notification
bot, sap = game([depot()])
n = released(bot, sap)
sap.cancel_order("o1")
sap.create_order(n, "o2")
bot.owned.pop(7)
bot.equipment_destroyed(7)
for _ in range(3):
    tick(bot)
assert sap.orders["o2"]["OrderStatus"] == "CANCELLED" and sap.notifications[n]["NotificationStatus"] == "CLOSED"
# not destroyed: a refused final report never closes a notification that a newer repair works on
bot, sap = game([depot()])
n = released(bot, sap)
sap.cancel_order("o1")                  # cancelled in SAP,
bot.structures[0].health = 400          # and the bot finds no damage left on its stale order
tick(bot)
bot.structures[0].health = 300          # damaged again before SAP's refusal arrives
tick(bot)
tick(bot)
assert sap.notifications[n]["NotificationStatus"] == "OPEN" and bot.notified[7]["uuid"] == n and not bot.closing
assert not sap.posted("reportNotification") and len(sap.notifications) == 1

# --- an order missing from a poll is not executed, and not ended: rows can move between two pages -------
bot, sap = game([depot()])              # the Architect's reproduction
released(bot, sap)
row = dict(sap.orders["o1"])
bot.take_repairs([])
bot.start_repairs()
assert bot.repairs["o1"]["state"] == "waiting" and not bot.reserved, "not executable until a poll shows it again"
bot.take_repairs([row])
bot.start_repairs()
scv = bot.workers[0]
assert bot.repairs["o1"]["state"] == "work" and scv.commands == [("repair", 7)]
for rows in ([], [row], [], [row]):     # in work: neither a missing row nor a lagging RELEASED starts it again
    bot.take_repairs(rows)
    tick(bot, sap=False)
assert scv.commands == [("repair", 7)] and len(bot.reserved) == 1
scv.orders = [order(REPAIR, 7)]
tick(bot)
charge(bot, 13)
bot.structures[0].health = 400
scv.orders = []
tick(bot)
tick(bot)
assert sap.orders["o1"]["OrderStatus"] == "CONFIRMED" and bot.repairs["o1"]["state"] == "ended"
for rows in ([], [row], [row]):         # ended by the bot's own final report: a stale RELEASED row revives nothing
    bot.take_repairs(rows)
    tick(bot)
assert bot.repairs["o1"]["state"] == "ended" and all(len(u.commands) <= 1 for u in bot.workers) and not bot.reserved
assert [e["Quantity"] for e in sap.events.values()] == [13]
bot, sap = game([depot()])              # ended by SAP's definitive answer: the same
released(bot, sap)
sap.cancel_order("o1")
tick(bot)
bot.workers[0].orders = [order(REPAIR, 7)]
tick(bot)                               # Order already CANCELLED
bot.workers[0].orders = [order(GATHER, PATCH)]
tick(bot)
assert bot.repairs["o1"]["state"] == "ended" and not bot.reserved
bot.take_repairs([dict(sap.orders["o1"], OrderStatus="RELEASED")])
for _ in range(3):
    tick(bot)
assert bot.repairs["o1"]["state"] == "ended" and len(bot.workers[0].commands) == 2 and not bot.reserved

# --- the damage is gone without a repair order: the notification is closed ------------------------------
bot, sap = game([depot()])              # the Architect's reproduction
tick(bot)
tick(bot)
bot.structures[0].health = 400
tick(bot)
tick(bot)
n = list(sap.notifications.values())[0]
assert (n["NotificationStatus"], n["StatusText"], n["Health"]) == ("CLOSED", "no damage found", 400)
assert not bot.notified and not bot.closing and not bot.pm_gen and len(sap.posted("reportNotification")) == 1
for _ in range(3):
    tick(bot)
assert len(sap.posted("reportNotification")) == 1 and len(sap.notifications) == 1, "closed once, nothing new"

# recovered, and damaged again while the close is not confirmed: one episode after the other, none lost
bot, sap = game([depot()])
tick(bot)
tick(bot)
first = sap.open_notifications(7)[0]["NotificationUUID"]
bot.structures[0].health = 400
sap.away = True
tick(bot)
assert 7 in bot.closing and 7 not in bot.notified
bot.structures[0].health = 250
for _ in range(3):
    tick(bot)
assert not bot.notified and len(sap.posted("_Notification")) == 1, "the new damage waits for the close"
sap.away = False
poll(bot)
tick(bot)
tick(bot)
assert sap.notifications[first]["NotificationStatus"] == "CLOSED"
new = sap.open_notifications(7)
assert len(new) == 1 and new[0]["NotificationUUID"] != first and new[0]["Health"] == 250 and len(sap.notifications) == 2
assert bot.notified[7]["uuid"] == new[0]["NotificationUUID"] and not bot.closing

# a repair in work is not touched by full health: its segment ends with the repair order
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 12)
bot.structures[0].health = 400
for _ in range(3):
    tick(bot)
assert bot.segment and bot.reserved == {51: "o1"} and scv.commands == [("repair", 7)] and 7 in bot.notified
assert not sap.posted("reportNotification") and sap.orders["o1"]["OrderStatus"] == "STARTED"
charge(bot, 1)
scv.orders = []
tick(bot)
tick(bot)
assert sap.orders["o1"]["OrderStatus"] == "CONFIRMED" and [e["Quantity"] for e in sap.events.values()] == [13]
assert not sap.posted("reportNotification") and sap.notifications[n]["StatusText"] == "repaired"

# an order the latest poll shows RELEASED ends as `no damage left`; one the bot has not seen ends with the close
bot, sap = game([depot()])
n = released(bot, sap)
bot.structures[0].health = 400
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CONFIRMED", "no damage left")
assert not sap.posted("reportNotification") and sap.notifications[n]["NotificationStatus"] == "CLOSED"
bot, sap = game([depot()])
tick(bot)
tick(bot)
n = sap.open_notifications(7)[0]["NotificationUUID"]
sap.create_order(n, "o1")               # released a moment ago, not polled yet
bot.structures[0].health = 400
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "no damage found")
assert sap.notifications[n]["NotificationStatus"] == "CLOSED" and not bot.closing
bot.take_repairs([dict(sap.orders["o1"], OrderStatus="RELEASED")])     # a poll made before the close, arriving late
for _ in range(3):
    tick(bot)
assert not any(u.commands for u in bot.workers) and len(sap.notifications) == 1
# the order's last report is not answered yet (SAP still holds STARTED): the close waits, nothing is parked
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 3)
bot.structures[0].health = 250
scv.orders = [order(GATHER, PATCH)]     # stopped by somebody
sap.away = True
tick(bot)
bot.structures[0].health = 400          # and the damage is gone
for _ in range(3):
    tick(bot)
assert 7 in bot.notified and not bot.closing and sap.orders["o1"]["OrderStatus"] == "STARTED"
sap.away = False
poll(bot)                               # made while SAP held STARTED; then the interruption arrives
tick(bot)
assert sap.orders["o1"]["StatusText"] == "interrupted: SCV stopped" and 7 in bot.closing, "answered: now the close goes"
tick(bot)
tick(bot)
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("CANCELLED", "no damage found")
assert sap.notifications[n]["NotificationStatus"] == "CLOSED" and not bot.sap_worker.pm.parked and not bot.closing
assert [e["Quantity"] for e in sap.events.values()] == [3] and bot.repairs["o1"]["state"] == "ended" and len(scv.commands) == 1

# --- new damage after a close waits for the close -------------------------------------------------
bot, sap = game([depot()])
n, scv = in_work(bot, sap)
charge(bot, 13)
bot.structures[0].health = 400
scv.orders = []
sap.away = True
tick(bot)
assert bot.repairs["o1"]["state"] == "ended" and 7 in bot.closing and 7 not in bot.notified
bot.structures[0].health = 350          # hit again before SAP confirmed the close
for _ in range(3):
    tick(bot)
assert not bot.notified and len(sap.posted("_Notification")) == 1, "no new notification before the close is confirmed"
sap.away = False
poll(bot)
tick(bot)
tick(bot)
assert sap.notifications[n]["NotificationStatus"] == "CLOSED" and sap.orders["o1"]["OrderStatus"] == "CONFIRMED"
new = sap.open_notifications(7)
assert len(new) == 1 and new[0]["NotificationUUID"] != n and len(sap.notifications) == 2, "a new one, a new UUID"
assert [e["Quantity"] for e in sap.events.values()] == [13] and len(scv.commands) == 1, "no second repair command"

# --- a STARTED that never arrives: polls keep showing RELEASED for the order in work ------------------
bot, sap = game([depot()])
released(bot, sap)
sap.away = True
tick(bot)
scv = bot.workers[0]
scv.orders = [order(REPAIR, 7)]
sap.away = False
sap.faults = ["lost"] * 3
for _ in range(3):
    bot.sap_worker.pm.poll()            # RELEASED in SAP; the report's retry is lost again
    bot.sap_worker.pm.pump(retry=True)
    tick(bot, sap=False)
assert sap.orders["o1"]["OrderStatus"] == "RELEASED" and scv.commands == [("repair", 7)] and len(bot.reserved) == 1, \
    "SAP's status alone starts nothing"
charge(bot, 13)
bot.structures[0].health = 400
scv.orders = []
tick(bot, sap=False)                    # the segment is settled: its 261 and CONFIRMED are decided
sap.faults = ["lost"]                   # the 261 is lost once, the report after it is not tried in that round
bot.sap_worker.pm.pump(retry=False)
assert not sap.events and sap.orders["o1"]["OrderStatus"] == "RELEASED" and bot.sap_worker.pm.unacknowledged() == 2
sap.faults = [None, "lost"]             # the 261 arrives, the final report is lost
poll(bot)
tick(bot, sap=False)
assert [e["Quantity"] for e in sap.events.values()] == [13] and sap.orders["o1"]["OrderStatus"] == "RELEASED", \
    "the cost does not wait for the status"
assert bot.repairs["o1"]["state"] == "ended" and 7 in bot.closing
for _ in range(2):                      # polls still show RELEASED: the ended order is not executed again
    bot.sap_worker.pm.poll()
    tick(bot, sap=False)
assert scv.commands == [("repair", 7)] and not bot.reserved
poll(bot)
tick(bot)
o = sap.orders["o1"]
assert (o["OrderStatus"], o["WorkerTag"], o["StartedAt"] > 0) == ("CONFIRMED", 51, True), "RELEASED to CONFIRMED, whole payload"
assert [b["OrderStatus"] for b in sap.posted("reportRepair")].count("CONFIRMED") == 2 and len(sap.events) == 1
assert not sap.open_notifications(7) and not bot.closing and bot.sap_worker.pm.unacknowledged() == 0

# --- answers are fenced by generation -------------------------------------------------------------
bot, sap = game([depot()])
bot.repairs["o1"] = {"row": {"OrderUUID": "o1", "UnitTag": 7, "Material": "SupplyDepot", "NotificationUUID": "n1"},
                     "state": "waiting", "reason": None, "released": True}
bot.report_repair("o1", "RELEASED", "no free SCV")
bot.report_repair("o1", "RELEASED", "cannot afford repair")
first, second = (bot.sap_worker.pm.inbox.get_nowait() for _ in range(2))
bot.pm_answer(first, "ack", {})
assert bot.pm_gen == {"o1": second["gen"]}, "an old answer never clears the latest pending state"
bot.pm_answer(first, "refused", {"OrderStatus": "CANCELLED"})
assert bot.repairs["o1"]["state"] == "waiting", "nor does an old refusal end anything"
bot.pm_answer(second, "ack", {})
assert not bot.pm_gen

bot.closing[7] = {"uuid": "n1", "key": "n1", "priority": "1", "health": 0, "max": 400, "text": "equipment destroyed"}
bot.report_notification(bot.closing[7], "CLOSED", "equipment destroyed")
bot.pm_answer(bot.sap_worker.pm.inbox.get_nowait(), "rejected", "Repair in work: report the repair")
assert 7 in bot.closing and not bot.pm_gen, "a close SAP rejected keeps the equipment blocked"

# an open notification SAP holds under another UUID is adopted, and closed under that UUID
bot, sap = game([depot()])
sap.notifications["old"] = {"NotificationUUID": "old", "DivisionUUID": DIV, "UnitTag": 7, "Material": "SupplyDepot",
                            "NotificationStatus": "OPEN", "Priority": "3", "ReportedAt": 1}
tick(bot)
tick(bot)
assert bot.notified[7]["uuid"] == "old" and list(sap.notifications) == ["old"] and not bot.pm_gen
bot.owned.pop(7)
bot.equipment_destroyed(7)
tick(bot)
assert sap.notifications["old"]["NotificationStatus"] == "CLOSED"
# the close was decided on the proposed uuid, before SAP named the other one
for recovered in (False, True):
    bot, sap = game([depot()])
    sap.notifications["old"] = {"NotificationUUID": "old", "DivisionUUID": DIV, "UnitTag": 7, "Material": "SupplyDepot",
                                "NotificationStatus": "OPEN", "Priority": "3", "ReportedAt": 1}
    tick(bot, sap=False)                # damage seen: the create is on its way
    proposed = bot.notified[7]["uuid"]
    if recovered:
        bot.structures[0].health = 400
        tick(bot, sap=False)
    else:
        bot.owned.pop(7)
        bot.equipment_destroyed(7)
    assert bot.closing[7]["key"] == proposed and list(bot.pm_gen) == [proposed]
    tick(bot)
    tick(bot)
    text = "no damage found" if recovered else "equipment destroyed"
    assert (sap.notifications["old"]["NotificationStatus"], sap.notifications["old"]["StatusText"]) == ("CLOSED", text)
    assert list(sap.notifications) == ["old"] and not any(proposed in p for p, _ in sap.calls), "nothing sent to the proposed uuid"
    assert not bot.closing and not bot.pm_gen and not bot.notified and not bot.sap_worker.pm.parked
    assert bot.sap_worker.pm.unacknowledged() == 0

# --- end of the game: the open segment is booked, the drain keeps trying ---------------------------
def ending(faults=(), away=False):
    bot, sap = game([depot()])
    n, scv = in_work(bot, sap)
    charge(bot, 6)
    bot.structures[0].health = 300
    tick(bot)
    outbox_so_far = bot.sap_worker.pm
    bot.sap_worker = SapWorker(sap, DIV, poll_seconds=0.05)
    bot.sap_worker.pm = outbox_so_far
    drain = bot.sap_worker.drain
    bot.sap_worker.drain = lambda: drain(1)      # the bot's 60 s, shortened
    bot.sap_worker.start()
    sap.faults, sap.away = list(faults), away
    charge(bot, 1)
    asyncio.run(bot.on_end(Result.Victory))
    return bot, sap


bot, sap = ending(faults=["lost", "lost"])
assert not bot.sap_worker.is_alive() and bot.sap_worker.pm.unacknowledged() == 0
repairs = [e for e in sap.events.values() if e.get("OrderUUID") == "o1"]
assert [e["Quantity"] for e in repairs] == [7] and bot.repair_posted == [7, 0], "up to the last observation, once"
assert (sap.orders["o1"]["OrderStatus"], sap.orders["o1"]["StatusText"]) == ("RELEASED", "interrupted: game over")
assert not bot.reserved and measure(bot.opening, bot.state.common, bot.state.score) == (7, 0), "posted = measured"
bot, sap = ending(away=True)
assert bot.sap_worker.pm.unacknowledged() == 2, "printed as PM unacknowledged: the 261 and the report"
bot.sap_worker.stopping.set()

print("ok: PM helpers, outbox (identity read, retry, conflict, rejection, pending receipt, adopt and rebind, slots, "
      "nextLink pages), damage check, recovered health, reservation in every selector, eligibility, watch and exact "
      "cost, cancel ordering, cancelled in SAP then destroyed, missing from a poll, new damage after a close, "
      "lost STARTED, generation fence, end of game")
