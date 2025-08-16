import React from 'react';
import { render, screen, cleanup } from '@testing-library/react';
import PostBody from '../postBody';

type MockDOMPurify = {
    __esModule: true;
    default: {
        sanitize: jest.Mock<string, [string]>;
    };
};

// Mock DOMPurify
jest.mock('dompurify', () => ({
    __esModule: true,
    default: {
        sanitize: jest.fn((content: string) => content),
    },
}));

describe('PostBody', () => {
    beforeEach(() => {
        // Clear all mocks before each test
        jest.clearAllMocks();
        cleanup();
    });

    afterEach(() => {
        cleanup();
    });

    it('renders content correctly', () => {
        const content = '<p>Test content</p>';
        render(<PostBody content={content} />);

        const article = screen.getByRole('article');
        expect(article).toBeInTheDocument();
        expect(article).toHaveTextContent('Test content');
    });

    it('applies custom className when provided', () => {
        const content = '<p>Test content</p>';
        const customClass = 'custom-class';

        render(<PostBody content={content} className={customClass} />);

        const article = screen.getByRole('article');
        expect(article).toHaveClass('custom-class');
        expect(article).toHaveClass('markdown');
    });

    it('sanitizes content using DOMPurify', () => {
        const content = '<script>alert("xss")</script><p>Safe content</p>';
        const mockDOMPurify = jest.requireMock<MockDOMPurify>('dompurify');

        render(<PostBody content={content} />);

        expect(mockDOMPurify.default.sanitize).toHaveBeenCalledWith(content);
        expect(screen.getByRole('article')).toHaveTextContent('Safe content');
    });
});
