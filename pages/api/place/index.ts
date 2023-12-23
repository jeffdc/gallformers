import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint } from '../../../libs/api/apipage.js';
import { searchPlaces } from '../../../libs/db/place.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiSearchEndpoint(req, res, searchPlaces);
