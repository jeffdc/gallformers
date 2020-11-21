import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { GlossaryEntryUpsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        const entry = req.body as GlossaryEntryUpsertFields;

        const f = await db.glossary.upsert({
            where: { word: entry.word },
            update: {
                definition: entry.definition,
                urls: entry.urls,
            },
            create: {
                word: entry.word,
                definition: entry.definition,
                urls: entry.urls,
            },
        });

        res.status(200).redirect(`/glossary#${entry.word}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
