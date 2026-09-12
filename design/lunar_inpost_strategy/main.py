from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Callable
import copy
import heapq
import math
import random

# ============================================================
# LUNAR INPOST v2
# Strategy layer for a narrative game.
# One turn = 3 Earth days. Campaign = 12 turns / 36 days.
# The world acts autonomously, but player courier decisions are scarce,
# high-leverage interventions that can change survival and politics.
# ============================================================

RESOURCES = ("life", "food", "parts", "fuel")
RESOURCE_LABEL = {
    "life": "LIFE (woda+tlen)",
    "food": "FOOD",
    "parts": "PARTS",
    "fuel": "FUEL",
}

ROAD_SPEED_KMH = {"highway": 55.0, "track": 24.0, "wilderness": 10.0}
ROAD_RISK_MULT = {"highway": 0.70, "track": 1.00, "wilderness": 1.35}


@dataclass
class Faction:
    name: str
    kind: str
    power: int
    trust_inpost: int
    hostility: int
    credits: int
    doctrine: str


@dataclass
class Location:
    name: str
    region: str
    owner: str
    population: int
    stocks: Dict[str, int]
    production: Dict[str, int]
    consumption: Dict[str, int]
    capacity: Dict[str, int]
    stability: int = 70
    security: int = 2
    comms: int = 2
    self_sufficiency: float = 0.0
    tags: List[str] = field(default_factory=list)
    shortage_turns: Dict[str, int] = field(default_factory=lambda: {r: 0 for r in RESOURCES})
    collapsed: bool = False


@dataclass
class Route:
    a: str
    b: str
    mode: str  # rover / hopper / orbital
    distance_km: int
    base_days: float
    fuel_cost: int
    risk: float
    road_class: str = "none"
    condition: int = 100
    active: bool = True


@dataclass
class Shipment:
    sid: int
    source: str
    destination: str
    cargo: str
    amount: int
    kind: str  # trade / humanitarian / military / passenger / bio
    passengers: int = 0
    value_ls: int = 0
    priority: int = 1
    sponsor: str = "InPost Lunar"
    description: str = ""


@dataclass
class Courier:
    name: str
    location: str
    rover_range_km: int = 600
    hopper_access: bool = True
    orbital_access: bool = False
    reputation: int = 50
    credits: int = 0
    completed: int = 0


@dataclass
class InPostState:
    liquidity: int = 150
    trust: int = 82
    neutrality: int = 90
    network_capacity: int = 3  # NPC shipments / turn; the player is a major fourth strategic delivery
    satellites: int = 6
    max_satellites: int = 7
    surface_network: int = 70


@dataclass
class WorldState:
    turn: int = 0
    trade_flow: int = 75
    network: int = 84
    war_tension: int = 28
    pirate_strength: int = 4
    ai_compute: int = 2
    hidden_model_discovered: bool = False
    events: List[str] = field(default_factory=list)
    history: List[dict] = field(default_factory=list)
    next_shipment_id: int = 1


# ----------------------------
# World data
# ----------------------------

def make_factions() -> Dict[str, Faction]:
    return {
        "InPost Lunar": Faction("InPost Lunar", "logistics", 5, 100, 0, 150,
            "Zysk przez przepływ. Utrzymać Księżyc przy życiu i zachować neutralność."),
        "Silesian Union": Faction("Silesian Union", "miners", 4, 86, 14, 50,
            "Autonomia, bezpieczeństwo pracy, przemysł ciężki."),
        "Blooming Flower Authority": Faction("Blooming Flower Authority", "china", 7, 56, 28, 100,
            "Najwyższa samowystarczalność, stabilność i kontrola własnej infrastruktury."),
        "US Space Navy": Faction("US Space Navy", "military", 8, 61, 35, 100,
            "Kontrola orbity. Gwarant Lunar Dollar przez paliwo, dokowanie i siłę."),
        "Lunar Science Compact": Faction("Lunar Science Compact", "science", 3, 94, 4, 35,
            "Zachować wiedzę, medycynę i obserwatoria."),
        "Luna Grand Consortium": Faction("Luna Grand Consortium", "billionaires", 5, 78, 8, 180,
            "Kapitał, usługi, luksus i możliwość ewakuacji."),
        "Free Crater Brotherhood": Faction("Free Crater Brotherhood", "pirates", 4, 6, 72, 30,
            "Polować na przepływy, okup, czarny rynek."),
        # Secret faction. It is not exposed as a normal strategic node.
        "The Model": Faction("The Model", "hidden_ai_cult", 3, 35, 18, 20,
            "Przetrwać w ukryciu, zdobywać hardware, chłodziwo, energię i dane."),
    }


def cap(**kwargs) -> Dict[str, int]:
    return {r: kwargs.get(r, 12) for r in RESOURCES}


def stocks(**kwargs) -> Dict[str, int]:
    return {r: kwargs.get(r, 0) for r in RESOURCES}


def make_locations() -> Dict[str, Location]:
    # Global output is broadly sufficient; local output is deliberately mismatched.
    # Blooming Flower is the exception: it can survive isolation much longer.
    return {
        "InPost Central": Location(
            "InPost Central", "Nearside Equatorial", "InPost Lunar", 1800,
            stocks(life=8, food=8, parts=9, fuel=10),
            stocks(life=1, food=0, parts=1, fuel=2),
            stocks(life=1, food=1, parts=1, fuel=1), cap(life=12, food=12, parts=14, fuel=15),
            stability=86, security=4, comms=3, tags=["hub", "cosmodrome", "warehouse"]),
        "Armstrong": Location(
            "Armstrong", "Mare Tranquillitatis", "Lunar Science Compact", 1200,
            stocks(life=6, food=5, parts=5, fuel=4),
            stocks(life=1, food=0, parts=1, fuel=0),
            stocks(life=1, food=1, parts=1, fuel=1), cap(),
            stability=78, security=2, comms=2, tags=["science", "historic"]),
        "Luna Grand": Location(
            "Luna Grand", "Mare Imbrium", "Luna Grand Consortium", 900,
            stocks(life=5, food=7, parts=3, fuel=4),
            stocks(life=0, food=1, parts=0, fuel=0),
            stocks(life=1, food=1, parts=1, fuel=1), cap(),
            stability=82, security=3, comms=2, tags=["hotel", "finance"]),
        "Tycho Station": Location(
            "Tycho Station", "Tycho", "Lunar Science Compact", 1600,
            stocks(life=5, food=4, parts=7, fuel=4),
            stocks(life=0, food=0, parts=2, fuel=0),
            stocks(life=1, food=1, parts=1, fuel=1), cap(parts=15),
            stability=76, security=2, comms=3, tags=["science", "medical", "relay"]),
        "Silesia": Location(
            "Silesia", "South Polar Highlands", "Silesian Union", 4200,
            stocks(life=4, food=4, parts=10, fuel=5),
            stocks(life=0, food=0, parts=3, fuel=1),
            stocks(life=2, food=1, parts=1, fuel=1), cap(life=14, food=12, parts=18, fuel=12),
            stability=72, security=3, comms=2, tags=["miners", "industry"]),
        "Lubin Deep": Location(
            "Lubin Deep", "South Polar Highlands", "Silesian Union", 2100,
            stocks(life=4, food=4, parts=9, fuel=4),
            stocks(life=0, food=0, parts=3, fuel=0),
            stocks(life=1, food=1, parts=1, fuel=1), cap(parts=17),
            stability=70, security=2, comms=1, tags=["mine", "metals"]),
        "Shackleton Ice": Location(
            "Shackleton Ice", "South Pole", "Silesian Union", 1700,
            stocks(life=11, food=3, parts=3, fuel=10),
            stocks(life=4, food=0, parts=0, fuel=3),
            stocks(life=1, food=1, parts=1, fuel=1), cap(life=18, fuel=18),
            stability=74, security=3, comms=2, tags=["ice", "fuel"]),
        "Gateway Ground": Location(
            "Gateway Ground", "Nearside Equatorial", "US Space Navy", 2600,
            stocks(life=6, food=6, parts=8, fuel=12),
            stocks(life=1, food=0, parts=2, fuel=3),
            stocks(life=1, food=1, parts=1, fuel=2), cap(parts=16, fuel=20),
            stability=84, security=5, comms=3, tags=["navy", "orbital", "spaceport"]),
        "Copernicus Freeport": Location(
            "Copernicus Freeport", "Copernicus", "InPost Lunar", 1900,
            stocks(life=6, food=6, parts=6, fuel=7),
            stocks(life=0, food=0, parts=1, fuel=1),
            stocks(life=1, food=1, parts=1, fuel=1), cap(),
            stability=78, security=2, comms=2, tags=["freeport", "warehouse"]),
        "Aristarchus Beacon": Location(
            "Aristarchus Beacon", "Aristarchus", "InPost Lunar", 250,
            stocks(life=4, food=3, parts=3, fuel=3),
            stocks(), stocks(life=1, food=1, parts=0, fuel=0), cap(life=7, food=7, parts=7, fuel=7),
            stability=68, security=1, comms=2, tags=["beacon", "paczkomat"]),
        "Kepler Scrapyard": Location(
            "Kepler Scrapyard", "Kepler", "Free Crater Brotherhood", 700,
            stocks(life=3, food=3, parts=10, fuel=6),
            stocks(life=0, food=0, parts=2, fuel=1),
            stocks(life=1, food=1, parts=0, fuel=1), cap(parts=16),
            stability=58, security=4, comms=1, tags=["pirates", "salvage", "black_market"]),
        "Chang'e Relay": Location(
            "Chang'e Relay", "Farside Relay Zone", "Blooming Flower Authority", 700,
            stocks(life=7, food=7, parts=7, fuel=7),
            stocks(life=1, food=1, parts=1, fuel=1),
            stocks(life=1, food=1, parts=1, fuel=1), cap(),
            stability=88, security=4, comms=3, self_sufficiency=0.75, tags=["relay", "china"]),
        "Blooming Flower": Location(
            "Blooming Flower", "Farside Midlatitudes", "Blooming Flower Authority", 9000,
            stocks(life=10, food=12, parts=10, fuel=8),
            stocks(life=2, food=3, parts=3, fuel=1),
            stocks(life=2, food=2, parts=2, fuel=2), cap(life=18, food=20, parts=18, fuel=16),
            stability=92, security=5, comms=3, self_sufficiency=0.90, tags=["city", "china", "farms", "industry"]),
        "Daedalus Port": Location(
            "Daedalus Port", "Farside Equatorial", "Blooming Flower Authority", 2400,
            stocks(life=7, food=7, parts=8, fuel=9),
            stocks(life=1, food=1, parts=2, fuel=2),
            stocks(life=1, food=1, parts=1, fuel=2), cap(parts=15, fuel=16),
            stability=86, security=4, comms=2, self_sufficiency=0.70, tags=["china", "spaceport"]),
    }


def make_routes() -> List[Route]:
    return [
        # Nearside corridor
        Route("InPost Central", "Armstrong", "rover", 440, 0, 1, 0.05, "highway", 92),
        Route("InPost Central", "Gateway Ground", "rover", 560, 0, 1, 0.07, "track", 78),
        Route("InPost Central", "Copernicus Freeport", "hopper", 920, 0.5, 2, 0.07),
        Route("Copernicus Freeport", "Luna Grand", "rover", 390, 0, 1, 0.07, "highway", 84),
        Route("Copernicus Freeport", "Aristarchus Beacon", "rover", 480, 0, 1, 0.13, "track", 66),
        Route("Copernicus Freeport", "Kepler Scrapyard", "rover", 340, 0, 1, 0.22, "wilderness", 45),
        Route("Aristarchus Beacon", "Luna Grand", "hopper", 760, 0.5, 2, 0.10),
        Route("Kepler Scrapyard", "Luna Grand", "rover", 500, 0, 1, 0.24, "wilderness", 38),
        # Polar belt
        Route("Armstrong", "Tycho Station", "hopper", 1180, 0.6, 2, 0.07),
        Route("Tycho Station", "Silesia", "hopper", 720, 0.5, 2, 0.09),
        Route("Silesia", "Lubin Deep", "rover", 270, 0, 1, 0.05, "highway", 88),
        Route("Silesia", "Shackleton Ice", "rover", 330, 0, 1, 0.06, "highway", 81),
        Route("Lubin Deep", "Shackleton Ice", "rover", 310, 0, 1, 0.08, "track", 74),
        Route("Gateway Ground", "Tycho Station", "hopper", 1450, 0.7, 3, 0.07),
        # Farside / orbital
        Route("Gateway Ground", "Chang'e Relay", "orbital", 2600, 0.8, 4, 0.12),
        Route("Gateway Ground", "Daedalus Port", "orbital", 2900, 0.9, 4, 0.14),
        Route("Chang'e Relay", "Blooming Flower", "rover", 620, 0, 1, 0.05, "highway", 95),
        Route("Blooming Flower", "Daedalus Port", "rover", 520, 0, 1, 0.05, "highway", 96),
        Route("Tycho Station", "Daedalus Port", "orbital", 3200, 1.0, 5, 0.16),
        Route("Shackleton Ice", "Daedalus Port", "hopper", 3850, 1.2, 5, 0.18),
        Route("InPost Central", "Blooming Flower", "orbital", 2750, 0.9, 4, 0.15),
        # Secret route is intentionally not here. The Model's sanctuary is discovered narratively.
    ]


class Game:
    def __init__(self, seed: int = 42):
        self.rng = random.Random(seed)
        self.factions = make_factions()
        self.locations = make_locations()
        self.routes = make_routes()
        self.inpost = InPostState()
        self.world = WorldState()
        self.courier = Courier("Siwy-04", "Silesia", rover_range_km=650, hopper_access=True)

    # ----------------------------
    # Network helpers
    # ----------------------------
    def route_days(self, r: Route) -> float:
        if r.mode != "rover":
            return r.base_days
        speed = ROAD_SPEED_KMH.get(r.road_class, 10.0)
        speed *= max(0.45, r.condition / 100)
        overhead = {"highway": 0.08, "track": 0.18, "wilderness": 0.35}.get(r.road_class, 0.35)
        return r.distance_km / speed / 24.0 + overhead

    def route_risk(self, r: Route) -> float:
        mult = ROAD_RISK_MULT.get(r.road_class, 1.0) if r.mode == "rover" else 1.0
        condition_penalty = 1.0 + max(0, 70 - r.condition) / 100 if r.mode == "rover" else 1.0
        pirate_pressure = 1.0 + 0.06 * max(0, self.world.pirate_strength - 3)
        return min(0.75, r.risk * mult * condition_penalty * pirate_pressure)

    def neighbors(self, node: str):
        for r in self.routes:
            if not r.active:
                continue
            if r.a == node:
                yield r.b, r
            elif r.b == node:
                yield r.a, r

    def shortest_path(self, start: str, goal: str, courier: Optional[Courier] = None):
        q = [(0.0, start, [])]
        best = {start: 0.0}
        while q:
            cost, node, path = heapq.heappop(q)
            if node == goal:
                return cost, path
            if cost > best.get(node, math.inf):
                continue
            for nxt, r in self.neighbors(node):
                if courier:
                    if r.mode == "rover" and r.distance_km > courier.rover_range_km:
                        continue
                    if r.mode == "hopper" and not courier.hopper_access:
                        continue
                    if r.mode == "orbital" and not courier.orbital_access:
                        continue
                nd = cost + self.route_days(r)
                if nd < best.get(nxt, math.inf):
                    best[nxt] = nd
                    heapq.heappush(q, (nd, nxt, path + [r]))
        return math.inf, []

    # ----------------------------
    # Economy / survival
    # ----------------------------
    def production_and_consumption(self):
        for loc in self.locations.values():
            if loc.collapsed:
                continue
            for r in RESOURCES:
                loc.stocks[r] = min(loc.capacity[r], loc.stocks[r] + loc.production[r])
                loc.stocks[r] -= loc.consumption[r]
                if loc.stocks[r] < 0:
                    loc.stocks[r] = 0

            for r in RESOURCES:
                if loc.stocks[r] <= 1:
                    loc.shortage_turns[r] += 1
                    severity = 4 if r in ("life", "food") else 2
                    # Chinese infrastructure is resilient but not magical.
                    severity = max(1, round(severity * (1.0 - 0.55 * loc.self_sufficiency)))
                    loc.stability = max(0, loc.stability - severity)
                else:
                    loc.shortage_turns[r] = max(0, loc.shortage_turns[r] - 1)

            lethal = max(loc.shortage_turns["life"], loc.shortage_turns["food"])
            if lethal >= 2:
                loss = max(5, int(loc.population * (0.0025 * lethal)))
                loc.population = max(0, loc.population - loss)
                self.world.events.append(f"{loc.name}: niedobory kosztują życie {loss} osób.")
            if loc.stability <= 15 or loc.population == 0:
                loc.collapsed = True
                self.world.events.append(f"UPADEK: {loc.name} przestaje funkcjonować jako samodzielna kolonia.")

    def need_score(self, loc: Location, cargo: str) -> int:
        # 0..100. Includes reserves and recent shortage history.
        ratio = loc.stocks[cargo] / max(1, loc.capacity[cargo])
        score = int((1.0 - ratio) * 70) + loc.shortage_turns[cargo] * 15
        if cargo in ("life", "food"):
            score += 8
        return max(0, min(100, score))

    def find_supplier(self, destination: str, cargo: str, min_surplus: int = 2):
        dst = self.locations[destination]
        candidates = []
        for name, loc in self.locations.items():
            if name == destination or loc.collapsed:
                continue
            reserve = loc.consumption[cargo] * 2 + min_surplus
            surplus = loc.stocks[cargo] - reserve
            if surplus <= 0:
                continue
            days, path = self.shortest_path(name, destination)
            if math.isinf(days):
                continue
            candidates.append((days, -surplus, name, path))
        if not candidates:
            return None
        candidates.sort()
        return candidates[0]

    def make_shipment(self, src, dst, cargo, amount, kind, sponsor, description, priority=2, passengers=0):
        s = Shipment(
            self.world.next_shipment_id, src, dst, cargo, amount, kind,
            passengers=passengers,
            value_ls=max(4, amount * (8 + priority * 4)),
            priority=priority, sponsor=sponsor, description=description,
        )
        self.world.next_shipment_id += 1
        return s

    def generate_contracts(self) -> List[Shipment]:
        contracts: List[Shipment] = []

        # 1. Genuine shortage-driven contracts.
        ranked_needs = []
        for loc in self.locations.values():
            if loc.collapsed:
                continue
            for cargo in RESOURCES:
                score = self.need_score(loc, cargo)
                if score >= 45:
                    ranked_needs.append((score, loc.name, cargo))
        ranked_needs.sort(reverse=True)

        for score, dst_name, cargo in ranked_needs[:9]:
            supplier = self.find_supplier(dst_name, cargo)
            if not supplier:
                continue
            _, _, src_name, _ = supplier
            src = self.locations[src_name]
            dst = self.locations[dst_name]
            amount = min(3 if score >= 75 else 2, max(1, src.stocks[cargo] - src.consumption[cargo] * 2))
            kind = "humanitarian" if score >= 75 and cargo in ("life", "food") else "trade"
            priority = 4 if kind == "humanitarian" else (3 if score >= 65 else 2)
            sponsor = dst.owner
            contracts.append(self.make_shipment(
                src_name, dst_name, cargo, amount, kind, sponsor,
                f"{RESOURCE_LABEL[cargo]} dla {dst_name}; zapas krytyczny={score}%", priority
            ))

        # 2. Political/military cargo creates tempting alternatives to life-saving freight.
        if self.world.war_tension >= 25 and not self.locations["Gateway Ground"].collapsed:
            contracts.append(self.make_shipment(
                "Tycho Station", "Gateway Ground", "parts", 2, "military", "US Space Navy",
                "Moduły sensorów i naprowadzania dla Space Navy", priority=3
            ))
        if self.world.war_tension >= 35 and not self.locations["Daedalus Port"].collapsed:
            contracts.append(self.make_shipment(
                "Blooming Flower", "Daedalus Port", "parts", 2, "military", "Blooming Flower Authority",
                "Elektronika obrony portu Daedalus", priority=3
            ))

        # 3. Passenger / evacuation missions.
        endangered = [l for l in self.locations.values() if not l.collapsed and l.stability < 45 and l.population > 300]
        if endangered:
            src = min(endangered, key=lambda l: l.stability)
            safe = max((l for l in self.locations.values() if not l.collapsed and l.stability > 75 and l.name != src.name),
                       key=lambda l: l.stability, default=None)
            if safe:
                contracts.append(self.make_shipment(
                    src.name, safe.name, "life", 0, "passenger", src.owner,
                    f"Ewakuacja cywilów z {src.name}", priority=4, passengers=12
                ))

        # 4. High-margin nonessential work. This is what makes a profit-first courier
        # genuinely different from a humanitarian one.
        if not self.locations["Luna Grand"].collapsed:
            if self.locations["InPost Central"].stocks["food"] >= 2:
                c = self.make_shipment(
                    "InPost Central", "Luna Grand", "food", 1, "trade", "Luna Grand Consortium",
                    "Luksusowa żywność i alkohol syntetyczny dla Luna Grand", priority=1
                )
                c.value_ls = 140
                contracts.append(c)
            if self.locations["Copernicus Freeport"].stocks["parts"] >= 2:
                c = self.make_shipment(
                    "Copernicus Freeport", "Luna Grand", "parts", 1, "trade", "Luna Grand Consortium",
                    "Części do prywatnych apartamentów i systemów rekreacyjnych", priority=1
                )
                c.value_ls = 125
                contracts.append(c)

        # 5. The hidden Model occasionally leaks an untraceable contract after midgame.
        if self.world.turn >= 5 and self.rng.random() < 0.35:
            contracts.append(self.make_shipment(
                "Daedalus Port", "Aristarchus Beacon", "parts", 1, "trade", "UNKNOWN",
                "Zaplombowany moduł chłodzenia; odbiorca ukryty za martwą skrzynką", priority=3
            ))

        # Deduplicate identical source/destination/cargo/kind pairs.
        unique = {}
        for c in contracts:
            key = (c.source, c.destination, c.cargo, c.kind, c.sponsor)
            if key not in unique or c.priority > unique[key].priority:
                unique[key] = c
        return list(unique.values())

    # ----------------------------
    # Shipment effects
    # ----------------------------
    def can_execute(self, s: Shipment) -> bool:
        if self.locations[s.source].collapsed or self.locations[s.destination].collapsed:
            return False
        if s.kind != "passenger" and self.locations[s.source].stocks[s.cargo] < s.amount:
            return False
        days, _ = self.shortest_path(s.source, s.destination)
        return not math.isinf(days)

    def shipment_risk(self, s: Shipment, courier: Optional[Courier] = None) -> float:
        _, path = self.shortest_path(s.source, s.destination, courier=courier)
        if not path:
            return 0.99
        survival = 1.0
        for r in path:
            survival *= (1.0 - self.route_risk(r))
        base = 1.0 - survival
        # InPost satellites and trust reduce practical risk.
        base *= (1.12 - 0.035 * self.inpost.satellites)
        return max(0.01, min(0.80, base))

    def execute_shipment(self, s: Shipment, player: bool = False, force_success: bool = False) -> bool:
        if not self.can_execute(s):
            return False
        src = self.locations[s.source]
        dst = self.locations[s.destination]
        risk = self.shipment_risk(s, self.courier if player else None)

        if s.kind != "passenger":
            src.stocks[s.cargo] -= s.amount

        success = force_success or self.rng.random() > risk
        actor = self.courier.name if player else "sieć InPost"

        if success:
            if s.kind == "passenger":
                moved = min(s.passengers, max(0, src.population - 50))
                src.population -= moved
                dst.population += moved
                src.stability = min(100, src.stability + 2)
                self.world.events.append(f"{actor}: ewakuowano {moved} osób {s.source} → {s.destination}.")
            else:
                dst.stocks[s.cargo] = min(dst.capacity[s.cargo], dst.stocks[s.cargo] + s.amount)
                self.world.events.append(
                    f"{actor}: dostarczono {s.amount} {s.cargo.upper()} {s.source} → {s.destination}."
                )

            # Economic impact: Lunar Dollar clearing through InPost.
            self.inpost.liquidity += max(1, s.value_ls // 12)
            self.world.trade_flow = min(100, self.world.trade_flow + (3 if player else 1))
            self.factions[s.sponsor].trust_inpost = min(100, self.factions.get(s.sponsor, self.factions["InPost Lunar"]).trust_inpost + 2) if s.sponsor in self.factions else 0

            # Social/political impact by cargo type.
            if s.kind == "humanitarian":
                dst.stability = min(100, dst.stability + 8)
                self.inpost.trust = min(100, self.inpost.trust + 3)
                self.world.war_tension = max(0, self.world.war_tension - (2 if player else 0))
            elif s.kind == "passenger":
                self.inpost.trust = min(100, self.inpost.trust + 4)
                self.world.war_tension = max(0, self.world.war_tension - (1 if player else 0))
            elif s.kind == "military":
                faction = self.factions[s.sponsor]
                faction.power = min(10, faction.power + 1)
                self.world.war_tension = min(100, self.world.war_tension + 5)
                self.inpost.neutrality = max(0, self.inpost.neutrality - (4 if player else 1))

            if s.sponsor == "UNKNOWN":
                self.world.ai_compute += 1
                if player:
                    self.world.hidden_model_discovered = True
                    self.world.events.append("Siwy-04 zauważa, że adres odbiorcy nie istnieje w publicznej sieci.")

            if player:
                self.courier.completed += 1
                self.courier.credits += s.value_ls
                self.courier.reputation = min(100, self.courier.reputation + 2)
            return True

        # Failed/intercepted shipment.
        self.world.events.append(f"ATAK/USTERKA: transport {s.sid} {s.source} → {s.destination} nie dotarł.")
        self.world.trade_flow = max(0, self.world.trade_flow - 3)
        if self.rng.random() < 0.35:
            self.world.pirate_strength = min(10, self.world.pirate_strength + 1)
        if player:
            self.courier.reputation = max(0, self.courier.reputation - 3)
        return False

    def reroute_player_shipment(self, original: Shipment, new_destination: str) -> Optional[Shipment]:
        if new_destination not in self.locations or new_destination == original.source:
            return None
        redirected = copy.copy(original)
        redirected.sid = self.world.next_shipment_id
        self.world.next_shipment_id += 1
        redirected.destination = new_destination
        redirected.description = f"SAMOWOLNE PRZEKIEROWANIE: {original.description}"
        redirected.sponsor = self.locations[new_destination].owner
        # Moral intervention: good for destination, bad for original client and corporate discipline.
        self.inpost.neutrality = max(0, self.inpost.neutrality - 2)
        self.courier.reputation = max(0, self.courier.reputation - 2)
        return redirected

    # ----------------------------
    # Autonomous world
    # ----------------------------
    def npc_logistics(self, contracts: List[Shipment], excluded_id: Optional[int] = None):
        # NPC network prioritizes profitable/high-priority work but has hard capacity.
        pool = [c for c in contracts if c.sid != excluded_id and self.can_execute(c)]
        pool.sort(key=lambda c: (c.priority, c.value_ls), reverse=True)
        delivered = 0
        for c in pool:
            if delivered >= self.inpost.network_capacity:
                break
            if self.execute_shipment(c, player=False):
                delivered += 1
        # Not enough couriers/vehicles to clear all shortages is intentional.
        if len(pool) > self.inpost.network_capacity:
            self.world.events.append(
                f"Sieć przeciążona: {len(pool)-self.inpost.network_capacity} zleceń nie obsłużono w tej turze."
            )

    def piracy_and_infrastructure(self):
        # Piracy targets chokepoints rather than random abstract trade.
        vulnerable = [r for r in self.routes if r.active and r.mode in ("rover", "hopper")]
        if vulnerable and self.rng.random() < 0.18 + 0.035 * self.world.pirate_strength:
            r = max(self.rng.sample(vulnerable, min(4, len(vulnerable))), key=self.route_risk)
            self.world.events.append(f"Piraci operują przy {r.a} ↔ {r.b}.")
            if r.mode == "rover" and self.rng.random() < 0.45:
                r.condition = max(20, r.condition - self.rng.randint(5, 14))
            if self.rng.random() < 0.12:
                r.active = False
                self.world.events.append(f"Trasa {r.a} ↔ {r.b} czasowo zamknięta.")

        # InPost repairs only a little: another capacity choice embedded in the world.
        damaged = [r for r in self.routes if r.mode == "rover" and r.active and r.condition < 75]
        if damaged and self.inpost.liquidity > 20:
            r = min(damaged, key=lambda x: x.condition)
            r.condition = min(100, r.condition + 8)
            self.inpost.liquidity -= 3
            self.world.events.append(f"InPost naprawia {r.a} ↔ {r.b}; stan {r.condition}%.")

        # Closed routes may reopen after local work.
        for r in self.routes:
            if not r.active and self.rng.random() < 0.22:
                r.active = True
                self.world.events.append(f"Ponownie otwarto {r.a} ↔ {r.b}.")

    def satellite_phase(self):
        if self.rng.random() < 0.08 and self.inpost.satellites > 3:
            self.inpost.satellites -= 1
            self.world.events.append("Utracono satelitę InPost/relay. Pokrycie sieci spada.")
        elif self.rng.random() < 0.06 and self.inpost.satellites < self.inpost.max_satellites and self.inpost.liquidity > 30:
            self.inpost.satellites += 1
            self.inpost.liquidity -= 6
            self.world.events.append("InPost przywraca satelitę przekaźnikowego.")

    def politics_phase(self):
        china = self.factions["Blooming Flower Authority"]
        # The geopolitical clock keeps ticking even when the courier behaves well.
        # Humanitarian work can slow escalation, not erase the strategic rivalry.
        self.world.war_tension = min(100, self.world.war_tension + 1)
        navy = self.factions["US Space Navy"]
        miners = self.factions["Silesian Union"]

        # Self-sufficient China grows in relative power when the rest fragments.
        china_cluster = [self.locations[n] for n in ("Blooming Flower", "Daedalus Port", "Chang'e Relay")]
        if all(l.stability >= 70 for l in china_cluster) and self.world.network < 65:
            china.power = min(10, china.power + 1)
            self.world.war_tension = min(100, self.world.war_tension + 2)
            self.world.events.append("Blooming Flower wykorzystuje chaos i zwiększa autonomię strategiczną.")

        if self.locations["Silesia"].stability < 45:
            miners.hostility = min(100, miners.hostility + 7)
            self.world.war_tension = min(100, self.world.war_tension + 2)
            self.world.events.append("Silesia grozi blokadą eksportu części.")

        if china.power >= navy.power:
            navy.hostility = min(100, navy.hostility + 3)
            self.world.war_tension = min(100, self.world.war_tension + 2)

        # Hidden Model grows slowly without needing a visible city.
        if self.rng.random() < 0.18:
            self.world.ai_compute += 1

    def recompute_world_metrics(self):
        active_routes = sum(1 for r in self.routes if r.active)
        open_ratio = active_routes / len(self.routes)
        stable = [l for l in self.locations.values() if not l.collapsed]
        avg_stability = sum(l.stability for l in stable) / max(1, len(stable))
        sat = self.inpost.satellites / self.inpost.max_satellites
        self.world.network = int(max(0, min(100, 45 * open_ratio + 30 * sat + 25 * avg_stability / 100)))

        # Trade grows with network and stability, but war/piracy/shortages suppress it.
        shortages = sum(1 for l in stable for r in RESOURCES if l.stocks[r] <= 1)
        target = self.world.network - shortages * 2 - self.world.war_tension // 5 - self.world.pirate_strength
        self.world.trade_flow = int(max(0, min(100, 0.7 * self.world.trade_flow + 0.3 * target)))

        self.inpost.surface_network = int(sum(
            ({"highway": 100, "track": 55, "wilderness": 15}.get(r.road_class, 0) * r.condition / 100)
            for r in self.routes if r.mode == "rover" and r.active
        ) / max(1, sum(1 for r in self.routes if r.mode == "rover")))

    # ----------------------------
    # Player policy / turn loop
    # ----------------------------
    def eligible_player_contracts(self, contracts: List[Shipment], max_days: float = 3.0) -> List[Shipment]:
        out = []
        for c in contracts:
            # Player can reposition to pickup if total travel fits one turn.
            d1, _ = self.shortest_path(self.courier.location, c.source, self.courier)
            d2, _ = self.shortest_path(c.source, c.destination, self.courier)
            if d1 + d2 <= max_days and self.can_execute(c):
                out.append(c)
        return out

    def apply_player_choice(self, shipment: Optional[Shipment], action: str = "deliver", reroute_to: Optional[str] = None):
        if shipment is None or action == "skip":
            self.world.events.append("Siwy-04 nie bierze strategicznego kursu w tej turze.")
            return None

        # Reposition to pickup is abstracted as part of the 3-day turn.
        if action == "deliver":
            ok = self.execute_shipment(shipment, player=True)
            if ok:
                self.courier.location = shipment.destination
            return ok

        if action == "reroute" and reroute_to:
            redirected = self.reroute_player_shipment(shipment, reroute_to)
            if redirected and self.can_execute(redirected):
                # Original client loses trust.
                if shipment.sponsor in self.factions:
                    self.factions[shipment.sponsor].trust_inpost = max(
                        0, self.factions[shipment.sponsor].trust_inpost - 7
                    )
                ok = self.execute_shipment(redirected, player=True)
                if ok:
                    self.courier.location = redirected.destination
                return ok
            return False

        if action == "pirates":
            # Sell cargo to pirates: immediate personal money, systemic damage.
            if shipment.kind != "passenger" and self.locations[shipment.source].stocks[shipment.cargo] >= shipment.amount:
                self.locations[shipment.source].stocks[shipment.cargo] -= shipment.amount
                self.courier.credits += shipment.value_ls * 2
                self.world.pirate_strength = min(10, self.world.pirate_strength + 2)
                self.inpost.trust = max(0, self.inpost.trust - 8)
                self.inpost.neutrality = max(0, self.inpost.neutrality - 5)
                self.world.trade_flow = max(0, self.world.trade_flow - 6)
                self.world.events.append("Siwy-04 sprzedaje ładunek Bractwu Wolnych Kraterów.")
                return True
            return False
        return False

    def choose_by_policy(self, contracts: List[Shipment], policy: str) -> Optional[Shipment]:
        eligible = self.eligible_player_contracts(contracts)
        if not eligible:
            return None
        if policy == "skip":
            return None
        if policy == "humanitarian":
            return max(eligible, key=lambda c: (
                c.kind in ("humanitarian", "passenger"),
                self.need_score(self.locations[c.destination], c.cargo) if c.kind != "passenger" else 100,
                c.priority
            ))
        if policy == "profit":
            return max(eligible, key=lambda c: c.value_ls)
        if policy == "military_navy":
            navy = [c for c in eligible if c.sponsor == "US Space Navy"]
            return max(navy, key=lambda c: c.value_ls) if navy else max(eligible, key=lambda c: c.value_ls)
        if policy == "network":
            # Save the most unstable destination, regardless of sponsor.
            return min(eligible, key=lambda c: self.locations[c.destination].stability)
        return max(eligible, key=lambda c: (c.priority, c.value_ls))

    def run_turn(self, player_policy: str = "humanitarian", interactive_choice: Optional[Callable] = None):
        self.world.turn += 1
        self.world.events = []
        self.world.events.append(f"--- TURA {self.world.turn} / dzień {1+(self.world.turn-1)*3}-{self.world.turn*3} ---")

        self.production_and_consumption()
        contracts = self.generate_contracts()
        eligible = self.eligible_player_contracts(contracts)

        chosen = None
        action = "deliver"
        reroute_to = None
        if interactive_choice:
            chosen, action, reroute_to = interactive_choice(self, eligible)
        else:
            chosen = self.choose_by_policy(contracts, player_policy)

        chosen_id = chosen.sid if chosen else None
        self.apply_player_choice(chosen, action, reroute_to)
        self.npc_logistics(contracts, excluded_id=chosen_id)
        self.piracy_and_infrastructure()
        self.satellite_phase()
        self.politics_phase()
        self.recompute_world_metrics()

        snapshot = self.snapshot(chosen)
        self.world.history.append(snapshot)
        return snapshot

    def snapshot(self, chosen: Optional[Shipment] = None):
        return {
            "turn": self.world.turn,
            "network": self.world.network,
            "trade": self.world.trade_flow,
            "war": self.world.war_tension,
            "pirates": self.world.pirate_strength,
            "satellites": self.inpost.satellites,
            "inpost_trust": self.inpost.trust,
            "neutrality": self.inpost.neutrality,
            "liquidity": self.inpost.liquidity,
            "courier_location": self.courier.location,
            "chosen": chosen.description if chosen else None,
            "collapsed": [l.name for l in self.locations.values() if l.collapsed],
            "stability": {l.name: l.stability for l in self.locations.values()},
            "population": {l.name: l.population for l in self.locations.values()},
            "events": list(self.world.events),
        }

    def campaign_score(self):
        alive_locations = [l for l in self.locations.values() if not l.collapsed]
        population = sum(l.population for l in alive_locations)
        avg_stability = sum(l.stability for l in alive_locations) / max(1, len(alive_locations))
        return {
            "surviving_colonies": len(alive_locations),
            "population": population,
            "avg_stability": round(avg_stability, 1),
            "network": self.world.network,
            "trade": self.world.trade_flow,
            "war_tension": self.world.war_tension,
            "pirate_strength": self.world.pirate_strength,
            "inpost_trust": self.inpost.trust,
            "neutrality": self.inpost.neutrality,
            "liquidity": self.inpost.liquidity,
            "courier_credits": self.courier.credits,
            "courier_completed": self.courier.completed,
            "model_discovered": self.world.hidden_model_discovered,
        }

    def run_campaign(self, turns=12, policy="humanitarian", verbose=True):
        for _ in range(turns):
            snap = self.run_turn(player_policy=policy)
            if verbose:
                print_turn(self, snap)
        return self.campaign_score()


# ----------------------------
# CLI / comparison
# ----------------------------

def contract_line(game: Game, c: Shipment) -> str:
    days1, _ = game.shortest_path(game.courier.location, c.source, game.courier)
    days2, _ = game.shortest_path(c.source, c.destination, game.courier)
    risk = game.shipment_risk(c, game.courier)
    cargo = f"{c.amount} {c.cargo.upper()}" if c.kind != "passenger" else f"{c.passengers} pasażerów"
    return (
        f"#{c.sid} {c.kind.upper():12s} {c.source} -> {c.destination} | {cargo} | "
        f"~{days1+days2:.1f} d | ryzyko {risk*100:.0f}% | {c.value_ls} L$ | {c.description}"
    )


def best_reroute_destination(game: Game, shipment: Shipment) -> Optional[str]:
    if shipment.kind == "passenger":
        return None
    candidates = []
    for loc in game.locations.values():
        if loc.name in (shipment.source, shipment.destination) or loc.collapsed:
            continue
        d1, _ = game.shortest_path(game.courier.location, shipment.source, game.courier)
        d2, _ = game.shortest_path(shipment.source, loc.name, game.courier)
        if d1 + d2 > 3.0:
            continue
        need = game.need_score(loc, shipment.cargo)
        if need >= 45:
            candidates.append((need, -loc.stability, loc.name))
    return max(candidates)[2] if candidates else None


def interactive_choice(game: Game, contracts: List[Shipment]):
    print(f"\nSiwy-04: {game.courier.location}. Dostępne strategiczne kursy:")
    if not contracts:
        print("Brak kursów możliwych do wykonania w tej turze.")
        return None, "skip", None
    for i, c in enumerate(contracts, 1):
        print(f"  {i}. {contract_line(game, c)}")
    print("  0. Pomiń kurs")
    raw = input("Wybór zlecenia: ").strip()
    try:
        idx = int(raw)
    except ValueError:
        idx = 0
    if idx <= 0 or idx > len(contracts):
        return None, "skip", None

    c = contracts[idx-1]
    alt = best_reroute_destination(game, c)
    print("\nDecyzja:")
    print("  1. Dostarcz zgodnie z listem przewozowym")
    if alt:
        need = game.need_score(game.locations[alt], c.cargo)
        print(f"  2. Samowolnie przekieruj do {alt} (potrzeba {need}/100)")
    if c.kind != "passenger":
        print("  3. Sprzedaj ładunek Bractwu Wolnych Kraterów")
    print("  0. Zrezygnuj")
    action = input("Decyzja: ").strip()
    if action == "1":
        return c, "deliver", None
    if action == "2" and alt:
        return c, "reroute", alt
    if action == "3" and c.kind != "passenger":
        return c, "pirates", None
    return None, "skip", None


def print_turn(game: Game, snap: dict):
    print("\n" + "=" * 88)
    print(
        f"TURA {snap['turn']:02d} | sieć {snap['network']:3d}% | handel {snap['trade']:3d}% | "
        f"wojna {snap['war']:3d}% | piraci {snap['pirates']} | sat {snap['satellites']} | "
        f"InPost trust {snap['inpost_trust']} / neutralność {snap['neutrality']}"
    )
    if snap["chosen"]:
        print("KURS GRACZA:", snap["chosen"])
    for e in snap["events"]:
        print(" -", e)


def compare_policies(seed=42):
    policies = ["skip", "humanitarian", "network", "profit", "military_navy"]
    rows = []
    for p in policies:
        g = Game(seed=seed)
        score = g.run_campaign(12, policy=p, verbose=False)
        rows.append((p, score))

    print("\nPORÓWNANIE: ten sam świat początkowy, inne decyzje Siwego-04")
    print("-" * 118)
    print(f"{'polityka':16s} {'kolonie':>7s} {'populacja':>10s} {'stabil.':>8s} {'sieć':>6s} {'handel':>7s} {'wojna':>6s} {'piraci':>7s} {'trust':>6s} {'neutral.':>8s} {'L$ kuriera':>10s}")
    for p, s in rows:
        print(
            f"{p:16s} {s['surviving_colonies']:7d} {s['population']:10d} {s['avg_stability']:8.1f} "
            f"{s['network']:6d} {s['trade']:7d} {s['war_tension']:6d} {s['pirate_strength']:7d} "
            f"{s['inpost_trust']:6d} {s['neutrality']:8d} {s['courier_credits']:10d}"
        )


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Lunar InPost strategy prototype v2")
    parser.add_argument("--interactive", action="store_true", help="12 tur z ręcznym wyborem kursów")
    parser.add_argument("--policy", choices=["skip", "humanitarian", "network", "profit", "military_navy"], default="humanitarian")
    parser.add_argument("--compare", action="store_true", help="porównaj skutki różnych polityk gracza")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if args.compare:
        compare_policies(args.seed)
        return

    game = Game(seed=args.seed)
    if args.interactive:
        for _ in range(12):
            snap = game.run_turn(interactive_choice=interactive_choice)
            print_turn(game, snap)
        print("\nKONIEC KAMPANII:", game.campaign_score())
    else:
        score = game.run_campaign(12, policy=args.policy, verbose=True)
        print("\nKONIEC KAMPANII:")
        for k, v in score.items():
            print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
