import { Audio } from 'expo-av';
import * as FileSystem from 'expo-file-system';
import type { VoiceActivitySummary } from './voiceActivity';

export interface RecordingResult {
  uri: string;
  durationSeconds: number;
  activity?: VoiceActivitySummary;
}

let recording: Audio.Recording | null = null;
let startTime: number = 0;

export async function requestAudioPermissions(): Promise<boolean> {
  const { granted } = await Audio.requestPermissionsAsync();
  return granted;
}

export async function startRecording(): Promise<void> {
  const granted = await requestAudioPermissions();
  if (!granted) throw new Error('Audio permission denied');

  await Audio.setAudioModeAsync({
    allowsRecordingIOS: true,
    playsInSilentModeIOS: true,
  });

  const { recording: rec } = await Audio.Recording.createAsync(
    {
      ...Audio.RecordingOptionsPresets.HIGH_QUALITY,
      isMeteringEnabled: true,
    }
  );

  recording = rec;
  startTime = Date.now();
}

export async function stopRecording(): Promise<RecordingResult> {
  if (!recording) throw new Error('No active recording');

  const status = await recording.stopAndUnloadAsync();
  const uri = recording.getURI();
  const durationSeconds = status.durationMillis > 0
    ? status.durationMillis / 1000
    : (Date.now() - startTime) / 1000;

  recording = null;

  await Audio.setAudioModeAsync({ allowsRecordingIOS: false });

  if (!uri) throw new Error('Recording URI is null');

  return { uri, durationSeconds };
}

export async function pauseRecording(): Promise<void> {
  if (!recording) throw new Error('No active recording');
  await recording.pauseAsync();
}

export async function resumeRecording(): Promise<void> {
  if (!recording) throw new Error('No active recording');
  await recording.startAsync();
}

export function isRecording(): boolean {
  return recording !== null;
}

export function onMeteringUpdate(cb: (amplitude: number) => void): () => void {
  if (!recording) return () => {};
  recording.setOnRecordingStatusUpdate(status => {
    if (!status.isRecording || status.metering == null) return;
    // dBFS range: ~-60 (silence) to 0 (peak). Normalise to 0–1.
    const amp = Math.max(0, Math.min(1, (status.metering + 60) / 55));
    cb(amp);
  });
  recording.setProgressUpdateInterval(80);
  return () => { recording?.setOnRecordingStatusUpdate(null); };
}
