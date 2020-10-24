import { getTextures } from '../../../../database';

export default async function getTexturesHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(getTextures);
}