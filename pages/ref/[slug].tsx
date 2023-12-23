import { GetStaticPaths } from 'next';
import ErrorPage from 'next/error.js';
import Head from 'next/head.js';
import { useRouter } from 'next/router.js';
import DateFormatter from '../../components/ref/dateformatter.js';
import PostBody from '../../components/ref/postBody.js';
import markdownToHtml from '../../libs/pages/mdtoHtml.js';
import { getAllPosts, getPostBySlug } from '../../libs/pages/refposts.js';
import PostType from '../../types/post.js';

type Props = {
    post: PostType;
    morePosts: PostType[];
    preview?: boolean;
};

const Post = ({ post }: Props) => {
    const router = useRouter();
    if (!router.isFallback && !post?.slug) {
        return <ErrorPage.default statusCode={404} />;
    }
    return (
        <>
            {router.isFallback ? (
                <h4>Loading…</h4>
            ) : (
                <>
                    <article className="m-4">
                        <Head.default>
                            <title>{post.title}</title>
                        </Head.default>
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
        if (!post || !content) throw '404';

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
    } catch (e) {
        return { notFound: true };
    }
}

export const getStaticPaths: GetStaticPaths = async () => {
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
