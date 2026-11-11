/**
 * Builds the designer page (designer.bundle.js) and the preview that runs
 * inside its iframe (preview.bundle.js). The preview imports the real
 * tgui-next components, so both bundles share tgui's copy of Inferno.
 */
const path = require('path');

const TGUI = path.resolve(__dirname, '../tgui');
// The workspace hoists everything (Inferno included) to tgui-next
const TGUI_MODULES = path.resolve(__dirname, '../../node_modules');

module.exports = (env = {}, argv = {}) => ({
  mode: argv.mode === 'production' ? 'production' : 'development',
  context: __dirname,
  entry: {
    designer: path.resolve(__dirname, './src/designer/index.js'),
    preview: path.resolve(__dirname, './src/preview/index.js'),
  },
  output: {
    path: path.resolve(__dirname, './public/build'),
    filename: '[name].bundle.js',
  },
  resolve: {
    extensions: ['.mjs', '.js', '.jsx'],
    alias: {
      'inferno': path.resolve(TGUI_MODULES, 'inferno'),
      'inferno-shared': path.resolve(TGUI_MODULES, 'inferno-shared'),
      'inferno-vnode-flags': path.resolve(TGUI_MODULES, 'inferno-vnode-flags'),
      'tgui': TGUI,
    },
  },
  module: {
    rules: [
      {
        test: /\.m?jsx?$/,
        exclude: /node_modules/,
        use: [
          {
            loader: 'babel-loader',
            options: {
              babelrc: false,
              presets: [
                ['@babel/preset-env', {
                  modules: 'commonjs',
                  targets: { chrome: '80' },
                }],
              ],
              plugins: [
                path.resolve(TGUI_MODULES, 'babel-plugin-inferno'),
                'common/string.babel-plugin.cjs',
              ],
            },
          },
        ],
      },
      {
        test: /\.(png|jpg|svg)$/,
        use: [{ loader: 'url-loader', options: {} }],
      },
    ],
  },
  devtool: argv.mode === 'production' ? false : 'cheap-module-source-map',
  performance: { hints: false },
  plugins: [],
  stats: 'errors-warnings',
});
