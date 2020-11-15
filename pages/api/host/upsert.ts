import { PrismaClient } from '@prisma/client';
import { NextApiRequest, NextApiResponse } from 'next';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const h = req.body;
        const db = new PrismaClient();

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
