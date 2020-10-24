import { getColors } from '../../../../database';

export default async function getColorsHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getColors());
}