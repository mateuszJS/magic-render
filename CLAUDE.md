This is an npm package which is a web canvas graphics editor. It uses WebGPU and Zig compiled to WASM.

Check ADRs/ before making architectural decisions which do nto ofllow existing patterns.

Each time you update heading of public functions in src/logic/index.zig, you might need to also update src/logic/index.d.ts to inform typescript about the changes.
