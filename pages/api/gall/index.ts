import { NextApiRequest, NextApiResponse } from 'next';
import db from '../../../libs/db/db';
import { gallById } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.speciesid) {
            res.status(400).end('Failed to provide the species_id as a query param.');
        } else {
            const gall = await gallById(req.query.speciesid as string);
            res.status(200).json(gall);
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
