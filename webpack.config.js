import { fileURLToPath } from 'url'
import path from 'path'
import { BundleAnalyzerPlugin } from 'webpack-bundle-analyzer'
import HtmlWebpackPlugin from 'html-webpack-plugin'
import TerserPlugin from 'terser-webpack-plugin'

/* eslint-disable no-undef */ // node process isn't defined, but is provided while running webpack config

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const isProd = process.env.NODE_ENV === 'production'

// Base configuration shared between both formats
const baseConfig = {
  experiments: {
    asyncWebAssembly: true,
    futureDefaults: true,
    outputModule: true, // webpack will output ECMAScript module syntax whenever possible
  },
  mode: process.env.NODE_ENV,
  devtool: isProd ? 'source-map' : 'eval-source-map',
  watch: !isProd,
  devServer: {
    // HMR doesn't support ESM
    hot: false, // and anyway with canvas we would need to perform reload
    liveReload: true,
  },
  resolve: {
    extensions: ['.ts', '.js', '.wgsl', '.jpg', '.png', '.zig', '.woff2', '.ttf'],
    modules: [path.resolve(__dirname, 'src'), 'node_modules'],
    /* useful with absolute imports, "src" dir now takes precedence over "node_modules" */
  },
  output: {
    filename: '[name].mjs',
    library: {
      type: 'module',
    },
    chunkFormat: 'module',
    chunkLoading: 'import',
    module: true,
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
      {
        test: /\.wgsl$/,
        type: 'asset/source',
      },
      {
        test: /\.svg$/,
        type: 'asset/source',
      },
      {
        test: /\.woff2$/,
        type: 'asset/resource',
      },
      {
        test: /\.ttf$/,
        type: 'asset/resource',
      },
      {
        test: /\.zig$/,
        exclude: /node_modules/,
        use: {
          loader: 'zigar-loader',
          options: {
            embedWASM: isProd,
            // for now ReleaseFast gets stuck https://github.com/chung-leong/zigar/issues/666
            // once solved we can come back to ReleaseFast
            optimize: isProd ? 'ReleaseSmall' : 'Debug', // we can play with ReleaseSmall also
          },
        },
      },
    ],
  },

  // Disable code splitting and runtime chunks
  optimization: {
    runtimeChunk: false,
    splitChunks: false,
    minimize: isProd,
    minimizer: [
      // used to remove license .txt file(comes from opentype library) + let's remove rest of unnecessary comments in the code
      // https://github.com/webpack/webpack/issues/12506#issuecomment-767454504
      new TerserPlugin({
        terserOptions: {
          format: {
            comments: false,
          },
        },
        extractComments: false,
      }),
    ],
  },
  plugins: [isProd && !process.env.CI && new BundleAnalyzerPlugin({})],
}

const libConfig = {
  ...baseConfig,
  entry: { index: './src/index.ts' },
  output: {
    ...baseConfig.output,
    path: path.resolve(__dirname, 'lib'),
  },
}

// Test config
const testConfig = {
  ...baseConfig,
  entry: { integrationTest: './integration-tests/index.ts' },
  output: {
    ...baseConfig.output,
    path: path.resolve(__dirname, 'lib-test'),
  },
  plugins: [
    ...baseConfig.plugins,
    new HtmlWebpackPlugin({
      template: path.resolve(__dirname, 'integration-tests/template.html'),
      inject: true,
      chunks: ['integrationTest'],
      scriptLoading: 'module',
    }),
  ],
}

export default isProd ? libConfig : testConfig
