_Hello there!_

```bash
npm i @mateuszjs/magic-render
```

# Generating WebGPU Binding Groups Layout and analyzing memory of structs

https://webgpufundamentals.org/webgpu/lessons/resources/wgsl-offset-computer.html#

# Releasing versions

Each Pull Request has to be merged with squash, the following naming convention needs to be respected:

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

In the repo where you want to put local veriso of the package.
Remember to build package to see an update!
