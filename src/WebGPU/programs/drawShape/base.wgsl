const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;

struct Vertex {
  @location(0) position: vec4f,
};

@group(0) @binding(1) var texture: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  let size = textureDimensions(texture);
  return VSOutput(
    camera_projection * vec4f(vert.position.xy, 0.0, 1.0),
    vert.position.zw * vec2f(size),
  );
}

fn getSample(pos: vec2f) -> vec4f {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let p00 = vec2u(floor_pos);
  let p10 = vec2u(floor_pos + vec2f(1.0, 0.0));
  let p01 = vec2u(floor_pos + vec2f(0.0, 1.0));
  let p11 = vec2u(floor_pos + vec2f(1.0, 1.0));

  let c00 = textureLoad(texture, p00);
  let c10 = textureLoad(texture, p10);
  let c01 = textureLoad(texture, p01);
  let c11 = textureLoad(texture, p11);

  let top = mix(c00, c10, fract_pos.x);
  let bottom = mix(c01, c11, fract_pos.x);

  return mix(top, bottom, fract_pos.y);
}


@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);

  let dist = sdf.r;
  let width = fwidth(dist);

  let hs = u.stroke_width * 0.5;

  let fill_alpha = smoothstep(hs - width, hs + width, dist);
  let fill_color = getFillColor(sdf, vsOut.uv);
  let stroke_color = getStrokeColor(sdf, vsOut.uv);
  let color = mix(stroke_color, fill_color, fill_alpha);

  let total_alpha = smoothstep(-hs - width, -hs + width, dist);

  return vec4f(color.rgb, color.a * total_alpha);

  // let stroke_factor = select(0.5, 0.0, sdf.g > 1.0);
  // color = vec4f(0, sdf.g % 1, 0, 1.0);
  // color = vec4f(0, 0, sdf.b / (2 * PI), 1.0);
  // color = vec4f(sdf.r / 100.0, sdf.g % 1, sdf.b / (2 * PI), 1.0);
  // color = select(vec4f(0.5, 0, 0, 1), vec4f(0, 0, 0.5, 1), u32(sdf.r / 20.0) % 2 == 0);
}
