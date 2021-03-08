import useSWR from 'swr';
import { TaxTreeForSpecies } from '../../libs/api/apitypes';

const useTaxTreeForSpecies = (id: string): { taxTree: TaxTreeForSpecies; isLoading: boolean; isError: unknown } => {
    const { data, error } = useSWR(`../api/taxonomy?id=${id}`, (...args) => fetch(args).then((res) => res.json()));

    return {
        taxTree: data,
        isLoading: !error && !data,
        isError: error,
    };
};

export default useTaxTreeForSpecies;
