import fs from 'fs';
import { join } from 'path';
import matter from 'gray-matter';
import sanitize from 'sanitize-filename';

const postsDirectory = join(process.cwd(), 'ref');
// logger.info(`Pulling ref articles from '${postsDirectory}'`);

export function getPostSlugs() {
    return fs.readdirSync(postsDirectory);
}

export function getPostBySlug(slug: string, fields: string[] = []) {
    const realSlug = sanitize(slug.replace(/\.md$/, ''));
    const fullPath = join(postsDirectory, `${realSlug}.md`);
    const fileContents = fs.readFileSync(fullPath, 'utf8');
    const { data, content } = matter(fileContents);

    type Items = {
        [key: string]: string;
    };

    const items: Items = {};

    // Ensure only the minimal needed data is exposed
    fields.forEach((field) => {
        if (field === 'slug') {
            items[field] = realSlug;
        }
        if (field === 'content') {
            items[field] = content;
        }

        if (typeof data[field] !== 'undefined') {
            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
            items[field] = data[field];
        }
    });

    return items;
}

export function getAllPosts(fields: string[] = []) {
    const slugs = getPostSlugs();
    const posts = slugs
        .map((slug) => getPostBySlug(slug, fields))
        // sort posts by date in descending order - dates are in YYYY-MM-DD format
        .sort((post1, post2) => post1.date?.split('-').join().localeCompare(post2.date?.split('-').join()))
        .reverse();
    return posts;
}
