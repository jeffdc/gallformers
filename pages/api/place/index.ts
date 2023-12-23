import { NextApiRequest, NextApiResponse } from 'next';
import { apiSearchEndpoint } from '../../../libs/api/apipage';
import { searchPlaces } from '../../../libs/db/place.ts';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiSearchEndpoint(req, res, searchPlaces);
