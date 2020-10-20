import useSWR from 'swr';
import fetch from '../libs/fetch'

function useSearch(query) {
    if (!query || !process.env.API_URL) {
        throw new Error(`Must have a query (${query}) and a valid API_URL (${process.env.API_URL})`)
    }

    const url = new URL(`${process.env.API_URL}/api/search`);
    url.searchParams.append("host", query.host);
    url.searchParams.append("location", query.location);
    url.searchParams.append("detachable", query.detachable);
    url.searchParams.append("texture", query.texture);
    url.searchParams.append("alignment", query.alignment);
    url.searchParams.append("walls", query.walls);
    url.searchParams.append("color", query.color);
    url.searchParams.append("shape", query.shape);
    url.searchParams.append("cells", query.cells);

    return useSWR(url.toString(), fetch);
}

export default useSearch;