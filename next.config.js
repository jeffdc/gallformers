/* eslint-disable @typescript-eslint/no-var-requires */
const { PHASE_DEVELOPMENT_SERVER } = require('next/constants');

module.exports = (phase) => {
    return {
        env: {
            APP_URL: (() => {
                if (phase === PHASE_DEVELOPMENT_SERVER) {
                    return 'http://localhost:3000';
                } else {
                    return 'http://gallformers.org:3000';
                }
            })(),
        },
        webpack: function (config) {
            config.plugins
                .push
                // add modules that should never be shipped in the client bundle here. mostly next.js is pretty good about
                // eliminating these but just in case... see: https://arunoda.me/blog/ssr-and-server-only-modules
                // new require('webpack').IgnorePlugin(/faker/)
                ();

            return config;
        },
    };
};
