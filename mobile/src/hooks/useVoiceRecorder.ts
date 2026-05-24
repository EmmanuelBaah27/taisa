import { useState, useRef, useCallback } from 'react';
import { useSharedValue } from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { startRecording, stopRecording, requestAudioPermissions, onMeteringUpdate, RecordingResult } from '../services/audio';

interface UseVoiceRecorder {
  isRecording: boolean;
  duration: number;
  amplitude: ReturnType<typeof useSharedValue<number>>;
  permissionGranted: boolean | null;
  start: () => Promise<void>;
  stop: () => Promise<RecordingResult>;
  requestPermission: () => Promise<boolean>;
}

export function useVoiceRecorder(): UseVoiceRecorder {
  const [isRecording, setIsRecording] = useState(false);
  const [duration, setDuration] = useState(0);
  const [permissionGranted, setPermissionGranted] = useState<boolean | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const unsubMeteringRef = useRef<(() => void) | null>(null);
  const amplitude = useSharedValue(0);

  const requestPermission = useCallback(async () => {
    const granted = await requestAudioPermissions();
    setPermissionGranted(granted);
    return granted;
  }, []);

  const start = useCallback(async () => {
    const granted = permissionGranted ?? await requestAudioPermissions();
    if (!granted) throw new Error('Audio permission denied');

    await startRecording();
    setIsRecording(true);
    setDuration(0);
    amplitude.value = 0;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    timerRef.current = setInterval(() => {
      setDuration(d => d + 1);
    }, 1000);

    unsubMeteringRef.current = onMeteringUpdate(amp => {
      amplitude.value = amp;
    });
  }, [permissionGranted]);

  const stop = useCallback(async () => {
    if (timerRef.current) clearInterval(timerRef.current);
    unsubMeteringRef.current?.();
    amplitude.value = 0;
    const result = await stopRecording();
    setIsRecording(false);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
    return result;
  }, []);

  return { isRecording, duration, amplitude, permissionGranted, start, stop, requestPermission };
}
