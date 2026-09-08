extends RefCounted
## Shared placement data for the renderer and flat-array collision map.
var surfaces: Array = []
var curbs: Array = []
var props: Array = []
var stops: Array = []
var blocked: Array[Rect2] = []
var protected: Array[Rect2] = []
var map: Node
var plaza := Rect2(-12,-39,24,15)
var parking := Rect2(-39,-39,25,12)

func build(source: Node) -> Dictionary:
	map=source
	blocked.assign(map.buildings)
	for tr in map.transitions:
		if tr["from_floor"] == 0: protected.append(tr["rect"].grow(1.5))
		if tr["to_floor"] == 0: protected.append(Rect2(tr["dest"]-Vector2.ONE,Vector2.ONE*2))
	protected.append(Rect2(-4,-44,8,20))
	protected.append(Rect2(-68,-68,6,6))
	var half := Tuning.WORLD_SIZE * .5
	var pitch := Tuning.MAP_BLOCK_SIZE+Tuning.MAP_STREET_W
	var road_exclusions := [map.mall_rect.grow(Tuning.MALL_CLEARANCE),plaza,parking]
	# Asphalt streets use exactly the same block pitch as MapGen.
	for i in range(Tuning.MAP_BLOCK_COLS+1):
		var start: float = -half+i*pitch
		_surface(Rect2(start,-half,Tuning.MAP_STREET_W,Tuning.WORLD_SIZE),"road",-.025,road_exclusions)
		_surface(Rect2(-half,start,Tuning.WORLD_SIZE,Tuning.MAP_STREET_W),"road",-.025,road_exclusions)
		var center := start+Tuning.MAP_STREET_W*.5
		for d in range(-int(half)+2,int(half)-2,5):
			var mark_x := Rect2(center-.045,d,.09,2.0)
			var mark_z := Rect2(d,center-.045,2.0,.09)
			if not _at_intersection(float(d)+1.0,half,pitch):
				_surface(mark_x,"paint",.005,road_exclusions)
				_surface(mark_z,"paint",.005,road_exclusions)
	# Paved block edges, lawns in their centers and low, walkable kerbs.
	for row in Tuning.MAP_BLOCK_ROWS:
		for col in Tuning.MAP_BLOCK_COLS:
			var start := Vector2(-half+Tuning.MAP_STREET_W+col*pitch,-half+Tuning.MAP_STREET_W+row*pitch)
			var block := Rect2(start,Vector2.ONE*Tuning.MAP_BLOCK_SIZE)
			_surface(block,"paving",-.020,road_exclusions)
			_surface(block.grow(-Tuning.MAP_SIDEWALK),"lawn",-.012,road_exclusions)
			for edge in [Rect2(block.position,Vector2(block.size.x,.12)),Rect2(block.position.x,block.end.y-.12,block.size.x,.12),Rect2(block.position,Vector2(.12,block.size.y)),Rect2(block.end.x-.12,block.position.y,.12,block.size.y)]:
				for piece in _subtract_all(edge,road_exclusions+[plaza,parking]):
					curbs.append(piece)
	# Paths through grass reach actual building doors.
	for entry in map.building_data:
		if not entry["has_interior"]: continue
		var door: Vector2=entry["door_pos"]
		var block_end: float=-half+Tuning.MAP_STREET_W+(floorf((door.y+half-Tuning.MAP_STREET_W)/pitch))*pitch+Tuning.MAP_BLOCK_SIZE
		_surface(Rect2(door.x-1.25,door.y,2.5,maxf(.2,block_end-door.y)),"paving",-.006,[])
	_surface(map.mall_rect.grow(3.0),"paving",-.008,[map.mall_rect])
	_surface(plaza,"plaza",.0,[])
	_surface(Rect2(-3,-40,6,16),"paving",.002,[])
	_surface(parking,"road",.0,[])
	_surface(Rect2(-44,-34,5,7),"road",.0,[])
	for x in [-35.0,-31.5,-28.0,-24.5,-21.0,-17.5]:
		_surface(Rect2(x-1.45,-37.5,.08,5.5),"paint",.015,[])
		_surface(Rect2(x+1.37,-37.5,.08,5.5),"paint",.015,[])
		_surface(Rect2(x-1.45,-37.5,2.9,.08),"paint",.015,[])
		_place("sedan" if props.size()%2==0 else "hatchback",Vector2(x,-35),0,Vector2(1.94,4.24))
	# Entrance zebra crossing; minor crossings on the surrounding street grid.
	_crossing(Vector2(0,-42.5),false)
	for p in [Vector2(-42.5,-30),Vector2(32.5,-30),Vector2(-30,32.5),Vector2(45,7.5),Vector2(-55,-42.5),Vector2(-42.5,45)]:
		_crossing(p,absf(fmod(p.x+67.5,25.0))<.1)
	for side in [-1.0,1.0]:
		for z in [-35.0,-28.5]:
			_place("bench",Vector2(side*8.5,z),-side*PI/2,Vector2(2.2,.72))
			_place("bin",Vector2(side*10.5,z+1.7),0,Vector2(.58,.58))
		for z in [-37.0,-26.0]:
			_place("planter",Vector2(side*10.5,z),0,Vector2(1.3,1.3))
	for row in Tuning.MAP_BLOCK_ROWS:
		for col in Tuning.MAP_BLOCK_COLS:
			var p:=Vector2(-half+Tuning.MAP_STREET_W+col*pitch+1.0,-half+Tuning.MAP_STREET_W+row*pitch+1.0)
			_place("lamp",p,0,Vector2(.40,.40))
	return {"surfaces":surfaces,"curbs":curbs,"props":props,"stops":stops,"plaza":plaza,"parking":parking}

func _at_intersection(p: float,half: float,pitch: float) -> bool:
	return fposmod(p+half,pitch) < Tuning.MAP_STREET_W+1.5

func _crossing(center: Vector2,vertical_road: bool) -> void:
	for i in range(6):
		var offset: float=(i-2.5)*.70
		var rect:=Rect2(center+Vector2(-2.2,offset-.22),Vector2(4.4,.44)) if vertical_road else Rect2(center+Vector2(offset-.22,-2.2),Vector2(.44,4.4))
		_surface(rect,"paint",.018,[map.mall_rect.grow(3)])

func _place(kind: String,center: Vector2,angle: float,size: Vector2) -> bool:
	var rect:=_rotated_rect(Rect2(-size*.5,size),center,angle)
	var world:=Rect2(Vector2.ONE*(-Tuning.WORLD_SIZE*.5+.5),Vector2.ONE*(Tuning.WORLD_SIZE-1))
	if not world.encloses(rect): return false
	for b in blocked:
		if rect.grow(.45).intersects(b): return false
	for p in protected:
		if rect.intersects(p): return false
	props.append({"kind":kind,"center":center,"angle":angle,"rect":rect})
	blocked.append(rect)
	map.buildings.append(rect)
	return true

func _rotated_rect(rect: Rect2,center: Vector2,angle: float) -> Rect2:
	var a:=rect.position.rotated(-angle)+center
	var b:=rect.end.rotated(-angle)+center
	return Rect2(Vector2(minf(a.x,b.x),minf(a.y,b.y)),Vector2(absf(a.x-b.x),absf(a.y-b.y)))

func _surface(rect: Rect2,kind: String,y: float,exclusions: Array) -> void:
	for piece in _subtract_all(rect,exclusions):
		surfaces.append({"rect":piece,"kind":kind,"y":y})

func _subtract_all(rect: Rect2,exclusions: Array) -> Array[Rect2]:
	var pieces: Array[Rect2]=[rect]
	for exclusion: Rect2 in exclusions:
		var remaining: Array[Rect2]=[]
		for piece in pieces:
			if not piece.intersects(exclusion):
				remaining.append(piece)
				continue
			var overlap:=piece.intersection(exclusion)
			for candidate in [Rect2(piece.position,Vector2(piece.size.x,overlap.position.y-piece.position.y)),Rect2(piece.position.x,overlap.end.y,piece.size.x,piece.end.y-overlap.end.y),Rect2(piece.position.x,overlap.position.y,overlap.position.x-piece.position.x,overlap.size.y),Rect2(overlap.end.x,overlap.position.y,piece.end.x-overlap.end.x,overlap.size.y)]:
				if candidate.size.x>.001 and candidate.size.y>.001: remaining.append(candidate)
		pieces=remaining
	return pieces
