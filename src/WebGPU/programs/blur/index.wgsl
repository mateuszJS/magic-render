struct Uniform {
  filterDim: i32, // x for horizontal, y for vertical
  blockDim: u32,
  sigma: f32, // standard deviation for X (when flip=0) and Y (when flip=1)
  flip: u32,
}

@group(0) @binding(0) var samp : sampler;
@group(0) @binding(1) var<uniform> u : Uniform;
@group(0) @binding(2) var inputTex : texture_2d<f32>;
@group(0) @binding(3) var outputTex : texture_storage_2d<{presentationFormat}, write>;

// This shader blurs the input texture in one direction, depending on whether
// |u.flip| is 0 or 1.
// It does so by running (128 / 4) threads per workgroup to load 128
// texels into 4 rows of shared memory. Each thread loads a
// 4 x 4 block of texels to take advantage of the texture sampling
// hardware.
// Then, each thread computes the blur result by averaging the adjacent texel values
// in shared memory.
// Because we're operating on a subset of the texture, we cannot compute all of the
// results since not all of the neighbors are available in shared memory.
// Specifically, with 128 x 128 tiles, we can only compute and write out
// square blocks of size 128 - (filterSize - 1). We compute the number of blocks
// needed in Javascript and dispatch that amount.

// 128/4 = 32 -> number of threads per working group
// does it in 4x4 block of texels(takes advantage of texture sampling hardware)
// with this beign said, we don't have all the neighbours, only this block
// That's why we can only compute & write out blocks of size 128 - (filterSize - 1)
var<workgroup> tile : array<array<vec4f, 128>, 4>;

@compute @workgroup_size(32, 1, 1)
fn main(
  @builtin(workgroup_id) WorkGroupID : vec3<u32>,
  @builtin(local_invocation_id) LocalInvocationID : vec3<u32>
) {
  let filterOffset = (u.filterDim - 1) / 2;
  let dims = vec2<i32>(textureDimensions(inputTex, 0));
  let baseIndex = vec2<i32>(WorkGroupID.xy * vec2(u.blockDim, 4) + // it's just the index of the first texel in a group
                            LocalInvocationID.xy * vec2(4, 1)) // <0, 128>
                  - vec2(filterOffset, 0);
  // baseIndex = xy of first texel of group
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      var loadIndex = baseIndex + vec2(c, r);
      if (u.flip != 0) {
        loadIndex = loadIndex.yx;
      }

      tile[r][4 * LocalInvocationID.x + u32(c)] = textureSampleLevel(
        inputTex,
        samp,
        (vec2<f32>(loadIndex) + vec2<f32>(0.5, 0.5)) / vec2<f32>(dims),
        0.0
      ).rgba;
    }
  }

  workgroupBarrier();
  // helps coordinate access to read-write memory
  // so all threads(32) will wait to hit this barrer, and then start form here together

  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      var writeIndex = baseIndex + vec2(c, r);
      if (u.flip != 0) {
        writeIndex = writeIndex.yx;
      }

      let center = i32(4 * LocalInvocationID.x) + c;
      if (center >= filterOffset &&
          center < 128 - filterOffset &&
          all(writeIndex < dims)) {
        var acc = vec4f(0.0);

        if (u.filterDim <= 1 || u.sigma <= 0.0) {
          acc = tile[r][center];
        } else {
          let denom = 2.0 * u.sigma * u.sigma;
          var wsum = 0.0;

          for (var f = 0; f < u.filterDim; f++) {
            let rel = f - filterOffset;
            let i = center + rel;
            let w = exp(- (f32(rel * rel)) / denom);
            acc = acc + w * tile[r][i];
            wsum = wsum + w;
          }
          acc = acc / wsum;
        }

        textureStore(outputTex, writeIndex, acc);
      }
    }
  }
}
