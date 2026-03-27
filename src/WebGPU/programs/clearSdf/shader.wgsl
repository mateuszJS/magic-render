@group(0) @binding(0) var texture: texture_storage_2d<rgba32float, write>;

@compute @workgroup_size($WORKING_GROUP_SIZE)
fn main(@builtin(global_invocation_id) id: vec3u) {
    textureStore(texture, id.xy, vec4f(-3.402823466e+38));
}