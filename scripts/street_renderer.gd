extends Node3D
## Static surfaces are batched; individual props have no scripts or processing.
const MODELS = {
	"bench": preload("res://assets/models/street/street_bench.glb"),
	"bin": preload("res://assets/models/street/street_bin.glb"),
	"lamp": preload("res://assets/models/street/street_lamp.glb"),
	"planter": preload("res://assets/models/street/street_planter.glb"),
	"shelter": preload("res://assets/models/street/bus_shelter.glb"),
	"stop_sign": preload("res://assets/models/street/bus_stop_sign.glb"),
	"sedan": preload("res://assets/models/street/parked_sedan.glb"),
	"hatchback": preload("res://assets/models/street/parked_hatchback.glb")
}
const COLORS = {"road":Color("343b43"),"paving":Color("939994"),"lawn":Color("53624c"),"plaza":Color("afa591"),"paint":Color("dbd9bc")}
var builder: SurfaceTool

func build(data: Dictionary) -> void:
	name="StreetEnvironment"
	var ambient:=WorldEnvironment.new()
	ambient.name="AmbientLight"
	ambient.environment=Environment.new()
	ambient.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	ambient.environment.ambient_light_color=Color("a9b8c7")
	ambient.environment.ambient_light_energy=.28
	add_child(ambient)
	builder=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface: Dictionary in data["surfaces"]:
		var r: Rect2=surface["rect"]
		var y: float=surface["y"]
		_quad([Vector3(r.position.x,y,r.position.y),Vector3(r.end.x,y,r.position.y),Vector3(r.end.x,y,r.end.y),Vector3(r.position.x,y,r.end.y)],COLORS[surface["kind"]],Vector3.UP)
	_finish_mesh("StreetSurfaces",false)
	builder=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: Rect2 in data["curbs"]:
		_box(Vector3(r.position.x,-.025,r.position.y),Vector3(r.size.x,.075,r.size.y),Color("a1a69e"))
	_finish_mesh("Kerbs",false)
	var index:=0
	for prop: Dictionary in data["props"]:
		var model: Node3D=(MODELS[prop["kind"]] as PackedScene).instantiate()
		add_child(model)
		model.name="%s_%d" % [prop["kind"],index]
		model.position=Vector3(prop["center"].x,0,prop["center"].y)
		model.rotation.y=prop["angle"]
		index+=1
	for stop: Dictionary in data["stops"]:
		var label:=Label3D.new()
		label.text="ЭВАКУАЦИЯ"
		label.font_size=40
		label.pixel_size=.009
		label.position=Vector3(stop["pos"].x,2.9,stop["pos"].y)
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate=Color("cde2be")
		add_child(label)

func _finish_mesh(title: String,shadows: bool) -> void:
	var mesh_instance:=MeshInstance3D.new()
	mesh_instance.name=title
	mesh_instance.mesh=builder.commit()
	var mat:=StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true
	mat.roughness=1.0
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override=mat
	mesh_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

func _quad(points: Array,color: Color,normal: Vector3) -> void:
	for i in [0,1,2,0,2,3]:
		builder.set_color(color)
		builder.set_normal(normal)
		builder.add_vertex(points[i])

func _box(p: Vector3,size: Vector3,color: Color) -> void:
	var e:=p+size
	_quad([Vector3(p.x,e.y,p.z),Vector3(e.x,e.y,p.z),Vector3(e.x,e.y,e.z),Vector3(p.x,e.y,e.z)],color,Vector3.UP)
	_quad([p,Vector3(e.x,p.y,p.z),Vector3(e.x,e.y,p.z),Vector3(p.x,e.y,p.z)],color,Vector3.FORWARD)
	_quad([Vector3(p.x,p.y,e.z),Vector3(p.x,e.y,e.z),e,Vector3(e.x,p.y,e.z)],color,Vector3.BACK)
	_quad([p,Vector3(p.x,e.y,p.z),Vector3(p.x,e.y,e.z),Vector3(p.x,p.y,e.z)],color,Vector3.LEFT)
	_quad([Vector3(e.x,p.y,p.z),Vector3(e.x,p.y,e.z),e,Vector3(e.x,e.y,p.z)],color,Vector3.RIGHT)
