import { getGall } from '../../../../database';

export default async function getGallByIdHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getGall(res.query.id));
}