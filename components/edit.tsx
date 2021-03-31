import { useSession } from 'next-auth/client';
import Link from 'next/link';
import React from 'react';

type Props = {
    id: string | number;
    type: 'family' | 'gall' | 'gallhost' | 'glossary' | 'host' | 'images' | 'source' | 'speciessource' | 'section';
};

const Edit = ({ id, type }: Props): JSX.Element => {
    const [session] = useSession();

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
