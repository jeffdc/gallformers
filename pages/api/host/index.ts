import { NextApiRequest, NextApiResponse } from 'next';
import * as O from 'fp-ts/lib/Option';
import { apiSearchEndpoint, getQueryParam } from '../../../libs/api/apipage';
import { hostsSearch, hostsSearchSimple } from '../../../libs/db/host';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    if (O.isSome(getQueryParam(req)('simple'))) {
        apiSearchEndpoint(req, res, hostsSearchSimple);
    } else {
        apiSearchEndpoint(req, res, hostsSearch);
    }
};
