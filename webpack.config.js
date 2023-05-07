const glob = require("glob");
const path = require("path");
const webpack = require("webpack");
const Overrides = require("./Client/Assets/CC_Script/Overrides.ios.js");

const AllFramesAtDocumentStart = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/AllFrames/AtDocumentStart/*.{js,mjs}"
);
const AllFramesAtDocumentEnd = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/AllFrames/AtDocumentEnd/*.{js,mjs}"
);
const MainFrameAtDocumentStart = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/MainFrame/AtDocumentStart/*.{js,mjs}"
);
const MainFrameAtDocumentEnd = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/MainFrame/AtDocumentEnd/*.{js,mjs}"
);
const WebcompatAllFramesAtDocumentStart = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/AllFrames/WebcompatAtDocumentStart/*.{js,mjs}"
);
const AutofillAllFramesAtDocumentStart = glob.sync(
  "./Client/Frontend/UserContent/UserScripts/AllFrames/AutofillAtDocumentStart/*.{js,mjs}"
);

// Ensure the first script loaded at document start is __firefox__.js
// since it defines the `window.__firefox__` global.
const needsFirefoxFile = {
  AllFramesAtDocumentStart,

  // PDF content does not execute user scripts designated to
  // run at document start for some reason. So, we also need
  // to include __firefox__.js for the document end scripts.
  // ¯\_(ツ)_/¯
  AllFramesAtDocumentEnd,
};

for (let [name, files] of Object.entries(needsFirefoxFile)) {
  if (path.basename(files[0]) !== "__firefox__.js") {
    throw `ERROR: __firefox__.js is expected to be the first script in ${name}.js`;
  }
}

// Custom plugin used to replace imports used in Desktop code that use uris:
// resource://... with Assets/...
// This is needed because aliases are not supported for URI imports.
// See: https://github.com/webpack/webpack/issues/12792
const CustomResourceURIWebpackPlugin =
  new webpack.NormalModuleReplacementPlugin(/resource:(.*)/, function (
    resource
  ) {
    const issuer = path.basename(resource.contextInfo.issuer);
    const moduleName = path.basename(resource.request);
    const override = Overrides.ModuleOverrides[moduleName];
    if (override && issuer !== override) {
      resource.request = resource.request.replace(moduleName, override);
    }
    resource.request = resource.request.replace(/.*\//, "Assets/CC_Script/");
  });

module.exports = {
  mode: "production",
  entry: {
    AllFramesAtDocumentStart,
    AllFramesAtDocumentEnd,
    MainFrameAtDocumentStart,
    MainFrameAtDocumentEnd,
    WebcompatAllFramesAtDocumentStart,
    AutofillAllFramesAtDocumentStart,
  },
  // optimization: { minimize: false }, // use for debugging
  output: {
    filename: "[name].js",
    path: path.resolve(__dirname, "Client/Assets"),
  },
  module: {
    rules: [],
  },
  plugins: [CustomResourceURIWebpackPlugin],
  resolve: {
    fallback: {
      url: require.resolve("page-metadata-parser"),
    },
    alias: {
      Assets: path.resolve(__dirname, "Client/Assets"),
    },
  },
};
