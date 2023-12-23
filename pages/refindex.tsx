import Head from 'next/head.js';
import Link from 'next/link.js';
import { Container } from 'react-bootstrap';
import { getAllPosts } from '../libs/pages/refposts.js';
import Post from '../types/post.js';

type Props = {
    allPosts: Post[];
};

const Index = ({ allPosts }: Props) => {
    return (
        <>
            <Head.default>
                <title>Gallformers Reference Library</title>
            </Head.default>
            <Container className="mx-0 mt-4">
                <h1 className="my-4">The Gallformers Reference Library</h1>
                {allPosts.map((p) => (
                    <article key={p.slug}>
                        <header className="">
                            <Link.default href={`/ref/${p.slug}`}>
                                <h5 className="">{p.title}</h5>
                            </Link.default>
                            <span className="small">
                                <em>{`${p.author.name} - ${p.date}`}</em>
                            </span>
                        </header>
                        <section>
                            <p className="small">{p.description}</p>
                        </section>
                    </article>
                ))}
            </Container>
        </>
    );
};

export default Index;

export const getStaticProps = async () => {
    const allPosts = getAllPosts(['title', 'date', 'slug', 'author', 'description']);

    return {
        props: { allPosts },
        revalidate: 60 * 60, // republish hourly
    };
};
