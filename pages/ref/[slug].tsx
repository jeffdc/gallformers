import { GetStaticPaths } from 'next';
import ErrorPage from 'next/error.js';
import Head from 'next/head';
import { useRouter } from 'next/router';
import DateFormatter from '../../components/ref/dateformatter';
import PostBody from '../../components/ref/postBody';
import markdownToHtml from '../../libs/pages/mdtoHtml';
import { getAllPosts, getPostBySlug } from '../../libs/pages/refposts';
import PostType from '../../types/post';

type Props = {
    post: PostType;
    morePosts: PostType[];
    preview?: boolean;
};

const Post = ({ post }: Props) => {
    const router = useRouter();
    if (!router.isFallback && !post?.slug) {
        return <ErrorPage statusCode={404} />;
    }
    return (
        <>
            {router.isFallback ? (
                <h4>Loading…</h4>
            ) : (
                <>
                    <article className="m-4">
                        <Head>
                            <title>{post.title}</title>
                        </Head>
                        <h1 className="my-2">{post.title}</h1>
                        <em>
                            <DateFormatter dateString={post.date} /> - {post.author.name}
                        </em>
                        <hr />
                        <PostBody content={post.content} />
                    </article>
                </>
            )}
        </>
    );
};

export default Post;

type Params = {
    params: {
        slug: string;
    };
};

export async function getStaticProps({ params }: Params) {
    try {
        const post = getPostBySlug(params.slug, ['title', 'date', 'slug', 'author', 'content']);
        const content = await markdownToHtml(post.content || '');
        if (!post || !content) throw new Error('404');

        return {
            props: {
                key: params.slug,
                post: {
                    ...post,
                    content,
                },
            },
            revalidate: 60 * 60, // republish hourly
        };
    } catch {
        return { notFound: true };
    }
}

export const getStaticPaths: GetStaticPaths = () => {
    const posts = getAllPosts(['slug']);

    return {
        paths: posts.map((post) => {
            return {
                params: {
                    slug: post.slug,
                },
            };
        }),
        fallback: true,
    };
};
