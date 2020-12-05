import { NextApiRequest, NextApiResponse } from 'next';
import { deleteHost } from '../../../libs/db/host';
import { apiIdEndpoint } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteHost);
