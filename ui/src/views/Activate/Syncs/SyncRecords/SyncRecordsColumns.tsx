import { SyncRecordResponse, SyncRecordStatus } from '../types';
import StatusTag from '@/components/StatusTag';
import { StatusTagVariants } from '@/components/StatusTag/StatusTag';
import ErrorLogsModal from './ErrorLogsModal';
import { CellContext, ColumnDef } from '@tanstack/react-table';
import { Text, Tooltip } from '@chakra-ui/react';
import { useMemo } from 'react';

export const useDynamicSyncColumns = (data: SyncRecordResponse[]) => {
  return useMemo(() => {
    if (!data || data.length === 0) return [];
    return Object.keys(data[0].attributes.record).map((key) => ({
      accessorKey: `attributes.record.${key}`,
      header: () => <span>{key}</span>,
      cell: (info: CellContext<SyncRecordResponse, string | null>) => (
        <Text size='sm' color='gray.700' fontWeight={500}>
          {info.getValue()}
        </Text>
      ),
    }));
  }, [data]);
};

const ErrorMessageCell = ({ syncRecord }: { syncRecord: SyncRecordResponse['attributes'] }) => {
  // Extract error message from logs response
  const getErrorMessage = () => {
    if (!syncRecord?.logs?.response) return null;

    try {
      const response = JSON.parse(syncRecord.logs.response);
      // Handle different error response formats
      if (response.error) return response.error;
      if (response.message) return response.message;
      if (response.errors) {
        if (Array.isArray(response.errors)) {
          return response.errors.map((e: any) => e.detail || e.message || e).join(', ');
        }
        return response.errors;
      }
      // If response itself is the error message
      if (typeof response === 'string') return response;
      return syncRecord.logs.response;
    } catch {
      // If not JSON, return raw response
      return syncRecord.logs.response;
    }
  };

  const errorMessage = getErrorMessage();

  if (!errorMessage || syncRecord.status === SyncRecordStatus.success) {
    return <Text fontSize='sm' color='gray.500'>-</Text>;
  }

  const truncatedMessage = errorMessage.length > 50
    ? `${errorMessage.substring(0, 50)}...`
    : errorMessage;

  return (
    <Tooltip label={errorMessage} fontSize='xs' placement='top' hasArrow>
      <Text fontSize='sm' color='error.500' cursor='pointer' noOfLines={1}>
        {truncatedMessage}
      </Text>
    </Tooltip>
  );
};

export const SyncRecordsColumns: ColumnDef<SyncRecordResponse>[] = [
  {
    accessorKey: `attributes.status`,
    header: () => <span>status</span>,
    cell: (info) =>
      info.getValue() === SyncRecordStatus.success ? (
        <StatusTag variant={StatusTagVariants.success} status='Added' />
      ) : (
        <StatusTag variant={StatusTagVariants.failed} status='Failed' />
      ),
  },
  {
    accessorKey: 'attributes',
    header: () => <span>Error</span>,
    cell: (info) => {
      const syncRecord = info.getValue() as SyncRecordResponse['attributes'];
      return <ErrorMessageCell syncRecord={syncRecord} />;
    },
  },
  {
    accessorKey: 'attributes',
    header: () => <h1>LOGS</h1>,
    cell: (info) => {
      const syncRecord = info.getValue() as SyncRecordResponse['attributes'];
      if (syncRecord?.logs?.request) {
        return (
          <ErrorLogsModal
            request={syncRecord?.logs?.request}
            response={syncRecord?.logs?.response}
            level={syncRecord?.logs?.level}
            status={syncRecord?.status}
          />
        );
      } else {
        return <></>;
      }
    },
  },
];
