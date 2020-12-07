import { NextApiRequest, NextApiResponse } from 'next';
import { gallsByHostGenus, gallsByHostName } from '../../../libs/db/gall';
import { mightFail } from '../../../libs/utils/util';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.host && !req.query.genus) {
            res.status(400).end('No valid query provided.');
        }

        if (req.query.host) {
            res.status(200).json(await mightFail(gallsByHostName(decodeURI(req.query.host as string))));
        } else {
            res.status(200).json(await mightFail(gallsByHostGenus(decodeURI(req.query.genus as string))));
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
