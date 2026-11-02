# SimBelonging — siła przynależności do rodu liczona od roota (S4, intro §5.1):
#   strength[root] = 1
#   strength[u] = 1 - Π_v (1 - strength[v] * w(u→v)),  w(u→v) = clamp(bond(u→v) / skala, 0, 1)
# po krawędziach rodzic–dziecko, rodzeństwo i małżeństwo, tylko między żywymi członkami
# rodu (małżonek nie wciąga swojej rodziny, bo ona nie należy do rodu). Iteracja z tłumieniem
# do stabilizacji. Siła nie decyduje o przynależności, tylko może wyzwolić odejście.
class_name SimBelonging
extends RefCounted


static func neighbors(f: SimFamily, p: SimPerson, members: Dictionary) -> Array:
	var out: Array = []
	for id in [p.mother_id, p.father_id, p.spouse_id] + p.children:
		if members.has(id) and not id in out:
			out.append(id)
	for oid in members:
		var o: SimPerson = f.persons[oid]
		if o.id != p.id and not o.id in out and f.siblings(p, o):
			out.append(o.id)
	return out


static func compute(f: SimFamily, bonds: SimBonds, lineage: SimLineage, cfg: Dictionary) -> Dictionary:
	var members := {}
	for p: SimPerson in f.living_members(lineage.id):
		members[p.id] = p
	var strength := {}
	for id in members:
		strength[id] = 0.0
	if not members.has(lineage.root_id):
		return strength
	strength[lineage.root_id] = 1.0
	var adj := {}
	for id in members:
		adj[id] = neighbors(f, members[id], members)
	var scale := float(cfg["bond_scale"])
	var damping := float(cfg["damping"])
	var ids := members.keys()
	ids.sort()
	for it in int(cfg["iterations"]):
		var delta := 0.0
		for id in ids:
			if id == lineage.root_id:
				continue
			var keep := 1.0
			for v in adj[id]:
				var wt := clampf(bonds.value(id, SimBonds.person(v)) / scale, 0.0, 1.0)
				keep *= 1.0 - float(strength[v]) * wt
			var target := 1.0 - keep
			var next: float = lerpf(float(strength[id]), target, damping)
			delta = maxf(delta, absf(next - float(strength[id])))
			strength[id] = next
		if delta < float(cfg["epsilon"]):
			break
	return strength
