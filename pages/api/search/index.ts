import { NextApiRequest, NextApiResponse } from 'next';
import { gallsByHostGenus, gallsByHostName } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.host && !req.query.genus) {
            res.status(400).end('No valid query provided.');
        }

        const query = req.query.host as string;
        if (req.query.host) {
            res.status(200).json(await gallsByHostGenus(query));
        } else {
            res.status(200).json(await gallsByHostName(query));
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
