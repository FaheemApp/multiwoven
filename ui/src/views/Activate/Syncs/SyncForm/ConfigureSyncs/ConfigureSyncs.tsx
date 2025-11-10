import ContentContainer from '@/components/ContentContainer';
import { SteppedFormContext } from '@/components/SteppedForm/SteppedForm';
import { ModelEntity } from '@/views/Models/types';
import { Box, Checkbox, CheckboxGroup, Input, Stack, Text } from '@chakra-ui/react';
import { FormEvent, useContext, Dispatch, SetStateAction, useState, useEffect } from 'react';
import SelectStreams from './SelectStreams';
import type {
  Stream,
  FieldMap as FieldMapType,
  PrimaryKeyMapping as PrimaryKeyMappingType,
  HTTPSyncSettings,
} from '@/views/Activate/Syncs/types';
import MapFields from './MapFields';
import PrimaryKeyMappingSelector from './PrimaryKeyMapping';
import { ConnectorItem } from '@/views/Connectors/types';
import FormFooter from '@/components/FormFooter';
import MapCustomFields from './MapCustomFields';
import { useQuery } from '@tanstack/react-query';
import { getCatalog } from '@/services/syncs';
import { SchemaMode } from '@/views/Activate/Syncs/types';
import Loader from '@/components/Loader';
import { useStore } from '@/stores';

type ConfigureSyncsProps = {
  selectedStream: Stream | null;
  configuration: FieldMapType[] | null;
  schemaMode: SchemaMode | null;
  selectedSyncMode: string;
  cursorField: string;
  setSelectedStream: Dispatch<SetStateAction<Stream | null>>;
  setConfiguration: Dispatch<SetStateAction<FieldMapType[] | null>>;
  primaryKeyMapping: PrimaryKeyMappingType | null;
  setPrimaryKeyMapping: Dispatch<SetStateAction<PrimaryKeyMappingType | null>>;
  httpSyncSettings: HTTPSyncSettings | null;
  setHttpSyncSettings: Dispatch<SetStateAction<HTTPSyncSettings | null>>;
  setSchemaMode: Dispatch<SetStateAction<SchemaMode | null>>;
  setSelectedSyncMode: Dispatch<SetStateAction<string>>;
  setCursorField: Dispatch<SetStateAction<string>>;
};

const ConfigureSyncs = ({
  selectedStream,
  configuration,
  primaryKeyMapping,
  httpSyncSettings,
  selectedSyncMode,
  cursorField,
  setSelectedStream,
  setConfiguration,
  setPrimaryKeyMapping,
  setHttpSyncSettings,
  setSchemaMode,
  setSelectedSyncMode,
  setCursorField,
}: ConfigureSyncsProps): JSX.Element | null => {
  const { state, stepInfo, handleMoveForward } = useContext(SteppedFormContext);
  const [refresh, setRefresh] = useState(false);

  const { forms } = state;

  const modelInfo = forms.find((form) => form.stepKey === 'selectModel');
  const selectedModel = modelInfo?.data?.selectModel as ModelEntity;

  const destinationInfo = forms.find((form) => form.stepKey === 'selectDestination');
  const selectedDestination = destinationInfo?.data?.selectDestination as ConnectorItem;

  const activeWorkspaceId = useStore((state) => state.workspaceId);

  const handleOnStreamChange = (stream: Stream) => {
    setSelectedStream(stream);
  };

  const handleOnConfigChange = (config: FieldMapType[]) => {
    setConfiguration(config);
  };

  const requiresPrimaryKeyMapping =
    selectedDestination?.attributes?.connector_name?.toLowerCase() === 'airtable';
  const isHttpDestination =
    selectedDestination?.attributes?.connector_name?.toLowerCase() === 'http';

  useEffect(() => {
    if (!requiresPrimaryKeyMapping) {
      setPrimaryKeyMapping(null);
    }
  }, [requiresPrimaryKeyMapping, setPrimaryKeyMapping]);

  useEffect(() => {
    if (!isHttpDestination) {
      setHttpSyncSettings(null);
      return;
    }
    if (httpSyncSettings?.events && httpSyncSettings.events.length > 0) return;
    setHttpSyncSettings({
      events: ['insert', 'update', 'delete'],
      batch_size: httpSyncSettings?.batch_size || 1000,
    });
  }, [isHttpDestination, httpSyncSettings, setHttpSyncSettings]);

  const handleOnSubmit = (e: FormEvent) => {
    e.preventDefault();
    const payload = {
      source_id: selectedModel?.connector?.id,
      destination_id: selectedDestination.id,
      model_id: selectedModel.id,
      stream_name: selectedStream?.name,
      configuration,
      sync_mode: selectedSyncMode,
      cursor_field: cursorField,
      primary_key_mapping: primaryKeyMapping,
      http_sync_settings: isHttpDestination ? httpSyncSettings : null,
    };

    handleMoveForward(stepInfo?.formKey as string, payload);
  };

  const { data: catalogData, refetch } = useQuery({
    queryKey: ['syncs', 'catalog', selectedDestination?.id, activeWorkspaceId],
    queryFn: () => getCatalog(selectedDestination?.id, refresh),
    enabled: !!selectedDestination?.id && activeWorkspaceId > 0,
    refetchOnMount: false,
    refetchOnWindowFocus: false,
  });

  const handleRefreshCatalog = () => {
    setRefresh(true);
  };

  useEffect(() => {
    if (refresh) {
      refetch();
      setRefresh(false);
    }
  }, [refresh]);

  if (!catalogData?.data?.attributes?.catalog?.schema_mode) {
    return <Loader />;
  }

  if (catalogData?.data?.attributes?.catalog?.schema_mode === SchemaMode.schemaless) {
    setSchemaMode(SchemaMode.schemaless);
  }

  const streams = catalogData?.data?.attributes?.catalog?.streams || [];

  const isPrimaryKeyMappingComplete =
    !requiresPrimaryKeyMapping ||
    Boolean(primaryKeyMapping?.source?.length && primaryKeyMapping?.destination?.length);
  const isHttpSettingsValid =
    !isHttpDestination || Boolean(httpSyncSettings?.events?.length);

  return (
    <Box width='100%' display='flex' justifyContent='center'>
      <ContentContainer>
        <form onSubmit={handleOnSubmit}>
          <SelectStreams
            model={selectedModel}
            onChange={handleOnStreamChange}
            destination={selectedDestination}
            selectedStream={selectedStream}
            setSelectedSyncMode={setSelectedSyncMode}
            selectedSyncMode={selectedSyncMode}
            selectedCursorField={cursorField}
            setCursorField={setCursorField}
            streams={streams}
          />
          {requiresPrimaryKeyMapping && (
            <PrimaryKeyMappingSelector
              model={selectedModel}
              destination={selectedDestination}
              stream={selectedStream}
              value={primaryKeyMapping}
              onChange={setPrimaryKeyMapping}
            />
          )}
          {isHttpDestination && httpSyncSettings && (
            <Box backgroundColor='gray.200' padding='24px' borderRadius='8px' marginBottom='24px'>
              <Text fontWeight={600} size='md' marginBottom='8px'>
                HTTP triggers
              </Text>
              <Text size='xs' mb={4} letterSpacing='-0.12px' fontWeight={400} color='black.200'>
                Choose which events should send requests and how many rows to include per call.
              </Text>
              <Text fontWeight={500} size='sm' marginBottom='8px'>
                Events to trigger
              </Text>
              <CheckboxGroup
                colorScheme='blue'
                value={httpSyncSettings.events}
                onChange={(values) =>
                  setHttpSyncSettings({ ...httpSyncSettings, events: values as string[] })
                }
              >
                <Stack spacing={2}>
                  <Checkbox value='insert'>Rows added</Checkbox>
                  <Checkbox value='update'>Rows changed</Checkbox>
                  <Checkbox value='delete'>Rows removed</Checkbox>
                </Stack>
              </CheckboxGroup>
              <Text fontWeight={500} size='sm' marginTop='16px' marginBottom='8px'>
                HTTP batch size
              </Text>
              <Input
                type='number'
                min='1'
                value={httpSyncSettings.batch_size ?? ''}
                onChange={(event) =>
                  setHttpSyncSettings({
                    ...httpSyncSettings,
                    batch_size: Number(event.target.value),
                  })
                }
                background='gray.100'
                borderColor='gray.400'
              />
            </Box>
          )}
          {catalogData?.data?.attributes?.catalog?.schema_mode === SchemaMode.schemaless ? (
            <MapCustomFields
              model={selectedModel}
              destination={selectedDestination}
              handleOnConfigChange={handleOnConfigChange}
              configuration={configuration}
              stream={selectedStream}
            />
          ) : (
            <MapFields
              model={selectedModel}
              destination={selectedDestination}
              stream={selectedStream}
              handleOnConfigChange={handleOnConfigChange}
              configuration={configuration}
              handleRefreshCatalog={handleRefreshCatalog}
            />
          )}

          <FormFooter
            ctaName='Continue'
            ctaType='submit'
            isCtaDisabled={!selectedStream || !isPrimaryKeyMappingComplete || !isHttpSettingsValid}
            isBackRequired
            isContinueCtaRequired
            isDocumentsSectionRequired
          />
        </form>
      </ContentContainer>
    </Box>
  );
};

export default ConfigureSyncs;
