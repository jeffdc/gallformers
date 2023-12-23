import { pipe } from 'fp-ts/lib/function.js';
import * as TE from 'fp-ts/lib/TaskEither.js';
import { NextApiRequest, NextApiResponse } from 'next';
import { sendErrorResponse, sendSuccessResponse, toErr } from '../../../libs/api/apipage.js';
import { allGlossaryEntries } from '../../../libs/db/glossary.js';

// GET: ../glossary
// fetches the glossary entries
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    return await pipe(allGlossaryEntries(), TE.mapLeft(toErr), TE.fold(sendErrorResponse(res), sendSuccessResponse(res)))();
};
