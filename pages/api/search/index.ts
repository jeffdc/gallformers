import { gallWhereInput } from '@prisma/client';
import { NextApiRequest, NextApiResponse } from 'next';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.host && !req.query.genus) {
            res.status(400).end('No valid query provided.');
        }

        const whereClause: gallWhereInput = req.query.host
            ? { species: { hosts: { some: { hostspecies: { name: { equals: req.query.host as string } } } } } }
            : { species: { hosts: { some: { hostspecies: { genus: { equals: req.query.genus as string } } } } } };

        const galls = await db.gall.findMany({
            include: {
                alignment: true,
                cells: true,
                color: true,
                galllocation: { include: { location: true } },
                galltexture: { include: { texture: true } },
                shape: true,
                walls: true,
                species: { include: { hosts: { select: { hostspecies: { select: { id: true } } } } } },
            },
            where: whereClause,
        });

        res.status(200).json(galls.sort((a, b) => a.species.name?.localeCompare(b.species.name)));
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
