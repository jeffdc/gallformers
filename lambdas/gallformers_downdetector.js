/* eslint-disable @typescript-eslint/no-var-requires */
const https = require('https');

exports.handler = async (event) => {
    'use strict';

    const data = await new Promise((resolve, reject) => {
        https
            .get('https://www.gallformers.org', (res) => {
                res.on('data', (d) => {
                    resolve(res.statusCode);
                });
            })
            .on('error', (e) => {
                reject(e);
            });
    });

    if (data !== 200) {
        throw new Error(data);
    }

    return {
        status: data,
    };
};
