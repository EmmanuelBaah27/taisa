import { useEffect, useRef, useState, useCallback } from 'react';
import { ExpoSpeechRecognitionModule } from 'expo-speech-recognition';

interface UseLiveTranscription {
  transcript: string;
  isListening: boolean;
  amplitude: number; // 0–10
  recognizerError: string | null;
  start: () => Promise<void>;
  stop: () => Promise<void>;
  reset: () => void;
}

const RECOGNITION_OPTIONS = {
  lang: 'en-US',
  interimResults: true,
  continuous: true,
  volumeChangeEventOptions: {
    enabled: true,
    intervalMillis: 100,
  },
} as const;

export function useLiveTranscription(): UseLiveTranscription {
  const [transcript, setTranscript] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [amplitude, setAmplitude] = useState(0);
  const [recognizerError, setRecognizerError] = useState<string | null>(null);
  const transcriptRef = useRef('');
  const shouldRestartRef = useRef(false);

  useEffect(() => {
    // result event: { isFinal: boolean; results: ExpoSpeechRecognitionResult[] }
    // Each ExpoSpeechRecognitionResult has: { transcript, confidence, segments }
    const resultSub = ExpoSpeechRecognitionModule.addListener('result', (event) => {
      const text = event.results?.[0]?.transcript ?? '';
      setTranscript(text);
      transcriptRef.current = text;
    });

    // volumechange event: { value: number } — float between -2 and 10
    // Docs: "anything below 0 should be considered inaudible"
    // Map: clamp to [0, 10], values below 0 become 0
    const volumeSub = ExpoSpeechRecognitionModule.addListener('volumechange', (event) => {
      const raw = typeof event.value === 'number' ? event.value : 0;
      const normalized = Math.max(0, Math.min(10, raw));
      setAmplitude(normalized);
    });

    // end event fires when the recognizer stops (iOS stops after silence)
    // Auto-restart if we're still supposed to be listening
    const endSub = ExpoSpeechRecognitionModule.addListener('end', () => {
      setIsListening(false);
      setAmplitude(0);
      if (shouldRestartRef.current) {
        ExpoSpeechRecognitionModule.start(RECOGNITION_OPTIONS);
      }
    });

    // error event: { error: ExpoSpeechRecognitionErrorCode; message: string }
    // Restart on transient errors (not permission/abort errors)
    const errorSub = ExpoSpeechRecognitionModule.addListener('error', (event) => {
      const nonRestartableErrors = ['aborted', 'not-allowed', 'service-not-allowed', 'busy'];
      if (nonRestartableErrors.includes(event.error)) {
        setRecognizerError(event.error);
      } else if (shouldRestartRef.current) {
        setTimeout(() => {
          if (shouldRestartRef.current) {
            ExpoSpeechRecognitionModule.start(RECOGNITION_OPTIONS);
          }
        }, 300);
      }
    });

    // start event: null payload — fires when recognition session begins
    const startSub = ExpoSpeechRecognitionModule.addListener('start', () => {
      setIsListening(true);
    });

    return () => {
      resultSub.remove();
      volumeSub.remove();
      endSub.remove();
      errorSub.remove();
      startSub.remove();
    };
  }, []);

  const start = useCallback(async () => {
    const { granted } = await ExpoSpeechRecognitionModule.requestPermissionsAsync();
    if (!granted) throw new Error('not-allowed');
    setRecognizerError(null);
    shouldRestartRef.current = true;
    ExpoSpeechRecognitionModule.start(RECOGNITION_OPTIONS);
  }, []);

  const stop = useCallback(async () => {
    shouldRestartRef.current = false;
    ExpoSpeechRecognitionModule.stop();
    setIsListening(false);
    setAmplitude(0);
  }, []);

  const reset = useCallback(() => {
    setTranscript('');
    transcriptRef.current = '';
    setAmplitude(0);
    setIsListening(false);
  }, []);

  return { transcript, isListening, amplitude, recognizerError, start, stop, reset };
}
