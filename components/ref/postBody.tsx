import { memo, useEffect, useState } from 'react';
import markdownStyles from './markdown-styles.module.css';
import DOMPurify from 'dompurify';

type Props = {
    content: string;
    className?: string;
};

const PostBody = memo(({ content, className = '' }: Props) => {
    const [sanitizedContent, setSanitizedContent] = useState(content);

    useEffect(() => {
        // Only run on client side
        if (typeof window !== 'undefined') {
            setSanitizedContent(DOMPurify.sanitize(content));
        }
    }, [content]);

    return (
        <div
            className={`${markdownStyles['markdown']} ${className}`}
            dangerouslySetInnerHTML={{ __html: sanitizedContent }}
            role="article"
            aria-label="Post content"
        />
    );
});

PostBody.displayName = 'PostBody';

export default PostBody;
