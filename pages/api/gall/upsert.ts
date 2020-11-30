import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { GallUpsertFields } from '../../../libs/apitypes';
import { upsertGall } from '../../../libs/db/gall';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const gall = req.body as GallUpsertFields;
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        const spid = await upsertGall(gall);

        res.status(200).redirect(`/gall/${spid}`).end();
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: `Failed to update gall ${gall.name}.` });
    }
};
