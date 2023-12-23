import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { NextApiRequest, NextApiResponse } from 'next';
import { sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage';
import { allGlossaryEntries } from '../../../libs/db/glossary.ts';

// GET: ../glossary
// fetches the glossary entries
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    return await pipe(allGlossaryEntries(), TE.mapLeft(toErr), TE.fold(sendErrorResponse(res), sendSuccessResponse(res)))();
};
