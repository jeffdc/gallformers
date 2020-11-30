import { speciessource } from '@prisma/client';
import { Source } from '../apitypes';
import db from './db';

export const speciesSourceByIds = async (speciesId: string, sourceId: string): Promise<Source | null> => {
    return db.speciessource.findFirst({
        include: { source: true },
        where: {
            AND: [{ species_id: { equals: parseInt(speciesId) } }, { source_id: { equals: parseInt(sourceId) } }],
        },
    });
};

export const deleteSpeciesSourceByIds = async (speciesId: string, sourceId: string): Promise<speciessource | null> => {
    const s = await speciesSourceByIds(speciesId, sourceId);
    if (s) {
        return db.speciessource.delete({
            where: {
                id: s.id,
            },
        });
    } else {
        return Promise.resolve(null);
    }
};
