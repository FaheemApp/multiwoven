import { Box } from '@chakra-ui/react';
import { FiRefreshCcw } from 'react-icons/fi';
import BaseButton from '@/components/BaseButton';
import useManualSync from '@/hooks/syncs/useManualSync';
import useSyncRuns from '@/hooks/syncs/useSyncRuns';
import { useStore } from '@/stores';
import { useEffect } from 'react';
import { APIRequestMethod } from '@/services/common';

const SYNC_STATUS = ['pending', 'started', 'querying', 'queued', 'in_progress'];

type SyncActionButtonProps = {
  syncId: string;
  scheduleType: string;
};

const SyncActionButton = ({ syncId, scheduleType }: SyncActionButtonProps) => {
  const activeWorkspaceId = useStore((state) => state.workspaceId);
  const { isSubmitting, runSyncNow, showCancelSync, setShowCancelSync } = useManualSync(syncId);
  const { data: syncRuns } = useSyncRuns(syncId, 1, activeWorkspaceId);

  const syncList = syncRuns?.data;

  useEffect(() => {
    if (syncList && syncList.length > 0) {
      const latestSyncStatus = syncList[0]?.attributes?.status;
      if (SYNC_STATUS.includes(latestSyncStatus)) {
        setShowCancelSync(true);
      } else {
        setShowCancelSync(false);
      }
    }
  }, [syncList, setShowCancelSync]);

  const handleManualSyncTrigger = async (triggerMethod: APIRequestMethod) => {
    await runSyncNow(triggerMethod);
  };

  // Only show button for manual schedule type
  if (scheduleType !== 'manual') {
    return null;
  }

  return (
    <Box onClick={(e) => e.stopPropagation()}>
      <BaseButton
        variant='shell'
        leftIcon={<FiRefreshCcw color='black.500' />}
        text={showCancelSync ? 'Cancel Run' : 'Run Now'}
        color='black.500'
        onClick={() => handleManualSyncTrigger(showCancelSync ? 'delete' : 'post')}
        isLoading={isSubmitting}
      />
    </Box>
  );
};

export default SyncActionButton;
