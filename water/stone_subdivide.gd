extends MeshInstance3D

@export var subdivisions: int = 3  # 3 = 64x triangles, enough for dome displacement

func _ready() -> void:
    call_deferred("_subdivide")

func _subdivide() -> void:
    if not mesh:
        return
    var result: Mesh = mesh
    for _i in subdivisions:
        result = _subdivide_once(result)
    mesh = result

func _subdivide_once(source: Mesh) -> ArrayMesh:
    var arr: ArrayMesh = source if source is ArrayMesh else _to_array_mesh(source)
    var mdt := MeshDataTool.new()
    if mdt.create_from_surface(arr, 0) != OK:
        return arr

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for f in mdt.get_face_count():
        var vi0 := mdt.get_face_vertex(f, 0)
        var vi1 := mdt.get_face_vertex(f, 1)
        var vi2 := mdt.get_face_vertex(f, 2)

        var p0 := mdt.get_vertex(vi0); var p1 := mdt.get_vertex(vi1); var p2 := mdt.get_vertex(vi2)
        var n0 := mdt.get_vertex_normal(vi0); var n1 := mdt.get_vertex_normal(vi1); var n2 := mdt.get_vertex_normal(vi2)
        var u0 := mdt.get_vertex_uv(vi0); var u1 := mdt.get_vertex_uv(vi1); var u2 := mdt.get_vertex_uv(vi2)

        var pm01 := (p0+p1)*0.5; var pm12 := (p1+p2)*0.5; var pm02 := (p0+p2)*0.5
        var nm01 := (n0+n1).normalized(); var nm12 := (n1+n2).normalized(); var nm02 := (n0+n2).normalized()
        var um01 := (u0+u1)*0.5; var um12 := (u1+u2)*0.5; var um02 := (u0+u2)*0.5

        _tri(st, p0,pm01,pm02,   n0,nm01,nm02,   u0,um01,um02)
        _tri(st, pm01,p1,pm12,   nm01,n1,nm12,   um01,u1,um12)
        _tri(st, pm02,pm12,p2,   nm02,nm12,n2,   um02,um12,u2)
        _tri(st, pm01,pm12,pm02, nm01,nm12,nm02, um01,um12,um02)

    st.generate_tangents()
    return st.commit()

func _tri(st: SurfaceTool, p0,p1,p2, n0,n1,n2, u0,u1,u2) -> void:
    st.set_normal(n0); st.set_uv(u0); st.add_vertex(p0)
    st.set_normal(n1); st.set_uv(u1); st.add_vertex(p1)
    st.set_normal(n2); st.set_uv(u2); st.add_vertex(p2)

func _to_array_mesh(source: Mesh) -> ArrayMesh:
    var am := ArrayMesh.new()
    for i in source.get_surface_count():
        am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(i))
    return am
