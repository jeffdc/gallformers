import { NextApiRequest, NextApiResponse } from 'next';
import { sendSuccResponse } from '../../../libs/api/apipage';
import { FILTER_FIELD_TYPES } from '../../../libs/api/apitypes';

// GET: ../filterfield
// fetches the filter field types
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // GET
    sendSuccResponse(res)(FILTER_FIELD_TYPES);
};
