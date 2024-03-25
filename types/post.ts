import Author from './author.js';

type PostType = {
    slug: string;
    title: string;
    date: string;
    description: string;
    author: Author;
    content: string;
};

export default PostType;
