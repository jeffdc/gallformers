/* eslint-disable @typescript-eslint/no-var-requires */
const { PHASE_DEVELOPMENT_SERVER } = require('next/constants');

module.exports = (phase) => {
    return {
        env: {
            DBPATH: (() => {
                if (phase === PHASE_DEVELOPMENT_SERVER) {
                    return 'prisma/gallformers.sqlite';
                } else {
                    return 'data/gallformers.sqlite';
                }
            })(),
        },
        experimental: {
            cpus: PHASE_DEVELOPMENT_SERVER ? true : 1,
        },
        webpack: function (config, webpack) {
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
