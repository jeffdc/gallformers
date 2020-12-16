import { useCallback, useEffect, useState } from 'react';
import { DeleteResult } from '../libs/api/apitypes';

type Params = {
    doDelete: () => DeleteResult;
};

//TOD this is a WIP...
export const useDeletable = ({ doDelete }: Params) => {
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

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
