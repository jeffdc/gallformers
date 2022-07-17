import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint } from '../../../../libs/api/apipage';
import { sectionSearch } from '../../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiSearchEndpoint(req, res, sectionSearch);
