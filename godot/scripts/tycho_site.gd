extends RefCounted
## Local metres inside the existing NAC_DTM_TYCHOPK 2 m sector.
## Tycho Station sits on the real central-peak summit (see tycho_power_plant.gd,
## which found the tallest sample in the sector by scanning the baked tiles):
## ~157 m median elevation here, ~270 m from the true +217 m crest and its
## power plant. Moved further north/west than the first relocation pass (was
## (-150,-1180)) specifically so the east annex's south mini-dome (m2) and D2
## no longer need mounding up over a real hollow to reach D1's shared
## city_level: m2 now needs essentially no fill (real median within ~1 m of
## city_level) and D2's fill dropped from ~72 m to ~38 m (still real, still
## needs an engineered footing -- 340 m out from D1 the ground is genuinely
## that much lower -- but roughly half what it was). m1 and m3 read as cut
## into the slope instead (m3 substantially so, ~37 m), same accepted
## "dug into the hill" look as before.
##
## Trade-off knowingly accepted for now: this sits close enough to the
## sector's northern real-DEM edge that the InPost highway's local corridor
## (road_streamer.gd's Tycho branch, anchored on CENTER + HIGHWAY_ANCHOR_OFFSET)
## no longer keeps its gate/forecourt/apron stations on real ground the way
## the previous site did -- real coverage now runs out barely past the gate.
## road_streamer.gd's Tycho reach was shortened accordingly (see its own
## comment) rather than re-solving the full gate/highway fit again; revisit
## together if the site moves again.
const CENTER := Vector2(-290.0, -1385.0)
const RADIUS := 100.0
const BLEND := 45.0
## Dome-centre -> local highway anchor, authored once against the original
## crater-floor site (where CENTER sat right on old road_streamer.SECTOR_ORIGIN)
## and preserved as a rigid offset ever since -- every distance the cosmoport
## and the baked highway measure from this anchor (forecourt, apron, junction,
## motorway start) stays correct under any CENTER relocation this way.
const HIGHWAY_ANCHOR_OFFSET := Vector2(-9.0, -39.0)

static func weight(x: float, z: float) -> float:
	return 1.0 - smoothstep(RADIUS, RADIUS + BLEND, Vector2(x, z).distance_to(CENTER))
