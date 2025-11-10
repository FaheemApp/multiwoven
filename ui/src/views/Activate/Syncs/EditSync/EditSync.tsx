import { Box, Checkbox, CheckboxGroup, Input, Stack, Text } from '@chakra-ui/react';
import { useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getCatalog } from '@/services/syncs';
import Loader from '@/components/Loader';
import React, { useEffect, useState } from 'react';
import SelectStreams from '@/views/Activate/Syncs/SyncForm/ConfigureSyncs/SelectStreams';
import MapFields from '../SyncForm/ConfigureSyncs/MapFields';
import PrimaryKeyMappingSelector from '../SyncForm/ConfigureSyncs/PrimaryKeyMapping';
import { getConnectorInfo } from '@/services/connectors';
import { CustomToastStatus } from '@/components/Toast/index';
import useCustomToast from '@/hooks/useCustomToast';
import {
  DiscoverResponse,
  FinalizeSyncFormFields,
  PrimaryKeyMapping,
  SchemaMode,
  Stream,
  TriggerSyncButtonProps,
  HTTPSyncSettings,
} from '@/views/Activate/Syncs/types';
import ScheduleForm from './ScheduleForm';
import { FormikProps, useFormik } from 'formik';
import FormFooter from '@/components/FormFooter';
import { FieldMap as FieldMapType } from '@/views/Activate/Syncs/types';
import MapCustomFields from '../SyncForm/ConfigureSyncs/MapCustomFields';
import { useStore } from '@/stores';
import BaseButton from '@/components/BaseButton';
import { FiRefreshCcw } from 'react-icons/fi';
import AlertBox from '@/components/Alerts/Alerts';
import useEditSync from '@/hooks/syncs/useEditSync';
import useManualSync from '@/hooks/syncs/useManualSync';
import useSyncRuns from '@/hooks/syncs/useSyncRuns';
import { APIRequestMethod } from '@/services/common';
import { useAPIErrorsToast } from '@/hooks/useErrorToast';
import useGetSyncById from '@/hooks/syncs/useGetSyncById';

const SYNC_STATUS = ['pending', 'started', 'querying', 'queued', 'in_progress'];

const RenderTriggerSyncButton = ({
  isSubmitting,
  showCancelSync,
  onClick,
}: TriggerSyncButtonProps) => (
  <Box marginRight='12px'>
    <BaseButton
      variant='shell'
      leftIcon={<FiRefreshCcw color='black.500' />}
      text={showCancelSync ? 'Cancel Run' : 'Run Now'}
      color='black.500'
      onClick={() => onClick(showCancelSync ? 'delete' : 'post')}
      isLoading={isSubmitting}
    />
  </Box>
);

const EditSync = (): JSX.Element | null => {
  const [selectedStream, setSelectedStream] = useState<Stream | null>(null);
  const [isEditLoading, setIsEditLoading] = useState<boolean>(false);
  const [configuration, setConfiguration] = useState<FieldMapType[] | null>(null);
  const [primaryKeyMapping, setPrimaryKeyMapping] = useState<PrimaryKeyMapping | null>(null);
  const [httpSyncSettings, setHttpSyncSettings] = useState<HTTPSyncSettings | null>(null);
  const [hasHydratedSyncData, setHasHydratedSyncData] = useState(false);
  const activeWorkspaceId = useStore((state) => state.workspaceId);
  const [refresh, setRefresh] = useState(false);

  const showAPIErrorsToast = useAPIErrorsToast();

  const { syncId } = useParams();
  const showToast = useCustomToast();

  const { isSubmitting, runSyncNow, showCancelSync, setShowCancelSync } = useManualSync(
    syncId as string,
  );

  const {
    data: syncFetchResponse,
    isLoading,
    isError,
  } = useGetSyncById(syncId as string, activeWorkspaceId);

  const syncData = syncFetchResponse?.data?.attributes;
  const requiresPrimaryKeyMapping =
    syncData?.destination?.connector_name?.toLowerCase() === 'airtable';
  const isHttpDestination =
    syncData?.destination?.connector_name?.toLowerCase() === 'http';

  const { data: destinationFetchResponse, isLoading: isConnectorInfoLoading } = useQuery({
    queryKey: ['sync', 'destination', syncData?.destination.id, activeWorkspaceId],
    queryFn: () => getConnectorInfo(syncData?.destination.id as string),
    refetchOnMount: true,
    refetchOnWindowFocus: false,
    enabled: !!syncData?.destination.id && activeWorkspaceId > 0,
  });

  const { data: catalogData, refetch } = useQuery({
    queryKey: ['syncs', 'catalog', syncData?.destination.id, activeWorkspaceId],
    queryFn: () => getCatalog(syncData?.destination?.id as string, refresh),
    enabled: !!syncData?.destination.id && activeWorkspaceId > 0,
    refetchOnMount: false,
    refetchOnWindowFocus: false,
  });

  const { data: syncRuns } = useSyncRuns(syncId as string, 1, activeWorkspaceId);
  const syncList = syncRuns?.data;

  const { handleSubmit, selectedSyncMode, setSelectedSyncMode, cursorField, setCursorField } =
    useEditSync(
      configuration,
      setIsEditLoading,
      syncData,
      destinationFetchResponse?.data.id,
      syncData?.model?.id,
      syncData?.source?.id,
      primaryKeyMapping,
      httpSyncSettings,
    );

  const formik: FormikProps<FinalizeSyncFormFields> = useFormik({
    initialValues: {
      sync_mode: 'full_refresh',
      sync_interval: 0,
      sync_interval_unit: 'minutes',
      schedule_type: 'interval',
      cron_expression: '',
    },
    onSubmit: (data) => handleSubmit(data, syncId as string),
  });

  const handleRefreshCatalog = () => {
    setRefresh(true);
  };

  const handleOnStreamsLoad = (catalog: DiscoverResponse) => {
    const { streams } = catalog.attributes.catalog;
    const selectedStream = streams.find(({ name }) => name === syncData?.stream_name);
    if (selectedStream) {
      setSelectedStream(selectedStream);
    }
  };

  const handleOnConfigChange = (config: FieldMapType[]) => {
    setConfiguration(config);
  };

  const handleManualSyncTrigger = async (triggerMethod: APIRequestMethod) => {
    await runSyncNow(triggerMethod);
  };

  useEffect(() => {
    if (refresh) {
      refetch();
      setRefresh(false);
    }
  }, [refresh]);

  useEffect(() => {
    if (isError) {
      showToast({
        status: CustomToastStatus.Error,
        title: 'Error!!',
        description: 'Something went wrong',
        position: 'bottom-right',
        isClosable: true,
      });
    }
  }, [isError]);

  useEffect(() => {
    if (!syncData || hasHydratedSyncData) {
      return;
    }

    formik.setValues({
      sync_interval: syncData?.sync_interval ?? 0,
      sync_interval_unit: syncData?.sync_interval_unit ?? 'minutes',
      sync_mode: syncData?.sync_mode ?? 'full_refresh',
      schedule_type: syncData?.schedule_type ?? 'interval',
      cron_expression: syncData?.cron_expression ?? '',
    });

    const syncConfiguration = syncData?.configuration;
    if (Array.isArray(syncConfiguration)) {
      setConfiguration(syncConfiguration);
    } else {
      const transformedConfigs = Object.entries(syncConfiguration || {}).map(
        ([model, destination]) => ({
          from: model,
          to: destination,
          mapping_type: 'standard',
        }),
      );
      setConfiguration(transformedConfigs);
    }

    setSelectedSyncMode(syncData?.sync_mode ?? 'full_refresh');
    setCursorField(syncData?.cursor_field || '');

    const destinationName = syncData?.destination?.connector_name?.toLowerCase();
    if (destinationName === 'http') {
      const events =
        syncData?.http_sync_settings?.events && syncData.http_sync_settings.events.length > 0
          ? syncData.http_sync_settings.events
          : ['insert', 'update', 'delete'];
      const batchSize = Number(syncData?.http_sync_settings?.batch_size) || 1000;
      setHttpSyncSettings({
        events,
        batch_size: batchSize,
      });
    } else {
      setHttpSyncSettings(null);
    }

    setPrimaryKeyMapping(syncData?.primary_key_mapping ?? null);
    setHasHydratedSyncData(true);
  }, [
    syncData,
    hasHydratedSyncData,
    formik,
    setConfiguration,
    setSelectedSyncMode,
    setCursorField,
    setHttpSyncSettings,
    setPrimaryKeyMapping,
  ]);

  useEffect(() => {
    setHasHydratedSyncData(false);
  }, [syncId]);

  useEffect(() => {
    if (catalogData?.errors && catalogData?.errors?.length > 0) {
      showAPIErrorsToast(catalogData?.errors);
    } else {
      if (catalogData?.data) {
        handleOnStreamsLoad(catalogData?.data);
      }
    }
  }, [catalogData]);

  useEffect(() => {
    if (syncList && syncList.length > 0) {
      const latestSyncStatus = syncList[0]?.attributes?.status;
      if (SYNC_STATUS.includes(latestSyncStatus)) {
        setShowCancelSync(true);
      }
    }
  }, [syncList]);

  const streams = catalogData?.data?.attributes?.catalog?.streams || [];

  return (
    <form onSubmit={formik.handleSubmit} style={{ backgroundColor: 'gray.200' }}>
      <Box width='100%' pt='20px'>
        {isLoading || isConnectorInfoLoading || !syncData ? <Loader /> : null}
        {syncData && destinationFetchResponse?.data ? (
          <React.Fragment>
            {/* will be changed to get schema mode in the sync data in the future */}
            <>
              <SelectStreams
                model={syncData?.model}
                destination={destinationFetchResponse?.data}
                isEdit
                setSelectedSyncMode={setSelectedSyncMode}
                selectedSyncMode={selectedSyncMode}
                selectedStreamName={syncData?.stream_name}
                selectedCursorField={cursorField}
                setCursorField={setCursorField}
                streams={streams}
              />
              {requiresPrimaryKeyMapping && (
                <PrimaryKeyMappingSelector
                  model={syncData?.model}
                  destination={destinationFetchResponse?.data}
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
                    Choose which events send requests and how many rows to include per call.
                  </Text>
                  <Text fontWeight={500} size='sm' marginBottom='8px'>
                    Events to trigger
                  </Text>
                  <CheckboxGroup
                    colorScheme='blue'
                    value={httpSyncSettings.events}
                    onChange={(values: (string | number)[]) =>
                      setHttpSyncSettings({
                        ...httpSyncSettings,
                        events: values.map((value) => value.toString()),
                      })
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
                    onChange={(event: React.ChangeEvent<HTMLInputElement>) =>
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
                  model={syncData?.model}
                  destination={destinationFetchResponse?.data}
                  handleOnConfigChange={handleOnConfigChange}
                  data={configuration}
                  isEdit
                  configuration={configuration}
                  stream={selectedStream}
                />
              ) : (
                <MapFields
                  model={syncData?.model}
                  destination={destinationFetchResponse?.data}
                  stream={selectedStream}
                  handleOnConfigChange={handleOnConfigChange}
                  data={configuration}
                  isEdit
                  configuration={configuration}
                  handleRefreshCatalog={handleRefreshCatalog}
                />
              )}
            </>

            <ScheduleForm formik={formik} isEdit />
            {formik.values.schedule_type === 'manual' && (
              <Box marginTop='20px' marginBottom='100px'>
                <AlertBox
                  title='Trigger syncs using API keys'
                  description='You can also trigger this sync using Airflow, Dagster, or Prefect. If you need an API key, please create one in the Settings page.'
                  status='info'
                />
              </Box>
            )}
          </React.Fragment>
        ) : null}
        <FormFooter
          ctaName='Save Changes'
          ctaType='submit'
          isCtaLoading={isEditLoading}
          isCtaDisabled={
            (requiresPrimaryKeyMapping &&
              !(primaryKeyMapping?.source && primaryKeyMapping?.destination)) ||
            (isHttpDestination && !(httpSyncSettings?.events?.length))
          }
          isAlignToContentContainer
          isDocumentsSectionRequired
          isContinueCtaRequired
          isBackRequired={formik.values.schedule_type !== 'manual'}
          navigateToListScreen
          listScreenUrl='/activate/syncs'
          extra={
            formik.values.schedule_type === 'manual' ? (
              <RenderTriggerSyncButton
                isSubmitting={isSubmitting}
                showCancelSync={showCancelSync}
                onClick={handleManualSyncTrigger}
              />
            ) : (
              <></>
            )
          }
        />
      </Box>
    </form>
  );
};

export default EditSync;
