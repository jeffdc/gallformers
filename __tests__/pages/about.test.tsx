import { render, screen } from '@testing-library/react';
import { GetStaticPropsResult } from 'next';
import { getCurrentStats, Stat } from '../../libs/db/stats';
import { mightFailWithArray } from '../../libs/utils/util';
import About, { getStaticProps } from '../../pages/about';

// Mock the dependencies
jest.mock('../../libs/db/stats', () => ({
    getCurrentStats: jest.fn(),
}));

// Mock the mightFailWithArray function
jest.mock('../../libs/utils/util', () => ({
    mightFailWithArray: jest.fn(),
}));

// Mock the Image component from next/image
jest.mock('next/image', () => ({
    __esModule: true,
    default: (props: any) => {
        // eslint-disable-next-line @next/next/no-img-element
        return <img {...props} alt={props.alt} />;
    },
}));

describe('About Page', () => {
    // Sample stats data for testing
    const mockStats = [
        { type: 'galls', count: 100 },
        { type: 'gall-family', count: 20 },
        { type: 'gall-genera', count: 50 },
        { type: 'undescribed', count: 10 },
        { type: 'hosts', count: 200 },
        { type: 'host-family', count: 30 },
        { type: 'host-genera', count: 80 },
        { type: 'sources', count: 150 },
    ];

    // Mock the getCurrentStats function to return our sample data
    beforeEach(() => {
        (getCurrentStats as jest.Mock).mockResolvedValue(mockStats);
        // Mock mightFailWithArray to return the function that returns the result
        (mightFailWithArray as jest.Mock).mockImplementation(() => {
            return () => Promise.resolve(mockStats);
        });
    });

    it('renders the About page with correct title', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the page title is rendered
        expect(screen.getByText('About Us')).toBeInTheDocument();
    });

    it('displays the correct statistics', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the statistics are displayed correctly
        expect(
            screen.getByText(/100 gallformers across 20 families and 50 genera, of which 10 are undescribed/),
        ).toBeInTheDocument();
        expect(screen.getByText(/200 hosts across 30 families and 80 genera/)).toBeInTheDocument();
        expect(screen.getByText(/150 sources/)).toBeInTheDocument();
    });

    it('displays the co-founders section', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the co-founders section is rendered
        expect(screen.getByText('Our Co-founders')).toBeInTheDocument();
        expect(screen.getByText('Adam Kranz')).toBeInTheDocument();
        expect(screen.getByText('Jeff Clark')).toBeInTheDocument();
    });

    it('displays the administrators section', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the administrators section is rendered
        expect(screen.getByText('Administrators')).toBeInTheDocument();
        expect(screen.getByText("Joshua C'deBaca")).toBeInTheDocument();
        expect(screen.getByText('Tim Frey')).toBeInTheDocument();
        expect(screen.getByText('Yann Kemper')).toBeInTheDocument();
        expect(screen.getByText('Kimberlie Sasan')).toBeInTheDocument();
        expect(screen.getByText('Ramsey Sullivan')).toBeInTheDocument();
    });

    it('displays the citation section', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the citation section is rendered
        expect(screen.getByText('Citing Gallformers')).toBeInTheDocument();
        expect(screen.getByText(/All of our original content is released under a/)).toBeInTheDocument();
        expect(screen.getByText('CC-BY')).toBeInTheDocument();
    });

    it('displays the "Dare You Click?" accordion', async () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the accordion is rendered
        expect(screen.getByText('Dare You Click?')).toBeInTheDocument();
    });

    it('displays the build ID', async () => {
        // Mock the process.env.BUILD_ID
        const originalBuildId = process.env.BUILD_ID;
        process.env.BUILD_ID = 'test-build-123';

        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check if the build ID is displayed
        expect(screen.getByText(/Build: test-build-123/)).toBeInTheDocument();

        // Restore the original BUILD_ID
        process.env.BUILD_ID = originalBuildId;
    });

    it('displays the generation time', async () => {
        const genTime = '2023-01-01T00:00:00.000Z';
        render(<About stats={mockStats} genTime={genTime} />);

        // Check if the generation time is displayed
        expect(screen.getByText(/As of/)).toBeInTheDocument();
        expect(screen.getByText(genTime)).toBeInTheDocument();
    });

    it('displays the NSF grant section properly', () => {
        render(<About stats={mockStats} genTime="2023-01-01T00:00:00.000Z" />);

        // Check for the heading
        expect(screen.getByText('Funding')).toBeInTheDocument();

        // Check for the NSF logo
        const nsfLogo = screen.getByAltText('National Science Foundation Logo');
        expect(nsfLogo).toBeInTheDocument();
        expect(nsfLogo).toHaveAttribute('src', '/images/nsf-logo.svg');

        // Check for the grant text
        expect(screen.getByText(/This site is supported in part by the National Science Foundation under/)).toBeInTheDocument();

        // Check for the grant link
        const grantLink = screen.getByText('Grant No. 2418250');
        expect(grantLink).toBeInTheDocument();
        expect(grantLink).toHaveAttribute(
            'href',
            'https://www.nsf.gov/awardsearch/showAward?AWD_ID=2418250&HistoricalAwards=false',
        );
        expect(grantLink).toHaveAttribute('target', '_blank');
        expect(grantLink).toHaveAttribute('rel', 'noreferrer');
    });
});

describe('getStaticProps', () => {
    it('returns the correct props', async () => {
        // Mock the getCurrentStats function
        const mockStats = [
            { type: 'galls', count: 100 },
            { type: 'gall-family', count: 20 },
        ];
        (getCurrentStats as jest.Mock).mockResolvedValue(mockStats);

        // Mock mightFailWithArray to return the function that returns the result
        (mightFailWithArray as jest.Mock).mockImplementation(() => {
            return () => Promise.resolve(mockStats);
        });

        // Call getStaticProps
        const result = (await getStaticProps()) as GetStaticPropsResult<{ stats: Stat[]; genTime: string }>;

        // Check if the result has the correct structure
        expect(result).toHaveProperty('props');
        if ('props' in result) {
            expect(result.props).toHaveProperty('stats', mockStats);
            expect(result.props).toHaveProperty('genTime');
        }
        expect(result).toHaveProperty('revalidate', 5 * 60); // 5 minutes
    });
});
