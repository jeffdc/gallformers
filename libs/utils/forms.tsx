/**
 * Generates a list of <option>s to be used within a form.
 * @param opts the array of string that represent the options to be rendered.
 * @param includeEmpty if true then an empty element will be included in the list of options.
 */
export const genOptions = (opts: readonly string[], includeEmpty = true): JSX.Element => {
    if (new Set(opts).size !== opts.length) {
        throw new Error('Passed in set of options contains duplicates and this is not allowed.');
    }

    return (
        <>
            {includeEmpty ? <option key="none" value=""></option> : undefined}
            {opts
                .filter((o) => o)
                .map((o) => {
                    return (
                        <option key={o} value={o}>
                            {o}
                        </option>
                    );
                })}
        </>
    );
};
