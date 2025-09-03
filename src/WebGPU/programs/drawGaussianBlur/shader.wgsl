struct Vertex {
  @location(0) position: vec4f,
};

struct Uniforms {
  cameraProjection: mat4x4f,
  texStart: vec2f, // point where texture bottom left corner starts rendering
  // point where texture bottom left corner starts rendering
  // use to leak the blur effect outside the texture bounds
  texEnd: vec2f, // similar as texStart but defined the end of texture, top right corner
  stdDeviation: vec2f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) texCoord: vec2f,
};

@group(0) @binding(0) var<uniform> m: Uniforms;
@group(0) @binding(1) var<uniform> u: Uniforms;
@group(0) @binding(2) var ourSampler: sampler;
@group(0) @binding(3) var ourTexture: texture_2d<f32>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  // maybe we should pass offsets from the position instead of... position?
  out.position = m.cameraProjection * vec4f(vert.position.xy, 0, 1);
  out.texCoord = vert.position.zw;
  
  return out;
}

const MAX_RADIUS: i32 = 20;

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  // Map the incoming [0..1] coords to the actual sampling region [texStart..texEnd]
  let uv_base = mix(u.texStart, u.texEnd, in.texCoord);

  // Compute texel size from the texture dimensions
  let texSize = vec2f(textureDimensions(ourTexture));
  let texel = 1.0 / max(texSize, vec2f(1.0));

  // Standard deviations for X and Y (sigma). Avoid zero to prevent div-by-zero.
  let sigma = max(u.stdDeviation, vec2f(0.0001));
  let radiusX: i32 = min(i32(ceil(3.0 * sigma.x)), MAX_RADIUS);
  let radiusY: i32 = min(i32(ceil(3.0 * sigma.y)), MAX_RADIUS);

  // Clamp sampling to the provided region so we can bleed outside the original bounds
  let uv_min = min(u.texStart, u.texEnd);
  let uv_max = max(u.texStart, u.texEnd);

  var accum: vec4f = vec4f(0.0);
  var weight_sum: f32 = 0.0;

  // 2D Gaussian kernel (separable but computed in one pass for simplicity)
  var y: i32 = -radiusY;
  loop {
    if (y > radiusY) { break; }
    let fy = f32(y);
    let wy = exp(-0.5 * (fy * fy) / (sigma.y * sigma.y));

    var x: i32 = -radiusX;
    loop {
      if (x > radiusX) { break; }
      let fx = f32(x);
      let wx = exp(-0.5 * (fx * fx) / (sigma.x * sigma.x));
      let w = wx * wy;

      let offset = vec2f(fx * texel.x, fy * texel.y);
      let uv = clamp(uv_base + offset, uv_min, uv_max);
      let c = textureSample(ourTexture, ourSampler, uv);
      accum += c * w;
      weight_sum += w;

      x += 1;
    }
    y += 1;
  }

  if (weight_sum > 0.0) {
    accum /= weight_sum;
  }
  return accum;
}
