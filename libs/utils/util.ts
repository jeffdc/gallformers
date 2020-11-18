// Welcome to the inevitable utils file!!!

/**
 * Checks an object, o, for the presence of the prop.
 * @param o the object to check
 * @param prop the prop to check for
 */
export function hasProp<T extends unknown, K extends PropertyKey>(o: T, prop: K): o is T & Record<K, unknown> {
    if (!o) return false;

    return Object.prototype.hasOwnProperty.call(o, prop);
}

export function bugguideUrl(species: string): string {
    return `https://bugguide.net/index.php?q=search&keys=${encodeURI(species)}&search=Search`;
}

export function iNatUrl(species: string): string {
    return `https://www.inaturalist.org/search?q=${encodeURI(species)}`;
}

export function gScholarUrl(species: string): string {
    return `https://scholar.google.com/scholar?hl=en&q=${species}`;
}

/**
 * Returns a random integer between [min, max]
 * @param min
 * @param max
 */
export function randInt(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1) + min);
}
