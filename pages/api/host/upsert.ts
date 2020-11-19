import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        const h = req.body;

        const abundanceConnect = () => {
            if (h.abundance) {
                return { connect: { abundance: h.abundance } };
            } else {
                return {};
            }
        };

        const sp = await db.species.upsert({
            where: { name: h.name },
            update: {
                family: { connect: { name: h.family } },
                abundance: { connect: { abundance: h.abundance } },
                synonyms: h.synonyms,
                commonnames: h.commonnames,
                description: h.description,
            },
            create: {
                name: h.name,
                genus: h.name.split(' ')[0],
                family: { connect: { name: h.family } },
                abundance: abundanceConnect(),
                synonyms: h.synonyms,
                commonnames: h.commonnames,
                description: h.description,
            },
        });

        res.status(200).redirect(`/host/${sp.id}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
