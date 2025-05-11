/** @type {import('ts-jest').JestConfigWithTsJest} **/
import { createDefaultPreset, type JestConfigWithTsJest } from 'ts-jest'

const tsPresetConfig = createDefaultPreset({})

const config: JestConfigWithTsJest = {
  moduleDirectories: ['node_modules', 'src'],
  ...tsPresetConfig,
  transform: {
    ...tsPresetConfig.transform,
    "^.+.wgsl$": '<rootDir>/jestWgslTransformer.js',
  },

  testEnvironment: "jsdom",
}

export default config
