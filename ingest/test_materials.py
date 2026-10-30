from parse_replay import load_materials
from sc2.ids.unit_typeid import UnitTypeId
from sc2.ids.upgrade_id import UpgradeId

m = load_materials()
protoss = {k: r for k, r in m.items() if r["bukrs"] == "3000"}
blocked = {k for k, r in protoss.items() if r["order_blocked"] == "X"}
assert blocked == {"Archon", "WarpGate", "WarpGateResearch", "Carrier"}, blocked
assert not any(r["order_blocked"] for r in m.values() if r["bukrs"] == "1000")
for k, r in protoss.items():
    for dep in (r["produced_by"], r["prerequisite"]):
        assert dep == "" or (dep in protoss and dep not in blocked), (k, dep)
    if k not in blocked:
        assert k.upper() in UnitTypeId.__members__ or k.upper() in UpgradeId.__members__, k
        if r["category"] != "UPGRADE":
            assert r["produced_by"], k                    # Nexus included: an expansion needs a Probe (P1-07)
assert protoss["Nexus"]["produced_by"] == "Probe"
assert protoss["Zealot"]["produced_by"] == "Gateway"
assert protoss["Stalker"]["prerequisite"] == "CyberneticsCore"
print("materials ok")
