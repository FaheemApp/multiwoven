import { useMemo } from 'react';
import type { ModelEntity } from '@/views/Models/types';

type UseModelColumnsResult = {
  columns: string[];
  isLoading: boolean;
  isUsingCachedSchema: boolean;
};

/**
 * Returns the columns stored on the model schema.
 */
export const useModelColumns = (model?: ModelEntity | null): UseModelColumnsResult => {
  const columns = useMemo(() => Object.keys(model?.schema ?? {}), [model?.schema]);

  return {
    columns,
    isLoading: false,
    isUsingCachedSchema: true,
  };
};
