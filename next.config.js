/* eslint-disable @typescript-eslint/no-var-requires */
module.exports = (phase) => {
    const d = new Date();
    const buildid = `${d.getUTCFullYear()}${
        d.getUTCMonth() + 1
    }${d.getUTCDate()}-${d.getUTCHours()}${d.getUTCMinutes()}.${d.getUTCMilliseconds()}`;

    return {
        env: {
            BUILD_ID: buildid,
        },
        webpack5: function (config, options) {
            config.plugins
                .push
                // add modules that should never be shipped in the client bundle here. mostly next.js is pretty good about
                // eliminating these but just in case... see: https://arunoda.me/blog/ssr-and-server-only-modules
                // new require('webpack').IgnorePlugin(/faker/)
                ();

            return config;
        },
        images: {
            domains: ['static.gallformers.org', 'dhz6u1p7t6okk.cloudfront.net'],
        },
        generateBuildId: async () => {
            //TODO convert this to the latest git hash
            return buildid;
        },
        strictMode: true,
        // this causes failures on Linux. Not sure why but for now disabling it.
        // i18n: {
        //     locales: ['en'],
        //     defaultLocale: 'en',
        // },
    };
};
