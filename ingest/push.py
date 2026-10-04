#!/usr/bin/env python3
"""Post parser output into ZSD_SCE over OData V4; also imported by live_bot.py.

  push.py --seed                  companies + materials.csv (resumable: adds missing rows, updates the tech tree and costs of existing ones)
  push.py payload.json [--verify] one deep create on Game; --verify compares StockBalance
  push.py --delete <GameUUID>     DELETE Game(<uuid>); RAP cascades to its divisions/plants/orders/events

Flags may appear in any order; the first non-flag argument is the payload path.
"""
import sys
import uuid
from pathlib import Path

from urllib.parse import urljoin

import requests

from parse_replay import load_materials, stock

HERE = Path(__file__).parent
SERVICE = "/sap/opu/odata4/sap/zsb_sce_o4/srvd/sap/zsd_sce/0001/"
ZERO_GUID = "00000000-0000-0000-0000-000000000000"
TIMEOUT = 60


class SapError(RuntimeError):
    """OData call answered with HTTP >= 400; .status holds the code."""
    def __init__(self, method, path, r):
        super().__init__(f"{method} {path} -> HTTP {r.status_code}\n{r.text[:800]}")
        self.status = r.status_code

COMPANIES = [("1000", "Terran Dominion", "Terran"),
             ("2000", "Zerg Swarm", "Zerg"),
             ("3000", "Protoss Protectorate", "Protoss")]


def env(path=HERE.parent / ".env"):
    if not path.exists():
        sys.exit(f"no .env in {path} — copy .env.example and fill it in")
    cfg = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if value[:1] in ("'", '"') and value.endswith(value[0]):
            value = value[1:-1]                    # quoted: keep # inside
        else:
            value = value.split("#", 1)[0].strip()
        cfg[key.strip()] = value
    return cfg


class Sap:
    def __init__(self):
        cfg = env()
        self.base = cfg["SAP_URL"].rstrip("/") + SERVICE
        self.s = requests.Session()
        self.s.auth = (cfg["SAP_USER"], cfg["SAP_PASSWORD"])
        self.s.params = {"sap-client": cfg.get("SAP_CLIENT", "001")}
        r = self.s.get(self.base, headers={"x-csrf-token": "fetch"}, timeout=TIMEOUT)
        r.raise_for_status()
        token = r.headers.get("x-csrf-token")
        if not token:
            sys.exit("no x-csrf-token in the service root response — check SAP_URL/service path in .env")
        self.s.headers.update({"x-csrf-token": token, "Accept": "application/json"})

    def post(self, entity_set, body):
        r = self.s.post(self.base + entity_set, json=body, timeout=TIMEOUT)
        if r.status_code >= 400:
            raise SapError("POST", entity_set, r)
        return r.json() if r.content else None

    def patch(self, path, body):
        r = self.s.patch(self.base + path, json=body, headers={"If-Match": "*"}, timeout=TIMEOUT)
        if r.status_code >= 400:
            raise SapError("PATCH", path, r)

    def get(self, path):
        r = self.s.get(self.base + path, timeout=TIMEOUT)
        if r.status_code >= 400:
            raise SapError("GET", path, r)
        return r.json()["value"]

    def get_all(self, path):
        """Every row of a collection: follows @odata.nextLink, whatever page size the service chooses."""
        rows, url = [], self.base + path
        while url:
            # the service's nextLink carries sap-client already; twice is a URI syntax error (HTTP 400)
            r = self.s.get(url, params={"sap-client": None} if "sap-client=" in url else None, timeout=TIMEOUT)
            if r.status_code >= 400:
                raise SapError("GET", path, r)
            data = r.json()
            rows += data["value"]
            url = urljoin(self.base, data["@odata.nextLink"]) if data.get("@odata.nextLink") else None
        return rows

    def delete(self, path):
        return self.s.delete(self.base + path, headers={"If-Match": "*"}, timeout=TIMEOUT)


def seed(sap):
    companies_added = 0
    if not sap.get("Company?$top=1"):
        for code, name, race in COMPANIES:
            sap.post("Company", {"CompanyUUID": str(uuid.uuid4()), "CompanyCode": code,
                                 "CompanyName": name, "Race": race})
        companies_added = len(COMPANIES)
    materials = load_materials()
    existing = {row["Material"]: row for row in
                sap.get("Material?$select=MaterialUUID,Material,ProducedBy,Prerequisite,MineralCost,GasCost,"
                        "SupplyProvided&$top=1000")}
    added = updated = 0
    for m in materials.values():
        synced = {"ProducedBy": m["produced_by"], "Prerequisite": m["prerequisite"],
                  "MineralCost": m["mineral_cost"], "GasCost": m["gas_cost"],
                  "SupplyProvided": m["supply_provided"]}
        row = existing.get(m["matnr"])
        if row is None:
            sap.post("Material", {"MaterialUUID": str(uuid.uuid4()), "Material": m["matnr"],
                                  "CompanyCode": m["bukrs"], "Category": m["category"],
                                  "SupplyCost": m["supply_cost"], "BuildSeconds": m["build_seconds"],
                                  **synced})
            added += 1
        elif any(row[k] != v for k, v in synced.items()):
            sap.patch(f"Material({row['MaterialUUID']})", synced)
            updated += 1
    print(f"seeded {companies_added} companies, {added} materials added, {updated} updated "
          f"({len(existing)} were present)")


def delete_game(sap, game_uuid):
    r = sap.delete(f"Game({game_uuid})")
    print(f"DELETE Game({game_uuid}) -> HTTP {r.status_code}")
    if r.status_code >= 400:
        print(r.text[:800])
        sys.exit(1)


def verify(sap, payload):
    local = stock(payload)
    remote = {}
    for row in sap.get(f"StockBalance?$filter=GameUUID eq {payload['GameUUID']}&$top=100000"):
        plant = "" if row["PlantUUID"] in (None, ZERO_GUID) else row["PlantUUID"].lower()
        remote[(row["DivisionUUID"].lower(), plant, row["Material"])] = row["OnHand"]
    local = {(d.lower(), p.lower(), m): q for (d, p, m), q in local.items()}
    diff = {k: (local.get(k), remote.get(k)) for k in set(local) | set(remote)
            if local.get(k) != remote.get(k)}
    if diff:
        for k, v in sorted(diff.items())[:20]:
            print("MISMATCH", k, "local", v[0], "remote", v[1])
        sys.exit(f"verify failed: {len(diff)} differences")
    print(f"verify ok: {len(remote)} balances match")


def parse_args(argv):
    """(payload_path_or_None, opts); flags in any order, first non-flag token is the payload path."""
    opts = {"seed": False, "verify": False, "delete": None}
    payload = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            sys.exit(__doc__)
        elif a == "--seed":
            opts["seed"] = True
        elif a == "--verify":
            opts["verify"] = True
        elif a == "--delete":
            i += 1
            if i >= len(argv):
                sys.exit("--delete needs a GameUUID argument")
            opts["delete"] = argv[i]
        elif a.startswith("--"):
            sys.exit(f"unknown flag: {a}")
        elif payload is None:
            payload = a
        else:
            sys.exit(f"unexpected argument: {a}")
        i += 1
    return payload, opts


def main(argv):
    payload_path, opts = parse_args(argv)
    if not opts["seed"] and not opts["delete"] and not payload_path:
        sys.exit(__doc__)
    sap = Sap()
    try:
        if opts["delete"]:
            return delete_game(sap, opts["delete"])
        if opts["seed"]:
            return seed(sap)
        import json
        payload = json.loads(Path(payload_path).read_text())
        sap.post("Game", payload)
        print(f"pushed game {payload['GameUUID']} ({payload['MapName']})")
        if opts["verify"]:
            verify(sap, payload)
    except SapError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main(sys.argv[1:])
