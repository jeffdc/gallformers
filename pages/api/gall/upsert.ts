import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { GallUpsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const gall = req.body as GallUpsertFields;
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

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

        const sp = await db.species.upsert({
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
                hosts: {
                    create: createFromIds('hostspecies', gall.hosts),
                },
            },
            update: {
                family: { connect: { name: gall.family } },
                abundance: connectIfNotNull('abundance', gall.abundance),
                synonyms: gall.synonyms,
                commonnames: gall.commonnames,
                description: gall.description,
                gall: {
                    update: {
                        // ugh, have to fake it when the create side of the upsert executes otherwise an error occurs since the
                        // gall.id is undefined. In "theory" we should never hit the case where the gall.id is undefined AND we
                        // execute the update rather than the create above.
                        where: { species_id: gall.id ? gall.id : 0 },
                        data: {
                            alignment: connectIfNotNull('alignment', gall.alignment),
                            cells: connectIfNotNull('cells', gall.cells),
                            color: connectIfNotNull('color', gall.color),
                            detachable: gall.detachable ? 1 : 0,
                            shape: connectIfNotNull('shape', gall.shape),
                            walls: connectIfNotNull('walls', gall.walls),
                            galllocation: {
                                // this seems stupid but I can not figure out a way to update these many-to-many
                                // like is provided with the 'set' operation for 1-to-many. :(
                                deleteMany: { location_id: { notIn: [] } },
                                create: createFromIds('location', gall.locations),
                            },
                            galltexture: {
                                deleteMany: { texture_id: { notIn: [] } },
                                create: createFromIds('texture', gall.textures),
                            },
                        },
                    },
                },
                hosts: {
                    deleteMany: { host_species_id: { notIn: [] } },
                    create: createFromIds('hostspecies', gall.hosts),
                },
            },
            where: { name: gall.name },
        });

        res.status(200).redirect(`/gall/${sp.id}`).end();
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: `Failed to update gall ${gall.name}.` });
    }
};
