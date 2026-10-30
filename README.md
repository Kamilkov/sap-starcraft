# StarCraft Enterprise

StarCraft II replays as SAP enterprise data: companies (races), divisions (players),
plants (town halls), production orders and a goods-movement ledger, in a custom RAP app
on the A4H ABAP Platform Trial.

A fan project, not affiliated with or endorsed by Blizzard Entertainment or SAP. StarCraft is a trademark of
Blizzard Entertainment; SAP, ABAP and Fiori are trademarks of SAP SE. MIT licensed (`LICENSE`).

## Reproduce it

You need the SAP ABAP Platform Trial 2025 (A4H, the Docker image from SAP), StarCraft II
(the free Starter Edition is enough; the live bot plays Terran against the built-in AI on `AcropolisLE` from the
Ladder 2019 Season 3 map pack, placed in the game's `Maps` folder), Python 3.11+ and Node 20.6+.

1. **ABAP objects.** Install [abapGit](https://abapgit.org) (standalone report `ZABAPGIT_STANDALONE`), create the local
   package `$ZSCE`, and pull this repository into it (online repo, or *New Offline* with the repo's ZIP). The sources
   are in `abap/` (tables, CDS views, behaviour definitions and implementations, service definitions and bindings,
   ABAP Unit). Activate everything, then publish the service bindings `ZSB_SCE_O4` and `ZSB_SCE_ANALYTICS_O4` in ADT.
2. **System settings** (once per system):
   - Virus-scan switch for OData V4 uploads (see *Prerequisite* under SAP side below).
   - Currencies `MIN` and `GAS` in OY03 (ISO codes MIN/GAS), 0 decimals in OY04; exchange rate type M,
     1 GAS = 2 MIN, in OB08.
3. **Local side.** `cp .env.example .env` and fill in your system's URL, client, user and password. Then:

       python3 -m venv .venv && .venv/bin/pip install -r ingest/requirements.txt
       .venv/bin/python ingest/push.py --seed        # companies and the material master
       .venv/bin/python ingest/test_live_bot.py && .venv/bin/python ingest/test_pm.py

4. **Fiori apps.** In each of `app/game`, `app/analytics` and `app/score`: `npm install && npm run deploy` (BSPs
   `ZSCE_GAME`, `ZSCE_ANALYTICS`, `ZSCE_SCORE` in `$ZSCE`; `ui5-deploy.yaml` targets `http://localhost:50000`,
   client 001). Without a launchpad, `npm start` in an app folder runs it locally against the system.
5. **Launchpad** (optional). In the Launchpad Designer (`/sap/bc/ui5_ui5/sap/arsrvc_upb_admn/main.html?scope=CONF`)
   create catalog `ZSCE_CATALOG` with three static tiles and target mappings (application type SAPUI5 Fiori App):
   `ZSCEGame-manage` → `/sap/bc/ui5_ui5/sap/zsce_game`, `ZSCEEconomy-analyze` → `/sap/bc/ui5_ui5/sap/zsce_analytics`,
   `ZSCEScore-display` → `/sap/bc/ui5_ui5/sap/zsce_score`. Add the catalog to your user's role in PFCG (tab Menu →
   SAP Fiori Launchpad → Launchpad Catalog).
6. **Play.** `.venv/bin/python ingest/live_bot.py`, open **Game Control**, and release orders on the `LIVE`
   division (see *Live bot* below). A replay of your own goes in with `parse_replay.py` + `push.py` (see *Local side*;
   sc2reader 1.9 does not read replays of the current client; the live bot needs no replay).

## SAP side

Package `$ZSCE` (local — see note below). Service `ZSB_SCE_O4`
(`/sap/opu/odata4/sap/zsb_sce_o4/srvd/sap/zsd_sce/0001/`).

**Local package note:** a transportable `ZSCE` package could not be created — the ABAP
Platform Trial system has no working transport route/consolidation for software component
`HOME` (`CreatePackage` failed with "Change recording must be activated for package ZSCE",
message TR432). Objects live in local package `$ZSCE` instead; no transport request is
used for SAP objects in this repo.

**Prerequisite:** the OData V4 runtime rejects deep creates with `Virus scan profile
/IWBEP/V4/ODATA_UPLOAD is not active` unless `VIRUS_SCANER_IGNORED = X` is set in table
`/IWBEP/C_V4_SETT` (SAP-provided switch
`/iwbep/cl_v4_settings_dba=>set_is_virus_scan_ignored( abap_true )`; the trial has no virus
scanner). Set once per system before the first push.

The deep create never sends parent keys (`Division.GameUUID`, children's `DivisionUUID`) —
RAP fills them on create-by-association; `ingest/parse_replay.py` omits them.

## Local side

    python3 -m venv .venv && .venv/bin/pip install -r ingest/requirements.txt
    cp .env.example .env            # then fill in credentials
    .venv/bin/python ingest/push.py --seed
    .venv/bin/python ingest/parse_replay.py "<replay>.SC2Replay" payload.json
    .venv/bin/python ingest/push.py payload.json --verify
    .venv/bin/python ingest/push.py --delete <GameUUID>   # DELETE Game(<uuid>), cascades to children
    .venv/bin/python ingest/test_parse.py
    .venv/bin/python ingest/test_live_bot.py
    .venv/bin/python ingest/test_pm.py

`materials.csv` carries `produced_by`/`prerequisite` (generated from python-sc2 game data;
addons and plain TechLab/Reactor assigned by hand); `--seed` updates them and the costs on existing rows. Costs are
what the SC2 client on this Mac charges (Terran rows checked against it on 2026-09-25, e.g. Command Center 300).

## Known approximations

- Unit → plant by nearest open town hall at birth position.
- Mining income is booked at division level, from the collection rate every 160 loops.
- Raw materials (MINERAL, VESPENE) are always booked at division level, including the 261
  consumed by an order — only the 101 receipt and the order itself carry the plant. Keeps
  per-plant raw-material balances from going negative.
- Production orders are back-computed as completion − build time.
- Zergling/Baneling supply is rounded to whole numbers.
- `UnitTypeChangeEvent` (morphs — Baneling, Ravager, Lurker, Overseer, BroodLord, Lair,
  Hive, WarpGate, Archon) is ignored, so morphs produce no order; any unit/upgrade type
  not in `materials.csv` is skipped and counted (`parse_replay.py` prints the tally).

## Live bot (Phase B.1)

SAP drives an outpost. One process, one game:

```bash
.venv/bin/python ingest/live_bot.py            # --minutes 20 --map AcropolisLE --difficulty VeryEasy
```

1. The bot deep-creates a Game + Division `LIVE` (company 1000) + Plant `0001`, prints their UUIDs, then launches StarCraft II (Terran vs Zerg AI, realtime).
2. Open the Division in **Game Control** (launchpad tile; the ADT preview of `ZSB_SCE_O4` works too) → **Release Order** (Material with value help, Quantity). Each unit becomes one `ProdOrder` in status `RELEASED`. The Material value help lists the division's company materials with a Buildable column (producer and prerequisite on hand, cost within the mineral and gas balance, all from the ledger); filter on it to see what can be built now. Quantity starts at 1. A release the ledger cannot cover (no producer or prerequisite on hand or ordered, over the mineral or gas balance, a blocked material) is refused with the reason; see Part 2 rules. **Also order missing prerequisites** (ticked by default) works like MRP dependent requirements: SAP walks the tech tree (producer, prerequisite, theirs, …) and releases one order for each one the division neither has on hand nor already has on order (RELEASED/STARTED), ahead of the requested units. So 5 Marauders in a fresh game also release a Supply Depot, a Barracks and a Barracks TechLab; the dialog lists each as `1 × … released (prerequisite)`. The bot's backlog builds them in tech order. Untick it to release only what you typed.
3. The bot keeps waiting orders in a backlog, refreshed by each SAP poll (every 5 s) and retried every ~0.5 game seconds. Units are queued into the producer with the shortest queue (up to 5 per structure), so several Marines of one release go into the Barracks queue at once; STARTED means "queued in the game", which is also when SC2 deducts the cost. When a unit appears the order becomes CONFIRMED with its UnitTag. While an order waits, the "Bot message" column shows why (updated only when the reason changes; reload the page to see it). Orders can be cancelled in the Production Orders table → **Cancel Order**. A RELEASED order becomes CANCELLED at once (`cancelled in SAP`). A STARTED order becomes CANCELLING (`cancel requested`); within about 5 s the bot cancels it in the game and answers CANCELLED with `cancelled in game, refund 100%` (queued unit, research, structure whose SCV is still walking) or `refund 75%` (structure or add-on under construction; the unrecovered 25% becomes Scrap), booking the refund as 262. If the game cannot do it the order goes back to STARTED with `cannot cancel: not last in any queue` (only the last item of a production queue can be cancelled) or `not found in the game`, or to CONFIRMED with `cannot cancel: already built`.
4. Goods movements arrive live with `EventSource = LIVE`: 561 at start, 501 mining summed over four stats ticks (every ~28 s), 261 at STARTED (the game's own cost), 262 when the game refused the command (below), a cancel refunded it or a destroyed producer's queue came back, 101 at completion, 551 on death. New Command Centers become plants. So the ledger's mineral balance (Buildable column, `Waits:` warning) can lag the game by up to ~28 s.
5. On leaving or game end: duration and result are patched, the replay is saved to `replays/`, and a reconciliation line compares posted 261 − 262 minerals/gas with what the game reports as spent.

The bot builds only what SAP orders. On its own it only sends SCVs that finish a building back to the minerals of their nearest base (SC2 leaves them idle; the console prints `N idle SCV back to mining`), fills every finished Refinery next to a base with 3 SCVs from the nearest mineral miners (SC2 staffs only its builder; `N SCV to gas`; a gas SCV pulled off to build is replaced within a second, and a fourth one, usually the builder joining late, is sent back to minerals: `N SCV off gas`) and lowers every finished Supply Depot, so our units walk over the ramp wall.

**Placement**: each structure has a zone. The first two Supply Depots and the first Barracks wall off the top of the main ramp (python-sc2's ramp analysis; on one start of AcropolisLE the Barracks' add-on closes the middle of the wall), later depots go behind the main's mineral line, a Bunker stands behind the wall or, once a Command Center stands at the natural, at the natural's front, a Missile Turret in the mineral line of the base with the fewest turrets, Barracks, Factory and Starport where their add-on fits, tech buildings at the back of the main away from the ramp, and a Command Center at the next expansion (`get_next_expansion()`). The bot searches grid spots around the zone's target, skips the SCVs' mining paths, asks the game which spots it accepts in one query and builds on the nearest one exactly. With no spot the order waits and its Bot message says `no placement in <ZONE>` or `no free expansion`. Refineries and add-ons are placed as before.

The game never waits on SAP: all calls run on one worker thread (FIFO). HTTP 423 (Game locked by a Fiori action) is retried 5 times 0.5 s apart; any other failure is logged and dropped. Fiori does not retry the other way round: an action that collides with a bot write shows "You can't edit this instance at the moment. It's currently locked." and closes its dialog; repeat it. Orders of unknown materials are set to `CANCELLED`. A bot restart starts a new game; `STARTED` and `CANCELLING` orders of a dead run stay as they are. The CSRF token is fetched once per run, so if SAP drops the security session mid-game every later call fails with 403 and is logged and dropped (restart the bot). A run that ends by `--minutes` is recorded with `GameResult UNKNOWN`, not LOSS. A surrendered game closes before python-sc2 can save the replay ("replay not saved"), and if python-sc2 dies mid-game the bot still runs its end-of-game step (duration, result UNKNOWN, queue drained). In both cases python-sc2 never sends StarCraft II its quit command and its own cleanup gives up after 1.5 s, so the bot closes the client it launched itself (SIGTERM, then a hard kill after 3 s); no more black window. Only one structure order per material is issued at a time and addons are placed only when there is room, because the placement timeout and the in-game cancel find the order by its material: an order whose command the game silently refused would otherwise sit in `STARTED` with its 261 posted and nothing built. For the same reason no waiting order is tried while an SCV walks to place a structure (up to 30 s), and units are never queued into a producer that is building an addon or morphing. If the game still refuses a command silently, the bot reverses the order: a structure whose SCV has not started building after 30 s and is no longer on its way, or units missing from every production queue on two checks about 5 s apart (only orders older than 5 s count; newest first), get a 262 for exactly their 261, return to `RELEASED` with the bot message `command refused, retried` and are retried like any waiting order (the console prints `<Material>: command refused, retried, 262 posted`). Addons and research are not watched; a refused one stays `STARTED` and shows in the reconciliation line. When a structure is destroyed the bot reads its last snapshot (spike 2026-09-24): units and research in its queue come back in full, so their orders get a 262 and return to `RELEASED` with `producer destroyed, retried`; a structure destroyed under construction gives nothing back and its order ends `SCRAPPED` (`destroyed under construction`); an add-on that dies with its parent gives 75% back (`destroyed with its Barracks, refund 75%`). A Cancel Order that arrives after that is answered with the SCRAPPED status.

## Finance (Phase B.2)

Division, Game and Company pages carry finance tables computed from the goods-movement ledger,
valued at cost in two SAP currencies, **MIN** (minerals) and **GAS** (vespene), one row per
currency (SAP never adds amounts in different currencies).

| Column | Meaning |
|---|---|
| Opening | initial stock (561) |
| Mined | income from mining (501) |
| Lost | units and structures destroyed, at cost (551) |
| Scrap | what CANCELLED and SCRAPPED orders consumed and the game did not give back (261 − 262): the 25% of a structure cancelled under construction, all of one destroyed under construction |
| Maintenance | what repairs consumed: the 261 posted on maintenance orders. Expense at once, never WIP; the repaired structure's asset value does not change |
| Net worth | Opening + Mined − Lost − Scrap − Maintenance |
| On hand | minerals / gas in the bank |
| Assets | units, structures and upgrades at cost |
| Army | units at cost, workers included |
| WIP | consumed for orders not received yet; 262 reversals (refused commands) take their 261 back out; CANCELLED and SCRAPPED orders count as Scrap instead; negative WIP means a receipt without consumption |

- Division page: **Finance** (its two rows) and **Outpost finance** (opening, produced, lost and net asset
  value per town hall; outposts have no income because mining is posted per division).
- Game page: **Finance**, every division of the game. Company page: **Finance across games**.
- Views: `ZI_SCEEventAmount` (one row per event and currency), `ZI_/ZC_SCEDivisionFinance`,
  `ZI_/ZC_SCEPlantFinance`; entity sets `DivisionFinance`, `PlantFinance`.
- Amounts are `dec(15,0)`: `decfloat34` switches the whole OData service to 4.01, which UI5 1.136
  rejects (every app fails with "Could not open app"); `curr` is shifted ×100 for 0-decimal currencies.
- New system prerequisite: currencies `MIN` and `GAS` (ISO codes MIN/GAS) in OY03, 0 decimals in OY04.
- **Net worth (MIN)** (B.2.1): the Divisions tables on the Game and Company pages show each division's net
  worth in one number, gas converted at the exchange rate M GAS→MIN (made up: 1 GAS = 2 MIN, maintained in
  OB08) by CDS `currency_conversion` in `ZI_SCEDivisionNetWorth`. The conversion runs on `decfloat34` inside
  the view (it accepts only decfloat34 or 2-decimal amounts) and is cast back to `dec(15,0)` before OData
  sees it. No rate → empty column. Not unit-tested: the CDS test double framework does not support
  `currency_conversion`. New system prerequisite: the same rate in OB08.
- **Order variances** (Division page, Production Orders table): *Std time* (material master build time),
  *Lead time* (ConfirmedAt − ReleasedAt, CONFIRMED orders), *Time variance* (lead − standard; the 5th Marine
  in a queue of 5 shows about +72 s), *Price variance (MIN)* (261 − 262 consumed − standard cost, gas at rate M;
  STARTED and CONFIRMED orders) and *Scrap variance (MIN)* (what a CANCELLED or SCRAPPED order consumed,
  261 − 262, gas at rate M). A column that does not apply to an order (lead and time variance before CONFIRMED,
  price variance of a RELEASED order, scrap variance of a live one) shows 0, not blank: the views return NULL,
  but the transactional OData service declares every property non-nullable, so a NULL arrives as 0. Views `ZI_SCEOrderConsumption`, `ZI_SCEOrderVariance`
  (unit-tested), `ZI_SCEOrderVarianceMin` (the conversion, kept separate because the CDS test double
  framework does not support `currency_conversion`). Replays show 0 everywhere: their release time is
  back-computed from the build time and their 261 comes from the material master. Live `ReleasedAt` is the
  moment the order is queued in the game; the wait in the bot's backlog before that is not measured.

## Verified on 2026-09-22 (re-verified after final-review fix wave)

- `ingest/test_parse.py` passes on a sample replay: 2 divisions, 56 events,
  6 orders, **7 stock rows** (was 8 — raw-material 261/501/561 postings are now division
  level only, so the per-plant MINERAL row that used to duplicate the division-level one
  is gone).
- `push.py --delete <GameUUID>` on the pre-existing game returned HTTP 204; confirmed
  `zsce_game`/`zsce_division`/`zsce_plant`/`zsce_prodord`/`zsce_event` all at 0 rows.
- `push.py --seed` is resumable: rerun against the already-seeded system printed
  `seeded 0 companies, 0 materials (128 already present)` and posted nothing.
- `parse_replay.py <replay> payload.json` also prints a skipped-materials
  tally, e.g. `SprayTerran×4, BeaconArmy×2, …` (16 distinct SC2 spray/beacon pseudo-units,
  none of them real production).
- `push.py payload.json --verify` pushed the sample replay and verified **7/7** stock
  balances; re-running `push.py --verify payload.json` (flag before the path) against the
  same payload is rejected with HTTP 400 and exits 1 — proving both the any-order flag
  parsing and the duplicate-push rejection.
- `SELECT COUNT(*) FROM zi_scestockbalance` = 7; the two `MATERIAL = 'MINERAL'` rows both
  carry the zero/initial `PLANTUUID` (no plant-level MINERAL row).
- ABAP Unit `ZBP_SCEGAME`: 3 tests green (unchanged by this wave).
- OData V4 service `ZSB_SCE_O4` is published; `Game`, `StockBalance` and `Company` all
  answer HTTP 200. Raw-URL check
  `Game?$expand=_Division($expand=_Plant,_ProdOrder,_Event)` returns the game
  "Void Training Stage 1" (79 s) with 2 divisions (P1 Kamil LOSS, P2 Player 2 WIN, both
  company 1000), 1 plant each, and orders/events present; `StockBalance` returns 7 rows
  (e.g. SCV=13 and SupplyDepot=1 for P2, MINERAL=508/243 per division, both division-level).
- Fiori Elements preview of `ZSB_SCE_O4` (service binding → entity `Game` → Preview, in
  Eclipse ADT): Game and Division Object Pages came up header-only, so `#LINEITEM_REFERENCE`
  facets were added to `ZC_SCEGame` (`_Division`) and `ZC_SCEDivision` (`_Plant`,
  `_ProdOrder`, `_Event`); Object Pages now show the tables (confirmed in ADT, 2026-09-22).

## MRP (Phase B.3)

The SAP planning cycle on the Division page:

1. **Plan Requirement** (MD61): Material, Quantity, Due at minute (starts five minutes after the division's game
   clock, its latest goods movement; the chain for a Marauder takes 190 s, so plan a minute later than the
   default). Listed under **Planned Requirements**; select one and press **Delete** to remove it (a row action,
   because the Division page has no edit mode; its planned orders stay until the next run, as in SAP).
2. **Run MRP** (MD01, regenerative): the division's planned orders are replaced. Targets are netted per material
   in due order against stock on hand and RELEASED/STARTED production orders (targets add up, as SAP's PIRs;
   units lost in the game are replanned by the next run). Units come in lots of 5 (one producer's queue,
   quantity × build time), structures and upgrades one per planned order; each lot finishes at its due time.
   Missing producers and prerequisites (the Release Order tech-tree walk) get one planned order each, finishing
   when the first item that needs them starts. A producer or prerequisite that is planned too late for what
   needs it is moved earlier, and what it needs follows.
   Supply: a lot needs quantity × supply cost at its start, a provider delivers at its finish. A shortage is
   covered by Supply Depots (the company's cheapest provider per supply) that finish when the lot starts, up
   to the cap of 200, and only if a worker is in stock or on order. The Barracks' own depot comes with its
   worker and counts, unless that worker is short of supply itself.
   Exceptions, the first that applies: `finish in the past`, `start in the past`, `short of supply`,
   `reschedule in to <t> s`. Infinite capacity, as classic MRP: a lot does not wait for another one on the
   same producer. Messages `MRP at <clock> s: planned orders <n>, exceptions <e>` and
   `Supply <used> of <capacity> now, <used> of <capacity> planned`; used above capacity is a shortage.
3. **Convert** (CO40/CO41, select one or more rows under **Planned Orders**): a planned order of n becomes n
   RELEASED single-unit production orders (`converted from planned order`), which the bot builds.
4. **Firm** and **Unfirm** (select rows under **Planned Orders**): a firmed planned order survives the run with
   its dates. It covers targets and needs like stock; if it finishes too late for one, the run flags it
   `reschedule in to <t> s` and plans nothing in its place (SAP's rescheduling check without horizon and
   tolerance). Unfirm it and run MRP to have it replanned.

Each action refreshes the table it changes (RAP side effects), and a row opens a Details page.
Not planned: minerals and gas, capacity. Firmed orders cannot be changed. Supply provided per material is in
the material master (`materials.csv`, from this SC2 client's game data: a Command Center gives 13).
Objects: `zsce_material-supply_provided`, `zsce_planord-firmed`, `ZSCE_PIR`, `ZSCE_PLANORD`, `ZI_/ZC_SCEPIR`, `ZI_/ZC_SCEPlannedOrder`,
`ZA_SCEPlanRequirement`, `lcl_mrp` in `ZBP_SCEGAME` (ABAP Unit `ltc_mrp`, `ltc_mrp_actions`).

## Plant Maintenance (serial numbers, equipment, repair)

Custom objects on purpose: the trial has no
standard PM (no `EQUI`, `QMEL`, `AFIH`).

| SAP | Here |
|---|---|
| Serial number (IQ03) | every unit and structure, key division + game tag; derived from the tagged receipts (101, 561), `DESTROYED` with its 551. Entity set `SerialNumber` |
| Equipment (IE03), functional location | every structure, at the outpost of its receipt; status `OK`, `DAMAGED`, `IN_REPAIR`, `DESTROYED`. Entity set `Equipment` |
| Notification (IW21) | `ZSCE_NOTIF`, raised by the bot at the first damage it sees on a finished structure: `OPEN` → `IN_PROCESS` → `CLOSED`; priority 1 below a third of the health, 2 below two thirds, else 3 |
| Maintenance order (IW31) | `ZSCE_MAINTORD`, created by the player with **Create Repair Order** on an OPEN notification: `RELEASED` → `STARTED` → `CONFIRMED`, or `CANCELLING` → `CANCELLED` |
| Goods issue to the order, settlement | 261 of MINERAL / VESPENE with the order's UUID, no plant; shown as **Maintenance** in Finance at once |

1. A structure is damaged: within about a second the bot posts a notification. Reload the Division page:
   **Maintenance Notifications** shows it, **Equipment** shows the structure `DAMAGED`.
2. Select the notification → **Create Repair Order**. The bot repairs nothing without an order.
3. Within one poll (5 s) the bot reserves the nearest free SCV and sends it: `STARTED`, `SCV on its way`, then
   `repairing`. An order that cannot start says why in **Bot message** (`cannot afford repair`, `no free SCV`,
   `equipment is flying`, `cannot reach equipment`, `waiting for the repair of …`).
4. When the SCV no longer holds the repair order and the structure is at full health: `CONFIRMED`, notification
   `CLOSED`, and the cost is posted. An interrupted repair (bank empty, SCV lost or stopped) posts what it cost so
   far and goes back to `RELEASED`; the bot starts it again.
5. **Cancel Order**: a `RELEASED` order is cancelled in SAP at once; a `STARTED` one becomes `CANCELLING`, the bot
   sends the SCV back to mining and answers `CANCELLED`, the notification is `OPEN` again.
6. A destroyed structure ends its order (`CANCELLED`, `equipment destroyed`) and closes its notification. Damage
   that is gone without an order closes the notification with `no damage found`.

**Cost** is exact, not estimated: the change of `opening bank + collected − spent − bank` between the repair
command and the first observation in which the SCV no longer holds the repair order (spike 2026-09-27: the game
charges whole units in advance and no score field reports repair spending). The console ends with
`+ repair posted minerals M gas G | exact measure minerals M gas G` and `+ PM unacknowledged N | parked N`.

**PM calls are acknowledged** (production calls keep log-and-drop): a fact is sent again with the same UUID and
body until SAP answers; an answer nobody received is resolved by reading the row back. SAP decides every status
transition itself (actions `reportNotification`, `reportRepair`); neither entity can be updated from outside.

**Limits:** one repair in work at a time, one SCV per order, structures only. The outbox lives in memory: what is
unacknowledged when the process ends is lost and printed, and a restarted bot adopts no open notification or
order. Replays give serial numbers and equipment only (no health in the tracker events).

**Checked automatically 2026-09-28:** ABAP Unit 95, OData check 79, `ingest/test_pm.py`, a browser check of the
deployed pages (42) and one scripted live game (21). Manual acceptance is open.

## Game Control (Fiori app)

The transactional service `ZSB_SCE_O4` as a deployed app: tile **Game Control** on My Home (catalog `ZSCE_CATALOG`),
intent `https://vhcala4hci:50001/sap/bc/ui2/flp?sap-client=001#ZSCEGame-manage`. Same pages and actions as the ADT
preview, which it replaces for playing: Games (loads on open) → Game (Divisions, Finance) → Division (Finance,
Outposts, Equipment, Outpost finance, Production Orders, Planned Requirements, Planned Orders, Maintenance
Notifications, Maintenance Orders, Goods Movements, Serial Numbers; Release Order, Plan Requirement, Run MRP,
Cancel Order, Convert, Delete, Create Repair Order) → Production Order, Outpost, Planned Requirement, Planned Order
or Goods Movement with a Details section; Equipment (Details, Maintenance Notifications, Maintenance Orders,
History), Maintenance Notification (Details, Maintenance Orders), Maintenance Order (Details, Goods Movements),
Serial Number (Details, History). Fiori Elements V4 List Report / Object Page `app/game/` (UI5 1.136), BSP
`ZSCE_GAME`; the generator builds two levels, the nine level-3 pages are routes in `manifest.json`.

```bash
cd app/game && npm install
npm run deploy     # BSP ZSCE_GAME in $ZSCE; credentials from ../../.env (SAP_USER, SAP_PASSWORD)
```

## Economy Analysis (Phase B.4)

An Analytical List Page in the Fiori launchpad of A4H:
tile **Economy Analysis** on My Home (catalog `ZSCE_CATALOG`, "StarCraft Enterprise", in role `ZDEVELOPER`), intent
`https://vhcala4hci:50001/sap/bc/ui2/flp?sap-client=001#ZSCEEconomy-analyze`.

- Opens on the latest game (filter **Latest game = Yes**: the newest game by creation, so a game in progress too).
  Clear it to compare games; every filter has a value help (Latest game, Race, Movement type and Category as dropdowns).
- Chart **Economy per minute**: Value (MIN) per game minute, stacked by movement type (Opening stock, Mining,
  Consumption, Reversal, Receipt, Loss). "View By" adds a level (Game, Material, Category, Player, Race); save
  combinations (e.g. Loss + Material) as variants.
- Table: one row per goods movement, with totals. Value (MIN) = minerals + gas at rate M (OB08), like Net worth (MIN).
- Amounts are the ledger's raw movements (a 262 refund is positive); balances and scrap stay in the Finance views.
- Visual filter bar (the page opens on it; the toggle at the top right switches to the compact filters): bar charts
  Value (MIN) by Movement type, by Category and by Material. A click on a bar filters the page, and each chart follows
  the other filters. They are defined in the app's `annotation.xml` (`Common.ValueList#Vf…` on the entity set itself),
  not in CDS: RAP refuses a value help on the analysed view (`VH_VIEW_SAME_AS_SOURCE_VIEW`). OData V4 limits: bar
  charts only (no donut; a line chart needs a date or time field).
- The table is grouped by movement type with subtotals (`UI.PresentationVariant#Table`, also in `annotation.xml`).
- Objects: `ZI_SCELatestGame`, `ZI_SCEMovementAnalysis` (ABAP Unit `ZCL_SCE_ANALYSIS_TEST`), `ZI_SCEMovementValue`
  (gas in MIN), `ZC_SCEMovementAnalysis`, value helps `ZC_SCEGameVH`, `ZC_SCEPlayerVH`, `ZC_SCEMovementTypeVH`, `ZC_SCELatestGameVH`, `ZC_SCERaceVH`,
  `ZC_SCECategoryVH`, `ZC_SCEMaterialVH`,
  service `ZSD_SCE_ANALYTICS` / `ZSB_SCE_ANALYTICS_O4`, BSP `ZSCE_ANALYTICS`, app `app/analytics/` (Fiori Elements V4
  ALP, UI5 1.136). Launchpad content in customizing scope (service `PAGE_BUILDER_CUST`): configuration scope
  records into a released transport on the trial.

```bash
cd app/analytics && npm install
npm start          # local, Fiori tools proxy to A4H (the browser asks for the SAP login)
npm run deploy     # BSP ZSCE_ANALYTICS in $ZSCE; credentials from ../../.env (SAP_USER, SAP_PASSWORD)
```

## Score over time (Phase B.5)

A second Analytical List Page: tile
**Score over time** on My Home (catalog `ZSCE_CATALOG`), intent
`https://vhcala4hci:50001/sap/bc/ui2/flp?sap-client=001#ZSCEScore-display`. SC2's post-game graphs, the SAP way.

- Running totals per player and game minute: Army value (units without SCVs, in MIN), Workers (SCVs alive), Bank
  minerals and Bank gas (unspent), Collected (mined, in MIN), Lost (in MIN). Stock curves are signed like the stock
  balance, so the last minute equals the stock on hand.
- Opens on the latest game with the chart **Army and losses**; clear Latest game and choose games to overlay them.
  Other curves (Workers, Bank, Collected): chart settings, saved as public variants.
- KPI tags Collected, Army peak and Lost always show the latest game (Fiori Elements V4 tags ignore the filter bar).
  They are defined in `app/score/webapp/annotations/annotation.xml`, not in CDS: RAP's `@UI.kpi` output is not
  readable by Fiori Elements V4 on this release.
- Chart series are Game and Player, so the two players of a replay keep their own lines.
- The KPI cards' charts are overridden in the app's `annotation.xml` with the currency as a dimension: SADL refuses to
  aggregate an amount without its currency in the grouping, and the cards stayed empty.
- Measures aggregate with MAX: a collapsed minute axis shows peak or final values, never a sum of running totals.
- Objects: `ZI_SCEMovementValueMin` (Value (MIN) per movement, shared with Economy Analysis), `ZI_SCEScoreMinute`
  (time axis), `ZI_SCEScore` (the minute grid joined to every movement up to that minute; ABAP Unit
  `ZCL_SCE_SCORE_TEST`), `ZC_SCEScore`, entity set `Score` in `ZSD_SCE_ANALYTICS`, BSP `ZSCE_SCORE`, app `app/score/`.

```bash
cd app/score && npm install
npm run deploy     # BSP ZSCE_SCORE in $ZSCE; credentials from ../../.env (SAP_USER, SAP_PASSWORD)
```

## Part 2 rules (Plan A)

The SAP side of the Terran vs Protoss match (design: `docs/superpowers/specs/2026-10-29-part2-terran-vs-protoss-design.md`,
gitignored). SAP is the rule keeper for what a planner orders: a production order reaches RELEASED only through
these checks. Event postings and the refund of a STARTED order back to RELEASED stay with the bot and are not checked;
locking LIVE postings to the bot's own user is a later step.

- **Order blocking.** `Material.OrderBlocked` (blank = orderable) is `X` for Archon, WarpGate, WarpGateResearch and
  Carrier (company 3000), SAP's "blocked for procurement". The Protoss tech tree is in `materials.csv`;
  `ingest/check_materials.py` compares the CSV with the SC2 client (build 5.0.16.97563, Base97563) and
  `ingest/test_materials.py` guards it. `BuildableMaterial` leaves blocked materials out; the Release Order value
  help lists every orderable material with a Buildable column (the default Buildable filter is gone).
- **Availability check** (`validateAvailability` on the production order). A new order needs quantity ≥ 1 and status
  RELEASED or CONFIRMED (CONFIRMED is replay ingestion and is not checked). A RELEASED order is refused for a blocked
  or unknown material (`X cannot be ordered`), a missing producer or prerequisite (`Needs X: none on hand or ordered`:
  stock plus open orders count) and a budget overrun (`Over budget: N MIN needed, M available`, the same with GAS;
  stock minus what open orders already committed). All new RELEASED orders of a division in one save are priced
  together. Material and Quantity are read-only after creation.
- **Status walk guard** (beyond the plan). An order enters RELEASED, STARTED or CANCELLING only from one of those three
  statuses, else `{db status} order cannot go back to {status}`; a CONFIRMED or CANCELLED order cannot be reopened.
  A new order in any other status is refused with `Orders are created RELEASED, not {status}`. Closes the bypass
  around the availability check.
- **Game clock.** `Division.GameClock` (seconds, written by the referee) is the division's time. Plan Requirement's
  default due minute and Run MRP use it, falling back to the latest event time while it is 0. Plan Requirement refuses
  a blocked material; Run MRP skips blocked PIRs with the warning `X: not orderable`.
- **Army posture.** `Division.ArmyPosture` (DEFEND or ATTACK) is written only by the action `setPosture` (button
  **Set Army Posture** on the Division page). ATTACK needs an army value of at least 500 MIN
  (`ZI_SCEDivisionArmyValue`: SCV and Probe excluded, gas counted at rate M as in Score over time, a Marauder is
  150 MIN); otherwise `Army N MIN, attack needs 500`. Any other posture is refused with `Posture X unknown`
  (upper case, as sent).
- **Record result.** The Game action `recordResult(WinnerDivisionUUID, DurationSeconds, IsVoid)` writes WIN and LOSS,
  TIE (blank winner) or VOID (`IsVoid`, any winner ignored) on every division, the winner and the duration on the
  game, in one save. A winner outside the game is refused (`Winner is not a division of this game`).
  **Re-record guard** (beyond the plan): a game whose divisions already carry a result is refused
  (`Result already recorded`), so the action cannot rewrite a result. A plain PATCH of `GameResult` stays open
  because a single-bot Part 1 game writes its own result; in Part 2 only the referee writes results.
- **Score.** Probes count as workers, not army, like SCVs (`ZI_SCEScore`).
- Division is `etag dependent by _Game`: PATCH and bound actions need `If-Match: *`, as `ingest/push.py` sends.

## Next (phase B)

- Replay parser: a building killed under construction still posts a lone 551 at full cost without 261/101 (Assets too low, On hand too high; totals right).
- Plant Maintenance follow-ups: several repairs at once, repair of units, adoption after a restart, tags shown
  without thousands separators (`4.348.444.673`), orders created automatically for priority 1.
- Live bot follow-ups: cancelling a unit that is not last in its queue, an SCV killed mid-construction (the site pauses, its order stays STARTED), adopting STARTED
  orders after a restart, Zerg/Protoss outposts (only addon handling is Terran-specific).
- abapGit export of `$ZSCE`.
- Play a real game (vs AI is fine) for deaths, expansions and upgrades the sample lacks:
  save it, run `parse_replay.py` + `push.py --verify` on it, and check that the Terran
  company page now aggregates two games.
- Unique index on `zsce_game.replay_hash` (today only `validateReplayHash` catches
  duplicates; two concurrent requests are not caught).
- Handle `UnitTypeChangeEvent` (morphs).
- Real-scale replays: 3–4k events in one deep create — fall back to
  `POST Division(<uuid>)/_Event` per chunk if the trial chokes.
- Extend the ABAP Unit deep-create test to `_Plant`/`_ProdOrder`.
- Run ATC over `$ZSCE`.
