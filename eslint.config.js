import eslint from '@eslint/js';
import tseslintPlugin from '@typescript-eslint/eslint-plugin';
import tseslintParser from '@typescript-eslint/parser';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';
import nextPlugin from '@next/eslint-plugin-next';
import prettierPlugin from 'eslint-plugin-prettier';
import globals from 'globals';
import { FlatCompat } from "@eslint/eslintrc";
import path from "path";
import { fileURLToPath } from "url";

// mimic CommonJS variables -- not needed if using CommonJS
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const compat = new FlatCompat({
    baseDirectory: __dirname
});

// Clean up any globals with whitespace in their names
const browserGlobals = { ...globals.browser };
const nodeGlobals = { ...globals.node };
const jestGlobals = { ...globals.jest };

// Remove any globals with whitespace in their names
Object.keys(browserGlobals).forEach(key => {
  if (key.trim() !== key) delete browserGlobals[key];
});
Object.keys(nodeGlobals).forEach(key => {
  if (key.trim() !== key) delete nodeGlobals[key];
});
Object.keys(jestGlobals).forEach(key => {
  if (key.trim() !== key) delete jestGlobals[key];
});

export default [
    eslint.configs.recommended,
    ...compat.extends('plugin:@typescript-eslint/recommended'),
    ...compat.extends('plugin:@typescript-eslint/recommended-requiring-type-checking'),
    ...compat.extends('plugin:react/recommended'),
    ...compat.extends('plugin:react-hooks/recommended'),
    ...compat.extends('plugin:@next/next/recommended'),
    ...compat.extends('plugin:prettier/recommended'),
    {
        files: ['**/*.{js,jsx,ts,tsx}'],
        plugins: {
            '@typescript-eslint': tseslintPlugin,
            'react': reactPlugin,
            'react-hooks': reactHooksPlugin,
            '@next/next': nextPlugin,
            'prettier': prettierPlugin,
        },
        languageOptions: {
            ecmaVersion: 2022,
            sourceType: 'module',
            parser: tseslintParser,
            parserOptions: {
                ecmaFeatures: {
                    jsx: true,
                },
                project: './tsconfig.json',
            },
            globals: {
                ...browserGlobals,
                ...nodeGlobals,
                ...jestGlobals,
            },
        },
        settings: {
            react: {
                version: 'detect',
            },
        },
        rules: {
            'react/react-in-jsx-scope': 'off',
            'react-hooks/rules-of-hooks': 'error',
            'react-hooks/exhaustive-deps': 'warn',
            '@next/next/no-img-element': 'off',
            '@typescript-eslint/no-explicit-any': 'warn',
            '@typescript-eslint/explicit-function-return-type': 'off',
            '@typescript-eslint/explicit-module-boundary-types': 'off',
        },
    },
    {
        files: ['**/*.tsx'],
        rules: {
            'react/prop-types': 'off',
        },
    },
    {
        ignores: ['.next/**/*', '__tests__/**/*', 'lambdas/**/*', 'eslint.config.js'],
    },
];
