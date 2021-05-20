//TODO work in progress...
exports.handler = async (event, context) => {
    const response = {
        statusCode: 200,
        body: JSON.stringify(event.Records.map((r) => r.body)),
    };
    return response;
};
