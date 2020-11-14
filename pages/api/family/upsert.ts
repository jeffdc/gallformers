import { PrismaClient } from '@prisma/client';
import { NextApiRequest, NextApiResponse } from 'next';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const h = req.body;
        const db = new PrismaClient();

        const f = await db.family.upsert({
            where: { name: h.name },
            update: {
                description: h.description,
            },
            create: {
                name: h.name,
                description: h.description,
            },
        });

        res.status(200).redirect(`/family/${f.id}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
