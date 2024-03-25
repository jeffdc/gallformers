import nextJest from 'next/jest.js';
const createJestConfig = nextJest({
    dir: './',
});
const customJestConfig = {
    // Automatically clear mock calls and instances between every test
    clearMocks: true,
    // The directory where Jest should output its coverage files
    coverageDirectory: '.coverage',
    // A list of paths to modules that run some code to configure or set up the testing framework before each test
    setupFilesAfterEnv: ['./jest.setup.js'],
    moduleNameMapper: {
        '\\.(scss|sass|css)$': 'identity-obj-proxy',
    },
    moduleDirectories: ['node_modules', '<rootDir>/'],
    testEnvironment: 'jest-environment-jsdom',
};
export default createJestConfig(customJestConfig);
