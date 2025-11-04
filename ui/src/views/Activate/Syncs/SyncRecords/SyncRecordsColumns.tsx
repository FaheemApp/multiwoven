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
  // For successful records, show nothing
  if (syncRecord.status === SyncRecordStatus.success) {
    return <Text fontSize='sm' color='gray.500'>-</Text>;
  }

  // Extract error message from logs response
  const getErrorMessage = () => {
    // Check if logs exist
    if (!syncRecord?.logs) return null;

    const response = syncRecord.logs.response;

    // If no response, return null
    if (!response || response.trim() === '') return null;

    // Try to parse as JSON first
    try {
      const parsed = JSON.parse(response);

      // Handle different error response formats
      if (parsed.error) return String(parsed.error);
      if (parsed.message) return String(parsed.message);
      if (parsed.errors) {
        if (Array.isArray(parsed.errors)) {
          return parsed.errors.map((e: any) => e.detail || e.message || String(e)).join(', ');
        }
        return String(parsed.errors);
      }

      // If parsed object has no error fields, return stringified version
      return JSON.stringify(parsed);
    } catch {
      // If not JSON, return raw response
      return response;
    }
  };

  const errorMessage = getErrorMessage();

  // If no error message found, show dash
  if (!errorMessage) {
    return <Text fontSize='sm' color='gray.500'>-</Text>;
  }

  const truncatedMessage = errorMessage.length > 100
    ? `${errorMessage.substring(0, 100)}...`
    : errorMessage;

  return (
    <Tooltip label={errorMessage} fontSize='xs' placement='top' hasArrow maxW='500px'>
      <Text fontSize='sm' color='error.500' cursor='pointer' noOfLines={2} maxW='300px'>
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
