import useSWR from 'swr';
import fetch from '../libs/fetch'

function useSearch(search) {
    const url = new URL(`${process.env.API_URL}/search`);
    url.searchParams.append("host", search.host);
    url.searchParams.append("location", search.location);
    url.searchParams.append("detachable", search.detachable);
    url.searchParams.append("texture", search.texture);
    url.searchParams.append("alignment", search.alignment);
    url.searchParams.append("walls", search.walls);

    return useSWR(url.toString(), fetch);
}

export default useSearch;