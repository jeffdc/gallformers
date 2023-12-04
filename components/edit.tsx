import { useSession } from 'next-auth/react';
import Link from 'next/link';
import React from 'react';
import useIsMounted from '../hooks/useIsMounted';

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
                <Link href={`/admin/${type}?id=${id}`} className="p-1">
                    ✎
                </Link>
            )}
        </>
    );
};

export default Edit;
