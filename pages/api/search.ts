import { NextApiRequest, NextApiResponse } from "next";
import { searchGalls } from "../../libs/search";
import { SearchQuery } from "../../libs/types";

export const findGalls = async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    const q = req.query as SearchQuery;
    const results = await searchGalls(q);

    res.status(200).json(JSON.stringify({ results }))
}