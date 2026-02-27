import https from "node:https";

const SITE_URL = process.env.SITE_URL;

function checkSite(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, (res) => {
      // Consume response data to free up memory
      res.resume();

      if (res.statusCode === 200) {
        resolve(res.statusCode);
      } else {
        reject(new Error(`${url} returned status ${res.statusCode}`));
      }
    });

    req.on("error", (err) => {
      reject(new Error(`${url} request failed: ${err.message}`));
    });

    req.setTimeout(8000, () => {
      req.destroy();
      reject(new Error(`${url} request timed out`));
    });
  });
}

export async function handler() {
  const status = await checkSite(SITE_URL);
  console.log(`Health check passed: ${SITE_URL} returned ${status}`);
  return { status };
}
