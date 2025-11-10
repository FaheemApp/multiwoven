import { ConnectorItem } from '@/views/Connectors/types';
import type { Stream, PrimaryKeyMapping as PrimaryKeyMappingType } from '@/views/Activate/Syncs/types';
import type { ModelEntity } from '@/views/Models/types';
import { Box, FormControl, FormLabel, Select, Text } from '@chakra-ui/react';
import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getModelPreviewById } from '@/services/models';
import { useStore } from '@/stores';
import { getPathFromObject } from '@/views/Activate/Syncs/utils';

type PrimaryKeyMappingSelectorProps = {
  model: ModelEntity;
  destination: ConnectorItem;
  stream: Stream | null;
  value: PrimaryKeyMappingType | null;
  onChange: (mapping: PrimaryKeyMappingType | null) => void;
};

const PrimaryKeyMappingSelector = ({
  model,
  destination,
  stream,
  value,
  onChange,
}: PrimaryKeyMappingSelectorProps): JSX.Element => {
  const [selectedSourceField, setSelectedSourceField] = useState<string>('');
  const [selectedDestinationField, setSelectedDestinationField] = useState<string>('');

  const activeWorkspaceId = useStore((state) => state.workspaceId);

  const { data: previewModelData } = useQuery({
    queryKey: ['syncs', 'preview-model', model?.connector?.id],
    queryFn: () => getModelPreviewById(model?.query, String(model?.connector?.id)),
    enabled: !!model?.connector?.id && activeWorkspaceId > 0,
    refetchOnMount: true,
    refetchOnWindowFocus: false,
  });

  const firstRow = Array.isArray(previewModelData?.data) && previewModelData.data[0];
  const modelColumns = useMemo(() => Object.keys(firstRow ?? {}), [firstRow]);
  const destinationColumns = useMemo(() => getPathFromObject(stream?.json_schema), [stream]);

  useEffect(() => {
    if (typeof value?.source === 'string' && value.source.length > 0) {
      setSelectedSourceField(value.source);
    } else if (model.primary_key && modelColumns.includes(model.primary_key)) {
      setSelectedSourceField(model.primary_key);
    } else {
      setSelectedSourceField('');
    }
  }, [value?.source, model.primary_key, modelColumns]);

  useEffect(() => {
    if (typeof value?.destination === 'string') {
      setSelectedDestinationField(value.destination);
    } else {
      setSelectedDestinationField('');
    }
  }, [value?.destination, stream?.name]);

  useEffect(() => {
    onChange({
      source: selectedSourceField,
      destination: selectedDestinationField,
    });
  }, [selectedSourceField, selectedDestinationField, onChange]);

  const isSelectionDisabled = !stream;

  return (
    <Box backgroundColor='gray.200' padding='24px' borderRadius='8px' marginBottom='24px'>
      <Text fontWeight={600} size='md' marginBottom='8px'>
        Map primary keys to {destination?.attributes?.connector_name}
      </Text>
      <Text size='xs' mb={6} letterSpacing='-0.12px' fontWeight={400} color='black.200'>
        Choose the source column that uniquely identifies each record and the Airtable field you
        want to merge on. We will use this mapping for upserts.
      </Text>

      <Box display='flex' gap='24px' flexDirection={{ base: 'column', md: 'row' }}>
        <FormControl isRequired>
          <FormLabel fontSize='sm' color='gray.600'>
            Source primary key
          </FormLabel>
          <Select
            placeholder='Select a column'
            value={selectedSourceField}
            onChange={(event) => setSelectedSourceField(event.target.value)}
            isDisabled={isSelectionDisabled || modelColumns.length === 0}
            background='gray.100'
            borderColor='gray.400'
          >
            {modelColumns.map((column) => (
              <option key={`source-pk-${column}`} value={column}>
                {column}
              </option>
            ))}
          </Select>
        </FormControl>

        <FormControl isRequired>
          <FormLabel fontSize='sm' color='gray.600'>
            Airtable primary key
          </FormLabel>
          <Select
            placeholder='Select a field'
            value={selectedDestinationField}
            onChange={(event) => setSelectedDestinationField(event.target.value)}
            isDisabled={isSelectionDisabled || destinationColumns.length === 0}
            background='gray.100'
            borderColor='gray.400'
          >
            {destinationColumns.map((column) => (
              <option key={`destination-pk-${column}`} value={column}>
                {column}
              </option>
            ))}
          </Select>
        </FormControl>
      </Box>
    </Box>
  );
};

export default PrimaryKeyMappingSelector;
