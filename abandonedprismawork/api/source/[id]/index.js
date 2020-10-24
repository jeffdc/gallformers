import { getSource } from '../../../../database';

export default async function getSourceHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }
   
    res.json(await getSource(req.query.id));
}