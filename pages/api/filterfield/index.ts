import { NextApiRequest, NextApiResponse } from 'next';
import { sendSuccessResponse } from '../../../libs/api/apipage.js';
import { FilterFieldTypeValue } from '../../../libs/api/apitypes.js';

// GET: ../filterfield
// fetches the filter field types
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    // GET
    sendSuccessResponse(res)(Object.values(FilterFieldTypeValue));
};
