import { useCallback, useEffect, useState } from 'react';
import { DeleteResults } from '../libs/apitypes';

type Params = {
    doDelete: () => DeleteResults;
};

//TOD this is a WIP...
export const useDeletable = ({ doDelete }: Params) => {
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResults>();

    const execute = useCallback(() => {
        setDeleteResults(doDelete());
    }, [doDelete]);

    useEffect(() => {
        execute();
    }, [execute]);

    return {
        existing: existing,
        setExisting: setExisting,
        deleteResults: deleteResults,
    };
};
