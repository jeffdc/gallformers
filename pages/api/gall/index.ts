import { pipe } from 'fp-ts/lib/function';
import { Option } from 'fp-ts/lib/Option';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { gallById } from '../../../libs/db/gall';
import { GallApi } from '../../../libs/api/apitypes';

export const getQueryId = (id: string | string[] | null | undefined): Option<number> => {
    // eslint-disable-next-line prettier/prettier
    return pipe(
        O.fromNullable(Array.isArray(id) ? null : id),
        O.map(parseInt),
    )
};

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const id = getQueryId(req.query.speciesid);
        const errMsg = (): TaskEither<Error, GallApi[]> => {
            return TE.left(new Error('Failed to provide the species_id as a query param.'));
        };
        const err = (e: Error) => res.status(400).json(e);

        const succ = (gall: GallApi[]) => res.status(200).json(gall[0]);

        // eslint-disable-next-line prettier/prettier
        await pipe(
            id,
            O.fold(errMsg, gallById),
            TE.fold(TE.taskify(err), TE.taskify(succ)),
        )();

    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
