import { NextApiRequest, NextApiResponse } from 'next';
import { deleteHost } from '../../../libs/db/host.js';
import { apiIdEndpoint } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteHost);
