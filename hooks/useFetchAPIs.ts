import useSWR from 'swr';

/**
 * A hook to make fetching from the APIs more consistent and less verbose.
 *
 * @param endpoint the url path fragment to the fetch API for @T
 * @returns a function that can be used to fetch T data.
 */
export const useFetchAPIs = <T>(endpoint: string) => (
    query: string,
): { data: T | undefined; isLoading: boolean; error: unknown } => {
    const { data, error } = useSWR<T>(`${endpoint}${query}`, (...args) => fetch(args).then((res) => res.json()));

    return {
        data: data,
        isLoading: !error && !data,
        error: error,
    };
};
