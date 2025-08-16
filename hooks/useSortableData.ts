import { useMemo, useState } from 'react';

export type SortDirection = 'asc' | 'desc';
export type SortableTableConfig<T> = {
    key: keyof T;
    direction: SortDirection;
};

export const useSortableData = <T>(
    items: T[],
    config: SortableTableConfig<T>,
): { items: T[]; requestSort: (k: keyof T) => void; sortConfig: SortableTableConfig<T> } => {
    const [sortConfig, setSortConfig] = useState(config);

    const sortedItems = useMemo(() => {
        const sortableItems = [...items];
        if (sortConfig !== null) {
            sortableItems.sort((a, b) => {
                if (a[sortConfig.key] < b[sortConfig.key]) {
                    return sortConfig.direction === 'asc' ? -1 : 1;
                }
                if (a[sortConfig.key] > b[sortConfig.key]) {
                    return sortConfig.direction === 'asc' ? 1 : -1;
                }
                return 0;
            });
        }
        return sortableItems;
    }, [items, sortConfig]);

    const requestSort = (key: keyof T) => {
        let direction: SortDirection = 'asc';
        if (sortConfig && sortConfig.key === key && sortConfig.direction === 'asc') {
            direction = 'desc';
        }
        setSortConfig({ key, direction });
    };

    return { items: sortedItems, requestSort, sortConfig };
};
