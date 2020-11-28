export const genOptions = (opts: readonly string[], includeEmpty = true): JSX.Element => {
    if (!opts) {
        throw new Error('Must have a valid list of options to render.');
    } else if (new Set(opts).size !== opts.length) {
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
