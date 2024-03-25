export default (phase) => {
    const d = new Date();
    const buildid = `${d.getUTCFullYear()}${
        d.getUTCMonth() + 1
    }${d.getUTCDate()}-${d.getUTCHours()}${d.getUTCMinutes()}.${d.getUTCMilliseconds()}`;

    return {
        env: {
            BUILD_ID: buildid,
        },
        images: {
            remotePatterns: [
                {
                    protocol: 'https',
                    hostname: 'static.gallformers.org',
                },
                {
                    protocol: 'https',
                    hostname: 'dhz6u1p7t6okk.cloudfront.net',
                },
            ],
        },
        generateBuildId: async () => {
            //TODO convert this to the latest git hash
            return buildid;
        },
        experimental: {
            forceSwcTransforms: true,
            esmExternals: false,
        },
        // strictMode: true,
        // this causes failures on Linux. Not sure why but for now disabling it.
        // i18n: {
        //     locales: ['en'],
        //     defaultLocale: 'en',
        // },
    };
};
