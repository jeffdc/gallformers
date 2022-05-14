import { useEffect, useState } from 'react';

type WindowDimentions = {
    width: number;
    height: number;
};

const useWindowDimensions = (): WindowDimentions => {
    const [dims, setDims] = useState<WindowDimentions>({ width: 0, height: 0 });

    useEffect(() => {
        const handle = () => setDims({ width: window.innerWidth, height: window.innerHeight });
        handle();
        window.addEventListener('resize', handle);
        return () => window.removeEventListener('resize', handle);
    }, []);

    return dims;
};

export default useWindowDimensions;
