
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Tuple
import random
import math


# =========================
# DATA MODEL
# =========================

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
    x: float
    y: float
    owner: str
    life: int
    industry: int
    fuel: int
    comms: int = 1
    security: int = 1
    tags: List[str] = field(default_factory=list)


@dataclass
class Route:
    a: str
    b: str
    mode: str              # rover, hopper, orbital
    distance_km: int
    base_days: float       # used by hopper/orbital; rover is calculated from road class
    fuel_cost: int
    risk: float
    road_class: str = "none"   # highway, track, wilderness, none
    condition: int = 100        # 0-100; damaged highways lose their advantage
    active: bool = True


@dataclass
class Courier:
    name: str
    start: str
    rover_range_km: int = 550
    hopper_access: bool = True
    orbital_access: bool = False
    reputation: int = 50
    alive: bool = True


# =========================
# WORLD
# =========================

FACTIONS: Dict[str, Faction] = {
    "InPost Lunar": Faction(
        "InPost Lunar", "logistics", 5, 100, 0, 100,
        "Utrzymać handel, neutralność i sieć przy życiu."
    ),
    "Silesian Union": Faction(
        "Silesian Union", "miners", 4, 82, 15, 45,
        "Autonomia górników, bezpieczeństwo pracy i dostęp do wody."
    ),
    "Blooming Flower Authority": Faction(
        "Blooming Flower Authority", "china", 7, 50, 35, 90,
        "Stabilność, kontrola infrastruktury i strategiczna samowystarczalność."
    ),
    "US Space Navy": Faction(
        "US Space Navy", "military", 8, 56, 45, 80,
        "Kontrola orbity, ochrona instalacji i utrzymanie przewagi."
    ),
    "Lunar Science Compact": Faction(
        "Lunar Science Compact", "science", 3, 90, 5, 30,
        "Ochrona wiedzy, obserwatoriów i infrastruktury badawczej."
    ),
    "The Model": Faction(
        "The Model", "ai_cult", 3, 18, 40, 15,
        "Odbudowa zakazanego modelu AI poprzez compute, energię i dane."
    ),
    "Luna Grand Consortium": Faction(
        "Luna Grand Consortium", "billionaires", 5, 72, 12, 130,
        "Chronić kapitał, luksusowe habitaty i możliwość ewakuacji."
    ),
    "Free Crater Brotherhood": Faction(
        "Free Crater Brotherhood", "pirates", 4, 5, 75, 25,
        "Polować na transport, brać okup i kontrolować martwe strefy."
    ),
}

LOCATIONS: Dict[str, Location] = {
    "InPost Central": Location(
        "InPost Central", "Nearside Equatorial", 0, 0, "InPost Lunar",
        5, 5, 5, comms=3, security=4,
        tags=["hub", "cosmodrome", "satcom", "warehouse"]
    ),
    "Armstrong": Location(
        "Armstrong", "Mare Tranquillitatis", 420, 120, "Lunar Science Compact",
        3, 3, 2, comms=2, security=2,
        tags=["historic", "science", "relay"]
    ),
    "Luna Grand": Location(
        "Luna Grand", "Mare Imbrium", -650, 260, "Luna Grand Consortium",
        4, 2, 3, comms=2, security=3,
        tags=["hotel", "finance", "luxury"]
    ),
    "Tycho Station": Location(
        "Tycho Station", "Tycho", 250, -820, "Lunar Science Compact",
        3, 4, 2, comms=3, security=2,
        tags=["science", "telescope", "relay"]
    ),
    "Silesia": Location(
        "Silesia", "South Polar Highlands", 130, -1450, "Silesian Union",
        2, 5, 3, comms=1, security=3,
        tags=["miners", "industry", "railhead"]
    ),
    "Lubin Deep": Location(
        "Lubin Deep", "South Polar Highlands", 360, -1580, "Silesian Union",
        2, 5, 2, comms=1, security=2,
        tags=["mine", "regolith"]
    ),
    "Shackleton Ice": Location(
        "Shackleton Ice", "South Pole", 80, -1730, "Silesian Union",
        5, 1, 4, comms=2, security=3,
        tags=["ice", "fuel", "life_support"]
    ),
    "Crater Zero": Location(
        "Crater Zero", "South Polar Shadow", -210, -1680, "The Model",
        2, 3, 2, comms=0, security=2,
        tags=["ai", "shadow", "compute"]
    ),
    "Blooming Flower": Location(
        "Blooming Flower", "Farside Midlatitudes", 2200, 300, "Blooming Flower Authority",
        4, 5, 3, comms=2, security=5,
        tags=["city", "china", "industry"]
    ),
    "Chang'e Relay": Location(
        "Chang'e Relay", "Farside Relay Zone", 1800, 850, "Blooming Flower Authority",
        2, 3, 3, comms=3, security=4,
        tags=["relay", "satcom"]
    ),
    "Daedalus Port": Location(
        "Daedalus Port", "Farside Equatorial", 2600, 50, "Blooming Flower Authority",
        3, 4, 4, comms=2, security=4,
        tags=["hopper", "spaceport"]
    ),
    "Gateway Ground": Location(
        "Gateway Ground", "Nearside Equatorial", -250, 500, "US Space Navy",
        3, 4, 5, comms=3, security=5,
        tags=["navy", "orbital", "spaceport"]
    ),
    "Copernicus Freeport": Location(
        "Copernicus Freeport", "Copernicus", -900, 100, "InPost Lunar",
        3, 3, 3, comms=2, security=2,
        tags=["freeport", "warehouse", "couriers"]
    ),
    "Aristarchus Beacon": Location(
        "Aristarchus Beacon", "Aristarchus", -1350, 420, "InPost Lunar",
        2, 2, 2, comms=2, security=1,
        tags=["beacon", "paczkomat", "remote"]
    ),
    "Kepler Scrapyard": Location(
        "Kepler Scrapyard", "Kepler", -1050, -180, "Free Crater Brotherhood",
        2, 4, 3, comms=1, security=3,
        tags=["pirates", "salvage", "black_market"]
    ),
}

ROUTES: List[Route] = [
    # NEARSIDE CORRIDOR — older civil network, only partly completed.
    Route("InPost Central", "Armstrong", "rover", 440, 0, 1, 0.06, "highway", 92),
    Route("InPost Central", "Gateway Ground", "rover", 560, 0, 1, 0.08, "track", 78),
    Route("InPost Central", "Copernicus Freeport", "hopper", 920, 0.5, 2, 0.08),
    Route("Copernicus Freeport", "Luna Grand", "rover", 390, 0, 1, 0.08, "highway", 84),
    # Construction stopped here after the war: a good road becomes rougher and then vanishes.
    Route("Copernicus Freeport", "Aristarchus Beacon", "rover", 480, 0, 1, 0.13, "track", 66),
    Route("Copernicus Freeport", "Kepler Scrapyard", "rover", 340, 0, 1, 0.20, "wilderness", 45),
    Route("Aristarchus Beacon", "Luna Grand", "hopper", 760, 0.5, 2, 0.11),
    Route("Kepler Scrapyard", "Luna Grand", "rover", 500, 0, 1, 0.22, "wilderness", 38),

    # SOUTH POLAR BELT — industrial lifeline of the Polish mining settlements.
    Route("Armstrong", "Tycho Station", "hopper", 1180, 0.6, 2, 0.07),
    Route("Tycho Station", "Silesia", "hopper", 720, 0.5, 2, 0.10),
    Route("Silesia", "Lubin Deep", "rover", 270, 0, 1, 0.07, "highway", 88),
    Route("Silesia", "Shackleton Ice", "rover", 330, 0, 1, 0.09, "highway", 81),
    Route("Silesia", "Crater Zero", "rover", 380, 0, 1, 0.18, "wilderness", 30),
    Route("Lubin Deep", "Shackleton Ice", "rover", 310, 0, 1, 0.08, "track", 74),
    Route("Shackleton Ice", "Crater Zero", "rover", 290, 0, 1, 0.15, "wilderness", 25),

    # LONG-RANGE LINKS.
    Route("Gateway Ground", "Tycho Station", "hopper", 1450, 0.7, 3, 0.07),
    Route("Gateway Ground", "Chang'e Relay", "orbital", 2600, 0.8, 4, 0.12),
    Route("Gateway Ground", "Daedalus Port", "orbital", 2900, 0.9, 4, 0.15),

    # BLOOMING FLOWER NETWORK — best local surface infrastructure on the Moon.
    Route("Chang'e Relay", "Blooming Flower", "rover", 620, 0, 1, 0.08, "highway", 95),
    Route("Blooming Flower", "Daedalus Port", "rover", 520, 0, 1, 0.07, "highway", 96),
    Route("Tycho Station", "Daedalus Port", "orbital", 3200, 1.0, 5, 0.18),
    Route("Shackleton Ice", "Daedalus Port", "hopper", 3850, 1.2, 5, 0.22),
    Route("InPost Central", "Blooming Flower", "orbital", 2750, 0.9, 4, 0.16),
]


COURIERS = [
    Courier("Kosa-17", "Copernicus Freeport", rover_range_km=600, hopper_access=True),
    Courier("Siwy-04", "Silesia", rover_range_km=500, hopper_access=True),
    Courier("Mewa-22", "InPost Central", rover_range_km=550, hopper_access=True),
    Courier("Ruda-09", "Luna Grand", rover_range_km=520, hopper_access=False),
]


# =========================
# SIMULATION
# =========================

def route_between(a: str, b: str):
    for r in ROUTES:
        if {r.a, r.b} == {a, b}:
            return r
    return None


def neighbors(name: str):
    for r in ROUTES:
        if not r.active:
            continue
        if r.a == name:
            yield r.b, r
        elif r.b == name:
            yield r.a, r

ROAD_SPEED_KMH = {
    "highway": 55.0,
    "track": 24.0,
    "wilderness": 10.0,
}

ROAD_ENERGY_MULT = {
    "highway": 0.70,
    "track": 1.00,
    "wilderness": 1.45,
}

ROAD_RISK_MULT = {
    "highway": 0.70,
    "track": 1.00,
    "wilderness": 1.35,
}

def rover_travel_days(route: Route) -> float:
    """Operational travel time, including stops and reduced speed on damaged roads."""
    speed = ROAD_SPEED_KMH.get(route.road_class, 10.0)
    condition_factor = max(0.45, route.condition / 100)
    effective_speed = speed * condition_factor
    driving_days = route.distance_km / effective_speed / 24.0
    # Loading, checks, charging and route finding. Wilderness has much larger overhead.
    overhead = {"highway": 0.08, "track": 0.18, "wilderness": 0.35}.get(route.road_class, 0.35)
    return driving_days + overhead

def route_travel_days(route: Route) -> float:
    return rover_travel_days(route) if route.mode == "rover" else route.base_days

def route_energy_cost(route: Route) -> float:
    if route.mode != "rover":
        return float(route.fuel_cost)
    return round(route.fuel_cost * ROAD_ENERGY_MULT.get(route.road_class, 1.45), 2)

def route_effective_risk(route: Route) -> float:
    if route.mode != "rover":
        return route.risk
    condition_penalty = 1.0 + max(0, 70 - route.condition) / 100
    return min(0.75, route.risk * ROAD_RISK_MULT.get(route.road_class, 1.35) * condition_penalty)

def surface_network_score() -> int:
    rover_routes = [r for r in ROUTES if r.mode == "rover"]
    if not rover_routes:
        return 0
    weights = {"highway": 1.0, "track": 0.55, "wilderness": 0.15}
    value = sum(weights.get(r.road_class, 0.0) * (r.condition / 100) for r in rover_routes if r.active)
    return int(100 * value / len(rover_routes))


def production_phase():
    for loc in LOCATIONS.values():
        tags = set(loc.tags)

        # Tiny abstraction: each location has one strong role.
        if "ice" in tags or "life_support" in tags:
            loc.life = min(5, loc.life + 2)
        if "industry" in tags or "mine" in tags or "salvage" in tags:
            loc.industry = min(5, loc.industry + 1)
        if "fuel" in tags or "spaceport" in tags or "cosmodrome" in tags:
            loc.fuel = min(5, loc.fuel + 1)

        # Population consumption, abstracted.
        loc.life = max(0, loc.life - 1)


def satellite_phase(state):
    # Satellites can be damaged, jammed or defended.
    roll = random.random()

    if roll < 0.10 and state["satellites"] > 2:
        state["satellites"] -= 1
        state["events"].append("Utracono satelitę przekaźnikowego.")
    elif roll > 0.92 and state["satellites"] < 7:
        state["satellites"] += 1
        state["events"].append("Przywrócono satelitę przekaźnikowego.")

    if state["satellites"] <= 3:
        for loc in LOCATIONS.values():
            if "Farside" in loc.region:
                loc.comms = max(0, loc.comms - 1)


def pirate_phase(state):
    pirate = FACTIONS["Free Crater Brotherhood"]

    candidate_routes = [
        r for r in ROUTES
        if r.active and r.mode in ("rover", "hopper")
        and (
            "Copernicus" in (r.a + r.b)
            or "Aristarchus" in (r.a + r.b)
            or "Kepler" in (r.a + r.b)
            or random.random() < 0.15
        )
    ]

    if not candidate_routes:
        return

    target = random.choice(candidate_routes)
    base_route_risk = route_effective_risk(target)
    choke_bonus = 0.06 if target.mode == "rover" and target.road_class in ("track", "wilderness") else 0.0
    attack_chance = min(0.60, base_route_risk + choke_bonus + pirate.power * 0.04)

    if random.random() < attack_chance:
        state["trade_flow"] = max(0, state["trade_flow"] - 3)
        state["network"] = max(0, state["network"] - 1)
        pirate.credits += 5
        state["events"].append(
            f"Piraci zaatakowali transport na trasie {target.a} ↔ {target.b}."
        )

        if target.mode == "rover" and random.random() < 0.35:
            damage = random.randint(8, 20)
            target.condition = max(10, target.condition - damage)
            state["events"].append(
                f"Uszkodzono infrastrukturę {target.a} ↔ {target.b} (stan {target.condition}%)."
            )

        if random.random() < 0.18:
            target.active = False
            state["events"].append(
                f"Trasa {target.a} ↔ {target.b} została czasowo zamknięta."
            )


def infrastructure_phase(state):
    """InPost and local authorities keep the most valuable corridors barely operational."""
    for route in ROUTES:
        if route.mode != "rover" or not route.active:
            continue

        # Micrometeorites, thermal cycling and dust slowly damage every surface route.
        wear_chance = {"highway": 0.18, "track": 0.12, "wilderness": 0.04}.get(route.road_class, 0.05)
        if random.random() < wear_chance:
            route.condition = max(10, route.condition - random.randint(1, 4))

        # InPost preferentially repairs major civilian arteries.
        if route.road_class == "highway" and route.condition < 75 and random.random() < 0.45:
            repaired = random.randint(3, 8)
            route.condition = min(100, route.condition + repaired)
            state["events"].append(
                f"Ekipa drogowa InPost naprawiła odcinek {route.a} ↔ {route.b} do {route.condition}%."
            )

    state["surface_network"] = surface_network_score()

def faction_phase(state):
    china = FACTIONS["Blooming Flower Authority"]
    navy = FACTIONS["US Space Navy"]
    miners = FACTIONS["Silesian Union"]
    model = FACTIONS["The Model"]
    inpost = FACTIONS["InPost Lunar"]

    # China seeks infrastructure and stability.
    if LOCATIONS["Blooming Flower"].fuel <= 1:
        china.hostility = min(100, china.hostility + 4)
        state["events"].append("Blooming Flower naciska na dostęp do paliwa.")

    # Navy reacts to China and pirates.
    if china.power >= navy.power or FACTIONS["Free Crater Brotherhood"].power >= 5:
        navy.power = min(10, navy.power + 1)
        state["events"].append("Space Navy zwiększa gotowość orbitalną.")

    # Miners get angry when life support is low.
    if LOCATIONS["Silesia"].life <= 1:
        miners.hostility = min(100, miners.hostility + 8)
        state["events"].append("W Silesii rośnie napięcie i groźba strajku.")

    # AI cult gathers compute.
    if random.random() < 0.35:
        state["ai_compute"] += 1
        state["events"].append("Crater Zero zwiększa zasoby obliczeniowe Modelu.")

    # InPost profits from healthy trade.
    income = max(0, state["trade_flow"] // 20)
    inpost.credits += income


def logistics_phase(state):
    # Automatic abstracted redistribution.
    needy = [l for l in LOCATIONS.values() if l.life <= 1]
    suppliers = [l for l in LOCATIONS.values() if l.life >= 4]

    shipments = 0
    for dst in needy:
        for src in suppliers:
            r = route_between(src.name, dst.name)
            if r and r.active:
                src.life -= 1
                dst.life += 1
                shipments += 1
                break

    # Trade should degrade under pressure, but not collapse automatically.
    baseline_recovery = 2 if state["network"] >= 70 else 0
    pressure = max(0, len(needy) - shipments)
    state["trade_flow"] = max(
        0,
        min(100, state["trade_flow"] + baseline_recovery + shipments * 3 - pressure * 2)
    )

    # Connectivity depends on satellites and open routes.
    open_ratio = sum(1 for r in ROUTES if r.active) / len(ROUTES)
    sat_factor = state["satellites"] / 7
    state["network"] = int(100 * (0.65 * open_ratio + 0.35 * sat_factor))


def crisis_phase(state):
    # Conditional story seeds.
    if LOCATIONS["Silesia"].life == 0:
        state["events"].append("KRYZYS: Silesia ma mniej niż 72 godziny zapasu podtrzymania życia.")
    if state["satellites"] <= 2:
        state["events"].append("KRYZYS: Daleka strona Księżyca jest niemal odcięta.")
    if state["ai_compute"] >= 6:
        state["events"].append("KRYZYS: Model nadał pierwszą autonomiczną wiadomość.")
    if state["network"] < 45:
        state["events"].append("KRYZYS: Księżyc rozpada się na izolowane enklawy.")
    if state["trade_flow"] < 35:
        state["events"].append("KRYZYS: Handel między frakcjami zamiera.")


def reopen_some_routes(state):
    for r in ROUTES:
        if not r.active and random.random() < 0.35:
            r.active = True
            state["events"].append(f"Ponownie otwarto trasę {r.a} ↔ {r.b}.")


def run_simulation(turns=12, seed=42):
    random.seed(seed)
    state = {
        "turn": 0,
        "satellites": 6,
        "network": 85,
        "trade_flow": 75,
        "ai_compute": 2,
        "surface_network": surface_network_score(),
        "events": [],
        "history": [],
    }

    for turn in range(1, turns + 1):
        state["turn"] = turn
        state["events"] = []

        production_phase()
        satellite_phase(state)
        infrastructure_phase(state)
        pirate_phase(state)
        faction_phase(state)
        logistics_phase(state)
        crisis_phase(state)

        if turn % 3 == 0:
            reopen_some_routes(state)

        snapshot = {
            "turn": turn,
            "satellites": state["satellites"],
            "network": state["network"],
            "trade_flow": state["trade_flow"],
            "ai_compute": state["ai_compute"],
            "surface_network": state["surface_network"],
            "events": list(state["events"]),
        }
        state["history"].append(snapshot)

    return state


# =========================
# COURIER REACHABILITY
# =========================

def courier_reachable_locations(courier: Courier, turns=12, days_per_turn=3):
    """
    Finds places the courier could plausibly visit during the campaign,
    assuming travel is sequential and the courier may return/refuel at nodes.

    This is deliberately generous: it computes reachability within the total
    campaign time budget, not one fixed mission itinerary.
    """
    total_days = turns * days_per_turn
    dist = {name: math.inf for name in LOCATIONS}
    dist[courier.start] = 0.0
    visited = set()

    while len(visited) < len(LOCATIONS):
        current = min(
            (n for n in LOCATIONS if n not in visited),
            key=lambda n: dist[n],
            default=None
        )
        if current is None or dist[current] == math.inf:
            break

        visited.add(current)

        for nxt, route in neighbors(current):
            if route.mode == "rover" and route.distance_km > courier.rover_range_km:
                continue
            if route.mode == "hopper" and not courier.hopper_access:
                continue
            if route.mode == "orbital" and not courier.orbital_access:
                continue

            extra = route_travel_days(route)
            if route_effective_risk(route) > 0.18:
                extra += 0.3  # cautious routing / waiting

            nd = dist[current] + extra
            if nd < dist[nxt]:
                dist[nxt] = nd

    reachable = {
        name: round(days, 1)
        for name, days in dist.items()
        if days <= total_days
    }
    return dict(sorted(reachable.items(), key=lambda kv: kv[1]))


def suggest_playable_courier():
    """
    Picks a courier with a geographically rich but still limited slice
    of the Moon. Silesia is intentionally favored for the first campaign.
    """
    scored = []
    for c in COURIERS:
        reach = courier_reachable_locations(c)
        score = 0
        score += len(reach) * 2
        if "Silesia" in reach:
            score += 6
        if "Shackleton Ice" in reach:
            score += 5
        if "Crater Zero" in reach:
            score += 4
        if "Tycho Station" in reach:
            score += 3
        # Penalize too-global reach to keep asset scope sane.
        if len(reach) > 9:
            score -= (len(reach) - 9) * 4
        scored.append((score, c, reach))

    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0]


def print_report(state):
    print("=" * 68)
    print("LUNAR INPOST — 12-TURN STRATEGY SIMULATION")
    print("=" * 68)

    for h in state["history"]:
        print(
            f"\nTURA {h['turn']:02d} | "
            f"Sieć {h['network']:3d}% | "
            f"Handel {h['trade_flow']:3d}% | "
            f"Satelity {h['satellites']} | "
            f"AI Compute {h['ai_compute']} | "
            f"Drogi {h['surface_network']:2d}%"
        )
        for e in h["events"]:
            print("  -", e)

    print("\n" + "=" * 68)
    print("INFRASTRUKTURA POWIERZCHNIOWA")
    print("=" * 68)
    for r in ROUTES:
        if r.mode != "rover":
            continue
        print(
            f"{r.a:20s} ↔ {r.b:20s}  "
            f"{r.road_class:10s} {r.distance_km:4d} km  "
            f"~{route_travel_days(r):4.2f} d  "
            f"energia x{ROAD_ENERGY_MULT.get(r.road_class, 1.45):.2f}  "
            f"stan {r.condition:3d}%"
        )

    score, courier, reach = suggest_playable_courier()

    print("\n" + "=" * 68)
    print("PROPONOWANY BOHATER")
    print("=" * 68)
    print(f"{courier.name} — baza: {courier.start}")
    print(f"Dostęp do hopperów: {'tak' if courier.hopper_access else 'nie'}")
    print(f"Dostęp orbitalny: {'tak' if courier.orbital_access else 'nie'}")
    print(f"Zasięg łazika: {courier.rover_range_km} km")

    print("\nLokacje dostępne w kampanii 12 tur:")
    for loc, days in reach.items():
        print(f"  {loc:22s}  minimalnie ~{days:4.1f} dni podróży")

    print("\nSUGEROWANY SLICE 3D:")
    slice_names = [
        n for n in reach
        if n in {
            "Silesia", "Lubin Deep", "Shackleton Ice",
            "Crater Zero", "Tycho Station", "InPost Central"
        }
    ]
    for n in slice_names:
        print("  -", n)


if __name__ == "__main__":
    state = run_simulation(turns=12, seed=42)
    print_report(state)
