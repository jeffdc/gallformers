import { NextApiRequest, NextApiResponse } from 'next';
import * as O from 'fp-ts/lib/Option.js';
import { apiSearchEndpoint, getQueryParam } from '../../../libs/api/apipage.js';
import { hostsSearch, hostsSearchSimple } from '../../../libs/db/host.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    if (O.isSome(getQueryParam(req)('simple'))) {
        apiSearchEndpoint(req, res, hostsSearchSimple);
    } else {
        apiSearchEndpoint(req, res, hostsSearch);
    }
};
