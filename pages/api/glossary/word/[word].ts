import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';
import { NextApiRequest, NextApiResponse } from 'next';
import { sendErrorResponse, sendSuccessResponse, toErr } from '../../../../libs/api/apipage';
import { getEntryByWord } from '../../../../libs/db/glossary';

// GET: ../glossary/[word]
// fetches the glossary entry by word
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const { word } = req.query;
    if (!word || word.length <= 0) {
        res.status(400).end('Not a valid glossary word form.');
    } else {
        await pipe(
            getEntryByWord(word as string),
            TE.map((t) => {
                return t[0];
            }),
            TE.mapLeft(toErr),
            TE.fold(sendErrorResponse(res), sendSuccessResponse(res)),
        )();
    }
};
