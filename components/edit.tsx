import { useSession } from 'next-auth/react';
import Link from 'next/link';
import React from 'react';

type Props = {
    id: string | number;
    type: 'taxonomy' | 'gall' | 'gallhost' | 'glossary' | 'host' | 'images' | 'source' | 'speciessource' | 'section' | 'place';
};

const Edit = ({ id, type }: Props): JSX.Element => {
    const { data: session } = useSession();

    return (
        <>
            {session && (
                <Link href={`/admin/${type}?id=${id}`}>
                    <a className="p-1">✎</a>
                </Link>
            )}
        </>
    );
};

export default Edit;
