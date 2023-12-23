import { useSession } from 'next-auth/react';
import Link from 'next/link.js';
import useIsMounted from '../hooks/useIsMounted.js';

type Props = {
    id: string | number;
    type: 'taxonomy' | 'gall' | 'gallhost' | 'glossary' | 'host' | 'images' | 'source' | 'speciessource' | 'section' | 'place';
};

const Edit = ({ id, type }: Props): JSX.Element => {
    const { data: session } = useSession();
    const mounted = useIsMounted();

    return (
        <>
            {mounted && session && (
                <Link.default href={`/admin/${type}?id=${id}`} className="p-1">
                    ✎
                </Link.default>
            )}
        </>
    );
};

export default Edit;
