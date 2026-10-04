"""Runnable check for parse_replay on the bundled sample. Run: .venv/bin/python ingest/test_parse.py"""
from pathlib import Path
from parse_replay import parse, stock, SIGN
assert SIGN.get("262") == 1, "a 262 returns what the 261 consumed"

HERE = Path(__file__).parent
if not (HERE / "sample.SC2Replay").exists():
    print("skipped: no ingest/sample.SC2Replay (not in the public repo)")
    raise SystemExit(0)
payload = parse(HERE / "sample.SC2Replay")

assert len(payload["ReplayHash"]) == 40
assert payload["DurationSeconds"] == 79, payload["DurationSeconds"]
divs = payload["_Division"]
assert len(divs) == 2
assert {d["CompanyCode"] for d in divs} == {"1000"}, "sample is a Terran mirror"
assert payload["WinnerDivisionUUID"] in {d["DivisionUUID"] for d in divs}
assert "GameUUID" not in divs[0], "parent keys are filled by RAP, never sent"

# In the sample, P1 (Kamil) built nothing and left at 79 s; P2 (AI) trained SCVs and a depot.
for d in divs:
    assert len(d["_Plant"]) >= 1, "each division starts with a town hall"
    assert "DivisionUUID" not in d["_Plant"][0]
    orders = {o["OrderUUID"] for o in d["_ProdOrder"]}
    types = {e["MovementType"] for e in d["_Event"]}
    assert {"561", "501"} <= types, types
    tag_of_101 = {e["OrderUUID"]: e["UnitTag"] for e in d["_Event"] if e["MovementType"] == "101"}
    for e in d["_Event"]:
        assert e["MovementType"] in SIGN
        if e["MovementType"] in ("101", "261"):
            assert e["OrderUUID"] in orders, e
        if e["MovementType"] == "261":
            assert e["UnitTag"] == tag_of_101[e["OrderUUID"]], e
        assert e["MineralValue"] >= 0 and e["GasValue"] >= 0
    for o in d["_ProdOrder"]:
        assert o["OrderStatus"] == "CONFIRMED"
        assert 0 <= o["ReleasedAt"] <= o["ConfirmedAt"]

all_orders = [o for d in divs for o in d["_ProdOrder"]]
assert any(o["Material"] == "SCV" for o in all_orders), "P2 trains SCVs"
assert any(o["Material"] == "SupplyDepot" for o in all_orders), "P2 builds a depot (init + done events)"
all_types = {e["MovementType"] for d in divs for e in d["_Event"]}
assert {"261", "101"} <= all_types, all_types

balances = stock(payload)
for (div, plant, matnr), qty in balances.items():
    if matnr in ("MINERAL", "VESPENE"):
        assert not plant, ("raw material balance must be division-level", matnr, plant, qty)
    else:
        assert qty >= 0, (matnr, qty)

from parse_replay import load_materials
mats = load_materials()
assert all(isinstance(m["supply_provided"], int) for m in mats.values())
# this SC2 client's game data (spike 2026-09-28): a town hall gives 13, a Hatchery 4; morphs add nothing
assert {k: m["supply_provided"] for k, m in mats.items() if m["supply_provided"]} == {
    "SupplyDepot": 8, "CommandCenter": 13, "Pylon": 8, "Nexus": 13, "Overlord": 8, "Hatchery": 4}, "providers"

print("ok:", len(divs), "divisions,", sum(len(d["_Event"]) for d in divs), "events,",
      sum(len(d["_ProdOrder"]) for d in divs), "orders,", len(balances), "stock rows")
