/* eslint-disable @typescript-eslint/ban-types */
import React, { ReactNode } from 'react';
import { hasProp } from './utils/util';

// lifted from: https://github.com/Scimonster/React-Serialize/tree/fragments-custom-components
// got tired of trying to fight broken babel builds to build this simple thing, so copied... so shoot me.
// I also ported it to TS and made various other changes to make it fit current needs. :)

/**
 * Serialize React element to JSON string
 *
 * @param {ReactNode} element
 * @returns {string}
 */
export function serialize(element: ReactNode): string {
    const replacer = (key: string, value: string | ReactNode) => {
        switch (key) {
            case '_owner':
            case '_store':
            case 'ref':
            case 'key':
                return;
            case 'type':
                if (typeof value === 'string') {
                    return value;
                }
                if (value === React.Fragment) {
                    return '<>';
                }
                if (value != undefined || value != null) {
                    if (hasProp(value, 'displayName')) {
                        return value.displayName;
                    }
                    if (hasProp(value, 'name')) {
                        return value.name;
                    }
                }
                throw new Error(`Got key of 'type' but it is not a parseable shape.`);
            default:
                return value;
        }
    };

    return JSON.stringify(element, replacer);
}

/**
 * Deserialize JSON string to React element
 *
 * @param {string|object} data
 * @returns {ReactNode}
 */
export function deserialize(data: string | object | undefined | null): ReactNode {
    if (data == null || data == undefined) {
        return undefined;
    }

    if (typeof data === 'string') {
        data = JSON.parse(data);
    }
    if (data instanceof Object) {
        return deserializeElement(data, undefined);
    }
    throw new Error('Deserialization error: incorrect data type');
}

type Element = {
    type: string;
    props: object;
};

function deserializeElement(element: object | [] | Element, key: string | number | undefined): ReactNode {
    if (typeof element !== 'object' || element == null || element == undefined) {
        return element;
    }

    if (element instanceof Array) {
        return element.map((el, i) => deserializeElement(el, i));
    }

    // Now element has following shape { type: string, props: object }
    let { type, props } = element as Element;

    if (typeof type !== 'string') {
        throw new Error('Deserialization error: element type must be string');
    }

    if (type === '<>') {
        type = React.Fragment.toString();
    } else {
        type = type.toLowerCase();
    }

    if (hasProp(props, 'children')) {
        const children = props.children as object | [] | Element;
        props = { ...props, children: deserializeElement(children, undefined) };
    }

    return React.createElement(type, { ...props, key });
}
