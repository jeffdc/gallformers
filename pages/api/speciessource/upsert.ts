import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import { SpeciesSourceInsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        const sourcespecies = req.body as SpeciesSourceInsertFields;
        try {
            // see if this mapping already exists
            const existing = await db.speciessource.findFirst({
                where: {
                    source_id: { equals: sourcespecies.source },
                    species_id: { equals: sourcespecies.species },
                },
            });

            // if this one is the new default, then make sure all of the other ones are not default
            if (sourcespecies.useasdefault) {
                db.speciessource.updateMany({
                    data: { useasdefault: 0 },
                    where: {
                        AND: [{ source_id: { equals: sourcespecies.source } }, { species_id: { equals: sourcespecies.species } }],
                    },
                });
            }

            const results = await db.speciessource.upsert({
                where: {
                    id: existing?.id ? existing.id : -1,
                },
                create: {
                    source: { connect: { id: sourcespecies.source } },
                    species: { connect: { id: sourcespecies.species } },
                    description: sourcespecies.description,
                    useasdefault: sourcespecies.useasdefault ? 1 : 0,
                },
                update: {
                    description: sourcespecies.description,
                    useasdefault: sourcespecies.useasdefault ? 1 : 0,
                },
            });

            res.status(200).send(JSON.stringify(results));
        } catch (e) {
            console.error(e);
            throw new AggregateError(
                [e],
                `Failed to add species-source mapping for species(${sourcespecies.species}) and source(${sourcespecies.source}).`,
            );
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
