struct Vertex {
  @location(0) position: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) originalPosition: vec2f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var<storage, read> quadBezierCurves: array<array<vec2f, 4>>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  out.position = u.worldViewProjection * vert.position;
  out.originalPosition = vert.position.xy;
  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  var minDistance = 1000.0;
  var minI: u32 = 0;
  let curvesCount = arrayLength(&quadBezierCurves);

  for (var i: u32 = 0; i < curvesCount; i++) {
    let distance = distance(quadBezierCurves[i][0], in.originalPosition);
    if (minDistance > distance) {
      minDistance = distance;
      minI = i;
    }
  }
  return vec4f(
    (f32(minI) / f32(curvesCount)),
    0.0,
    minDistance / 5.0,
    1.0
  );
}
