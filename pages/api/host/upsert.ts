import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { SpeciesUpsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';
import { HostTaxon } from '../../../libs/db/dbinternaltypes';
import { upsertHost } from '../../../libs/db/host';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        const h = req.body as SpeciesUpsertFields;
        const spId = await upsertHost(h);

        res.status(200).redirect(`/host/${spId}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
