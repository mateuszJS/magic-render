import { fileURLToPath } from "url"
import path from "path"
// const BundleAnalyzerPlugin = require('webpack-bundle-analyzer').BundleAnalyzerPlugin
// thanks to that plugin we don't need to make sure wasm-pack is installed
import HtmlWebpackPlugin from 'html-webpack-plugin'

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
  devtool: isProd ? undefined : "eval-source-map",
  watch: !isProd,
  devServer: { // HMR doesn't support ESM
    hot: false, // and anyway with canvas we would need to perform reload
    liveReload: true,
  },
  resolve: {
    extensions: [".ts", ".js", '.wasm', '.wgsl', '.jpg', '.png', '.zig'],
    modules: [path.resolve(__dirname, "src"), "node_modules"],
    /* useful with absolute imports, "src" dir now takes precedence over "node_modules" */
  },
  output: {
    filename: '[name].mjs',  // Direct filename instead of [name].js
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
        use: "ts-loader",
        exclude: /node_modules/,
      },
      {
        test: /\.wgsl$/,
        type: "asset/source",
      },
      {
        test: /\.(png|jpg)$/,
        type: "asset/resource",
      },
      // {
      //   test: /\.wasm$/,
      //   type: "asset/inline",
      // },
      {
        test: /\.zig$/,
        exclude: /node_modules/,
        use: {
          loader: path.resolve('zigar-loader.cjs'),
          options: {
            embedWASM: isProd,
            optimize: isProd ? 'ReleaseFast' : 'Debug', // we can play with ReleaseSmall also
          },
        }
      },
    ],
  },

  // Disable code splitting and runtime chunks
  optimization: {
    runtimeChunk: false,
    splitChunks: false,
    minimize: isProd
  },
  plugins: [
    // isProd && !process.env.CI && new BundleAnalyzerPlugin({
    //   analyzerMode: 'static' // 'server' had issue running along with PrerendererWebpackPlugin
    // }),
  ],
}

const libConfig = {
  ...baseConfig,
  entry: { 'index': './src/index.ts' },
  output: {
    ...baseConfig.output,
    path: path.resolve(__dirname, "lib"),
  }
}

// Test config
const testConfig = {
  ...baseConfig,
  entry: { 'integrationTest': './integration-tests/index.ts' },
  output: {
    ...baseConfig.output,
    path: path.resolve(__dirname, "lib-test"),
  },
  plugins: [
    ...baseConfig.plugins,
    new HtmlWebpackPlugin({
      template: path.resolve(__dirname, "integration-tests/template.html"),
      inject: true,
      chunks: ['integrationTest'],
      scriptLoading: "module",
    }),
  ],
}

export default isProd ? [libConfig, testConfig] : testConfig
