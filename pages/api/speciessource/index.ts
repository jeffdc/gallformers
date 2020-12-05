import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { deleteSpeciesSourceByIds, speciesSourceByIds } from '../../../libs/db/speciessource';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.speciesid || !req.query.sourceid) {
            res.status(400).end('No valid query provided. You must provide both a speciesid and a sourceid.');
        }
        const speciesid = req.query.speciesid as string;
        const sourceid = req.query.sourceid as string;

        const err = (e: Error) => res.status(500).json({ error: e });
        const succ = <T>(results: T) => res.status(200).json(results);

        if (req.method === 'GET') {
            // eslint-disable-next-line prettier/prettier
            await pipe(
                speciesSourceByIds(speciesid, sourceid),
                TE.fold(TE.taskify(err), TE.taskify(succ))
            )();
            res.status(200).json(await speciesSourceByIds(speciesid, sourceid));
        } else if (req.method === 'DELETE') {
            // eslint-disable-next-line prettier/prettier
            await pipe(
                deleteSpeciesSourceByIds(speciesid, sourceid),
                TE.fold(TE.taskify(err), TE.taskify(succ)),
            )();
        }
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: e.message });
    }
};
