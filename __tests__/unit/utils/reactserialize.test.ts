import React from 'react';
import { deserialize, serialize } from '../../../libs/utils/reactserialize';
import { hasProp } from '../../../libs/utils/util';

// const reactNode = React.createElement();

describe('Serialization and Deserialization tests', () => {
    test('Should handle Fragments', () => {
        //TODO not sure how to do this as React.Fragment can not be instantiatd or manipulated like a normal node.
        // const div = React.createElement('div', {}, React.Fragment);
        // const fragment = React.Fragment;
        // const sFragment = '<>';
        // console.log(serialize(div));
        // expect(serialize(div)).toEqual(sFragment);
        // expect(deserialize(sFragment)).toEqual(fragment);
    });

    test('Should handle nested children', () => {
        const children = React.createElement(
            'ul',
            null,
            React.createElement('li', { key: '1' }, 'hi'),
            React.createElement('li', { key: '2' }, 'there'),
        );

        const div = React.createElement('div', {}, children);

        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const testDiv = deserialize(serialize(div)) as React.DetailedReactHTMLElement<any, HTMLElement>;
        expect(hasProp(testDiv, 'props')).toBeTruthy();
        expect(hasProp(testDiv, 'ref')).toBeTruthy();
        expect(hasProp(testDiv, 'type')).toBeTruthy();
        expect(testDiv.type).toBe('div');
        expect(testDiv.props.children).toBeTruthy();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const c = testDiv.props.children as React.DetailedReactHTMLElement<any, HTMLElement>;
        expect(hasProp(c, 'props')).toBeTruthy();
        expect(Array.isArray(c.props.children)).toBeTruthy();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const cs = c.props.children as React.DetailedReactHTMLElement<any, HTMLElement>[];
        expect(cs.length).toBe(2);
        expect(cs.filter((c) => c.type == 'li').length).toBe(2);
        expect(cs.filter((c) => c.props.children == 'hi').length).toBe(1);
        expect(cs.filter((c) => c.props.children == 'there').length).toBe(1);
    });
});
