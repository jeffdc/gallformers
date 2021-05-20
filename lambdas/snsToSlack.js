/* eslint-disable @typescript-eslint/no-var-requires */
var https = require('https');
var util = require('util');

exports.handler = function (event, context) {
    console.log(JSON.stringify(event, null, 2));
    console.log('From SNS:', event.Records[0].Sns.Message);

    var postData = {
        channel: '#site-monitoring',
        username: 'AWS SNS Alert',
        text: '*Gallformers is Down!!!*',
        icon_emoji: ':scream_cat:',
    };

    postData.attachments = [
        {
            color: 'danger',
            text: 'Action is needed NOW!',
        },
    ];

    var options = {
        method: 'POST',
        hostname: 'hooks.slack.com',
        port: 443,
        path: 'MUST GET PATH TO SLACK INTEGRATION WITH SECRET KEY AND PASTE IT HERE!!!',
    };

    var req = https.request(options, function (res) {
        res.setEncoding('utf8');
        res.on('data', function (chunk) {
            context.done(null);
        });
    });

    req.on('error', function (e) {
        console.log('problem with request: ' + e.message);
    });

    req.write(util.format('%j', postData));
    req.end();
};
