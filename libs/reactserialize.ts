/* eslint-disable @typescript-eslint/ban-types */
import React, { ReactNode } from "react"

// lifted from: https://github.com/Scimonster/React-Serialize/tree/fragments-custom-components
// got tired of trying to fight broken babel builds to build this simple thing, so copied... so shoot me.
// I also ported it to TS. :) 

/**
 * Serialize React element to JSON string
 *
 * @param {ReactNode} element
 * @returns {string}
 */
export function serialize(element: ReactNode): string {
  const replacer = (key: any, value: any) => {
    switch (key) {
      case "_owner":
      case "_store":
      case "ref":
      case "key":
        return
      case "type":
        if (typeof value === 'string') {
          return value
        }
        if (value === React.Fragment) {
          return '<>'
        }
        return value.displayName || value.name
      default:
        return value
    }
  }

  return JSON.stringify(element, replacer)
}


/**
 * Deserialize JSON string to React element
 *
 * @param {string|object} data
 * @returns {ReactNode}
 */
export function deserialize(data: (string | object)): ReactNode {
  if (typeof data === "string") {
    data = JSON.parse(data)
  }
  if (data instanceof Object) {
    return deserializeElement(data, undefined)
  }
  throw new Error("Deserialization error: incorrect data type")
}

function deserializeElement(element: any, key: any): ReactNode {
  if (typeof element !== "object") {
    return element
  }

  if (element === null) {
    return element
  }

  if (element instanceof Array) {
    return element.map((el, i) => deserializeElement(el, i))
  }

  // Now element has following shape { type: string, props: object }
  let { type, props } = element

  if (typeof type !== "string") {
    throw new Error("Deserialization error: element type must be string")
  }

  if (type === '<>') {
    type = React.Fragment
  } else {
    type = type.toLowerCase()
  }

  if (props.children) {
    props = { ...props, children: deserializeElement(props.children, undefined) }
  }

  return React.createElement(type, { ...props, key })
}
