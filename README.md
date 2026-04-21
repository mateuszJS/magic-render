_Hello there!_

```bash
npm i @mateuszjs/magic-render
```

# Generating WebGPU Binding Groups Layout and analyzing memory of structs

https://webgpufundamentals.org/webgpu/lessons/resources/wgsl-offset-computer.html#

# Releasing versions

Each Pull Request has to be merged with squash (currnetly to `main`, we have dropped `next` branch),, the following naming convention needs to be respected:

| Commit Message                                                                                                                                                                                   | Release Type                                                                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `fix(pencil): stop graphite breaking when too much pressure applied`                                                                                                                             | patch/fix                                                                                                   |
| `feat(pencil): add 'graphiteWidth' option`                                                                                                                                                       | minor/feature                                                                                               |
| `perf(pencil): remove graphiteWidth option`<br><br>`BREAKING CHANGE: The graphiteWidth option has been removed.`<br>`The default graphite width of 10mm is always used for performance reasons.` | major/breaking release <br /> (Note that the `BREAKING CHANGE: ` token must be in the footer of the commit) |

## Testing locally:

```bash
npm link
```

Creates link in global registry on your machine.

Then call

```bash
npm link @mateuszjs/magic-render
```

In the repo where you want to put local version of the package.
Remember to build package to see an update! To unlink call `npm unlink @mateuszjs/magic-render`

## Glossary

### Units:

- `Viewport` - value expressed in pixels which will be rendered onto the screen. Represents exactly how many pixels will be rendered, already includes retina/non-retina. It's physical device pixel, not CSS pixel.

- `World` - values expressed in abstract units used in projects. This unit is absolute, never changes, does not depend on anything. This is how all sizes of all assets and assets' properties are kept expressed in zig state and snapshots.

- `Texel` - value expressed in texels (pixel but for texture), usually in SDF texture texels. It corresponds to how many texels will be used in the SDF texture.

_Often when no unit is used, a value is expressed in the world coordinates OR the unit is obvious from the context._
