import { PrismaClient } from '@prisma/client';
import { NextApiRequest, NextApiResponse } from 'next';
import { GallUpsertFields } from '../../../libs/apitypes';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const gall = req.body as GallUpsertFields;
        const db = new PrismaClient({ log: ['query'] });

        const connectIfNotNull = (fieldName: string, value: string | undefined) => {
            if (value) {
                return { connect: { [fieldName]: value } };
            } else {
                return {};
            }
        };

        const createFromIds = (fieldName: string, ids: number[]) => {
            return ids.map((l) => {
                return { [fieldName]: { connect: { id: l } } };
            });
        };
        console.log(`${JSON.stringify(gall, null, '  ')}`);
        const sp = await db.species.upsert({
            where: { name: gall.name },
            update: {
                abundance: connectIfNotNull('abundance', gall.abundance),
                family: { connect: { name: gall.family } },
                synonyms: gall.synonyms,
                commonnames: gall.commonnames,
                description: gall.description,
                taxontype: { connect: { taxoncode: 'gall' } },
                gall: {
                    create: {
                        alignment: { connect: { alignment: gall.alignment } },
                        cells: { connect: { cells: gall.cells } },
                        color: { connect: { color: gall.color } },
                        detachable: gall.detachable ? 1 : 0,
                        shape: { connect: { shape: gall.shape } },
                        walls: { connect: { walls: gall.walls } },
                        taxontype: { connect: { taxoncode: 'gall' } },
                        galllocation: { create: createFromIds('location', gall.locations) },
                        galltexture: { create: createFromIds('texture', gall.textures) },
                    },
                },
                host_galls: {
                    create: createFromIds('gallspecies', gall.hosts),
                },
            },
            create: {
                name: gall.name,
                genus: gall.name.split(' ')[0],
                family: { connect: { name: gall.family } },
                abundance: connectIfNotNull('abundance', gall.abundance),
                synonyms: gall.synonyms,
                commonnames: gall.commonnames,
                description: gall.description,
                taxontype: { connect: { taxoncode: 'gall' } },
                gall: {
                    create: {
                        alignment: connectIfNotNull('alignment', gall.alignment),
                        cells: connectIfNotNull('cells', gall.cells),
                        color: connectIfNotNull('color', gall.color),
                        detachable: gall.detachable ? 1 : 0,
                        shape: connectIfNotNull('shape', gall.shape),
                        walls: connectIfNotNull('walls', gall.walls),
                        taxontype: { connect: { taxoncode: 'gall' } },
                        galllocation: { create: createFromIds('location', gall.locations) },
                        galltexture: { create: createFromIds('texture', gall.textures) },
                    },
                },
                host_galls: {
                    create: createFromIds('gallspecies', gall.hosts),
                },
            },
        });

        res.status(200).redirect(`/gall/${sp.id}`).end();
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
