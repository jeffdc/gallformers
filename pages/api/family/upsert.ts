import { NextApiRequest, NextApiResponse } from 'next';
import { FamilyUpsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const family = req.body as FamilyUpsertFields;

        const f = await db.family.upsert({
            where: { name: family.name },
            update: {
                description: family.description,
            },
            create: {
                name: family.name,
                description: family.description,
            },
        });

        res.status(200).redirect(`/family/${f.id}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
