import {
    galllocationCreateWithoutGallInput,
    galltextureCreateWithoutGallInput,
    hostCreateWithoutGallspeciesInput,
} from '@prisma/client';
import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { GallUpsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';
import { GallTaxon } from '../../../libs/db/dbinternaltypes';

type InsertFieldName = 'hostspecies' | 'location' | 'texture';
type ConnectTypes = hostCreateWithoutGallspeciesInput | galllocationCreateWithoutGallInput | galltextureCreateWithoutGallInput;

function connectWithIds<T extends ConnectTypes>(fieldName: InsertFieldName, ids: number[]): T[] {
    const key = fieldName as keyof T;
    return ids.map((l) => {
        // ugly casting due to what seems to be a TS bug. See: https://github.com/Microsoft/TypeScript/issues/13948
        return ({ [key]: { connect: { id: l } } } as unknown) as T;
    });
}

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

        const sp = await db.species.upsert({
            create: {
                name: gall.name,
                genus: gall.name.split(' ')[0],
                family: { connect: { name: gall.family } },
                abundance: connectIfNotNull('abundance', gall.abundance),
                synonyms: gall.synonyms,
                commonnames: gall.commonnames,
                taxontype: { connect: { taxoncode: GallTaxon } },
                gall: {
                    create: {
                        alignment: connectIfNotNull('alignment', gall.alignment),
                        cells: connectIfNotNull('cells', gall.cells),
                        color: connectIfNotNull('color', gall.color),
                        detachable: gall.detachable ? 1 : 0,
                        shape: connectIfNotNull('shape', gall.shape),
                        walls: connectIfNotNull('walls', gall.walls),
                        taxontype: { connect: { taxoncode: GallTaxon } },
                        galllocation: { create: connectWithIds('location', gall.locations) },
                        galltexture: { create: connectWithIds('texture', gall.textures) },
                    },
                },
                hosts: {
                    create: connectWithIds('hostspecies', gall.hosts),
                },
            },
            update: {
                family: { connect: { name: gall.family } },
                abundance: connectIfNotNull('abundance', gall.abundance),
                synonyms: gall.synonyms,
                commonnames: gall.commonnames,
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
                                // create: [{ location: { connect: { id: gall.locations[0] } } }],
                                create: connectWithIds('location', gall.locations),
                            },
                            galltexture: {
                                deleteMany: { texture_id: { notIn: [] } },
                                create: connectWithIds('texture', gall.textures),
                            },
                        },
                    },
                },
                hosts: {
                    deleteMany: { host_species_id: { notIn: [] } },
                    create: connectWithIds('hostspecies', gall.hosts),
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
