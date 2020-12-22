import { useEffect, useState } from 'react';

const getDims = () => {
    // check if this being invoked from the server side.
    if (typeof window == 'undefined') {
        return { width: 0, height: 0 };
    }
    const { innerWidth: width, innerHeight: height } = window;
    return { width, height };
};

const useWindowDimensions = (): { width: number; height: number } => {
    const [dims, setDims] = useState(getDims());

    const handle = () => setDims(getDims);

    useEffect(() => {
        window.addEventListener('resize', handle);
        return () => window.removeEventListener('resize', handle);
    }, []);

    return dims;
};

export default useWindowDimensions;
