import { useState, useRef, useCallback, useEffect } from 'react';
import { useSharedValue } from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import {
  startRecording,
  stopRecording,
  pauseRecording,
  resumeRecording,
  requestAudioPermissions,
  onMeteringUpdate,
  RecordingResult,
} from '../services/audio';
import { classifyVoiceActivity } from '../services/voiceActivity';

interface UseVoiceRecorder {
  isRecording: boolean;
  isPaused: boolean;
  duration: number;
  amplitude: ReturnType<typeof useSharedValue<number>>;
  amplitudeLevel: number;
  permissionGranted: boolean | null;
  start: () => Promise<void>;
  stop: () => Promise<RecordingResult>;
  pause: () => Promise<void>;
  resume: () => Promise<void>;
  getActivity: () => ReturnType<typeof classifyVoiceActivity>;
  requestPermission: () => Promise<boolean>;
}

export function useVoiceRecorder(): UseVoiceRecorder {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [duration, setDuration] = useState(0);
  const [amplitudeLevel, setAmplitudeLevel] = useState(0);
  const [permissionGranted, setPermissionGranted] = useState<boolean | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const unsubMeteringRef = useRef<(() => void) | null>(null);
  const mountedRef = useRef(true);
  const activitySamplesRef = useRef<number[]>([]);
  const amplitude = useSharedValue(0);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (timerRef.current) clearInterval(timerRef.current);
      unsubMeteringRef.current?.();
    };
  }, []);

  const requestPermission = useCallback(async () => {
    const granted = await requestAudioPermissions();
    if (mountedRef.current) setPermissionGranted(granted);
    return granted;
  }, []);

  const start = useCallback(async () => {
    const granted = permissionGranted ?? await requestAudioPermissions();
    if (!granted) throw new Error('Audio permission denied');

    await startRecording();
    if (mountedRef.current) {
      setIsRecording(true);
      setIsPaused(false);
      setDuration(0);
      setAmplitudeLevel(0);
    }
    amplitude.value = 0;
    activitySamplesRef.current = [];
    if (!mountedRef.current) return;
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    timerRef.current = setInterval(() => {
      if (mountedRef.current) setDuration(d => d + 1);
    }, 1000);

    unsubMeteringRef.current = onMeteringUpdate(amp => {
      amplitude.value = amp;
      if (mountedRef.current) setAmplitudeLevel(amp);
      activitySamplesRef.current.push(amp);
    });
  }, [permissionGranted]);

  const stop = useCallback(async () => {
    if (timerRef.current) clearInterval(timerRef.current);
    unsubMeteringRef.current?.();
    amplitude.value = 0;
    if (mountedRef.current) setAmplitudeLevel(0);
    const result = await stopRecording();
    const activity = classifyVoiceActivity(activitySamplesRef.current);
    if (mountedRef.current) {
      setIsRecording(false);
      setIsPaused(false);
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
    }
    return { ...result, activity };
  }, []);

  const pause = useCallback(async () => {
    await pauseRecording();
    if (timerRef.current) clearInterval(timerRef.current);
    timerRef.current = null;
    amplitude.value = 0;
    if (mountedRef.current) {
      setAmplitudeLevel(0);
      setIsPaused(true);
    }
  }, []);

  const resume = useCallback(async () => {
    await resumeRecording();
    timerRef.current = setInterval(() => {
      if (mountedRef.current) setDuration(d => d + 1);
    }, 1000);
    if (mountedRef.current) setIsPaused(false);
  }, []);

  const getActivity = useCallback(
    () => classifyVoiceActivity(activitySamplesRef.current),
    [],
  );

  return {
    isRecording,
    isPaused,
    duration,
    amplitude,
    amplitudeLevel,
    permissionGranted,
    start,
    stop,
    pause,
    resume,
    getActivity,
    requestPermission,
  };
}
