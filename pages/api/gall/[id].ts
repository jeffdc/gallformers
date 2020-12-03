import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { deleteGall } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        if (req.method === 'DELETE') {
            const speciesid = parseInt(
                Array.isArray(req.query.id) && req.query.id.length > 1 ? req.query.id[0] : (req.query.id as string),
            );

            (await deleteGall(speciesid)).mapOrElse(
                (err) => res.status(400).json({ error: err }),
                () => res.status(200).json({ name: 'Gall' }),
            );
        } else {
            res.status(405).end();
        }
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: 'Failed to Delete.' });
    }
};
