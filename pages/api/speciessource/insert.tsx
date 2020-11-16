import { NextApiRequest, NextApiResponse } from 'next';
import { SpeciesSourceInsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const sourcespecies = req.body as SpeciesSourceInsertFields;

        const results = await Promise.all(
            sourcespecies.species
                .map((species) => {
                    return sourcespecies.sources.map((source) => {
                        try {
                            return db.speciessource.create({
                                data: {
                                    source: { connect: { id: source } },
                                    species: { connect: { id: species } },
                                },
                            });
                        } catch (e) {
                            throw new AggregateError(
                                [e],
                                `Failed to add species-source mapping for species(${species}) and source(${source}).`,
                            );
                        }
                    });
                })
                .flatMap((x) => x),
        );

        res.status(200).send(JSON.stringify(results));
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
