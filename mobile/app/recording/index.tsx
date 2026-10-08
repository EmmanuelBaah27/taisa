import { Redirect } from 'expo-router';

import { LOCAL_CAPTURE_ROUTE } from '../../src/navigation/localCaptureRoute';

export default function LegacyRecordingRedirect() {
  return <Redirect href={LOCAL_CAPTURE_ROUTE} />;
}
