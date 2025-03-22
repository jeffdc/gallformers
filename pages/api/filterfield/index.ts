import { NextApiRequest, NextApiResponse } from 'next';
import { sendSuccessResponse } from '../../../libs/api/apipage';
import { FilterFieldTypeValue } from '../../../libs/api/apitypes';

// GET: ../filterfield
// fetches the filter field types
//
export default (req: NextApiRequest, res: NextApiResponse): void => {
    // GET
    sendSuccessResponse(res)(Object.values(FilterFieldTypeValue));
};
