@group(0) @binding(0) var texture: texture_storage_2d<r32float, write>;

@compute @workgroup_size(1)
fn main(@builtin(global_invocation_id) id: vec3u) {
    textureStore(texture, id.xy, vec4f(-3.402823466e+38));
}