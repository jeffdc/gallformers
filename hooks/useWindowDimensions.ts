import { useEffect, useState } from 'react';

type WindowDimensions = {
    width: number;
    height: number;
};

const useWindowDimensions = (): WindowDimensions => {
    const [dims, setDims] = useState<WindowDimensions>({ width: 0, height: 0 });

    useEffect(() => {
        const handle = () => setDims({ width: window.innerWidth, height: window.innerHeight });
        handle();
        window.addEventListener('resize', handle);
        return () => window.removeEventListener('resize', handle);
    }, []);

    return dims;
};

export default useWindowDimensions;
