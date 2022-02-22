import Head from 'next/head';
import Link from 'next/link';
import { Container } from 'react-bootstrap';
import { getAllPosts } from '../libs/pages/refposts';
import Post from '../types/post';

type Props = {
    allPosts: Post[];
};

const Index = ({ allPosts }: Props) => {
    return (
        <>
            <Head>
                <title>Gallformers Reference Library</title>
            </Head>
            <Container className="mx-0 mt-4">
                <h1 className="my-4">The Gallformers Reference Library</h1>
                {allPosts
                    .sort((a, b) => a.title.localeCompare(b.title))
                    .map((p) => (
                        <div key={p.slug} className="my-2">
                            <Link href={`/ref/${p.slug}`}>
                                <a>{p.title}</a>
                            </Link>
                        </div>
                    ))}
            </Container>
        </>
    );
};

export default Index;

export const getStaticProps = async () => {
    const allPosts = getAllPosts(['title', 'date', 'slug', 'author']);

    return {
        props: { allPosts },
    };
};
