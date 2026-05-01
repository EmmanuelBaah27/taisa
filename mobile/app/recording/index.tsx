import { useState, useRef } from 'react';
import { View, Text, TouchableOpacity, Animated, ActivityIndicator } from 'react-native';
import { router } from 'expo-router';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import { transcribeAudio } from '../../src/services/transcription';
import api from '../../src/services/api';
import { colors } from '../../src/constants/theme';

export default function RecordingModal() {
  const { start, stop, isRecording, duration } = useVoiceRecorder();
  const [phase, setPhase] = useState<'idle' | 'recording' | 'processing' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const pulseLoop = useRef<Animated.CompositeAnimation | null>(null);

  const startPulse = () => {
    pulseLoop.current = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, { toValue: 1.2, duration: 700, useNativeDriver: true }),
        Animated.timing(pulseAnim, { toValue: 1, duration: 700, useNativeDriver: true }),
      ])
    );
    pulseLoop.current.start();
  };

  const stopPulse = () => {
    pulseLoop.current?.stop();
    Animated.timing(pulseAnim, { toValue: 1, duration: 150, useNativeDriver: true }).start();
  };

  const handleStartRecording = async () => {
    try {
      setError(null);
      setPhase('recording');
      await start();
      startPulse();
    } catch (e: any) {
      setError(e.message);
      setPhase('error');
    }
  };

  const handleDone = async () => {
    if (!isRecording) return;
    stopPulse();
    setPhase('processing');

    try {
      const result = await stop();
      const transcript = await transcribeAudio(result.uri, result.durationSeconds);

      // Create journal entry
      const entryRes = await api.post('/entries', {
        rawTranscript: transcript,
        editedTranscript: transcript,
        audioDurationSeconds: result.durationSeconds,
        recordedAt: new Date().toISOString(),
        inputType: 'voice',
      });
      const entryId: string = entryRes.data.data.id;

      // Analyze — backend auto-creates chat_session and returns sessionId
      const analyzeRes = await api.post(`/analyze/${entryId}`);
      const sessionId: string = analyzeRes.data.data.sessionId;

      // Navigate to the new thread
      router.replace(`/thread/${sessionId}`);
    } catch (e: any) {
      setError(e.message ?? 'Something went wrong. Try again.');
      setPhase('error');
    }
  };

  const handleClose = () => {
    router.back();
  };

  return (
    <View className="flex-1" style={{ backgroundColor: 'rgba(6,6,11,0.95)' }}>
      {/* Dismiss area at top */}
      <TouchableOpacity className="flex-1" onPress={handleClose} />

      {/* Bottom sheet */}
      <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
        {/* Handle */}
        <View className="w-8 h-1 bg-border rounded-full self-center mb-6" />

        {phase === 'error' ? (
          <View className="items-center py-8">
            <Text className="text-error text-base mb-4">{error}</Text>
            <TouchableOpacity onPress={() => setPhase('idle')} className="bg-surface rounded-full px-6 py-3">
              <Text className="text-text-primary text-sm font-semibold">Try again</Text>
            </TouchableOpacity>
          </View>
        ) : phase === 'processing' ? (
          <View className="items-center py-8">
            <ActivityIndicator color={colors.accent} size="large" style={{ marginBottom: 16 }} />
            <Text className="text-text-secondary text-sm">Taisa is reading your entry…</Text>
          </View>
        ) : (
          <View className="items-center">
            <Text className="text-text-tertiary text-xs font-bold tracking-widest uppercase mb-6">
              {isRecording ? 'Recording' : 'Ready'}
            </Text>

            {isRecording && (
              <Text className="text-accent text-lg tracking-widest mb-4">〜 〜 〜 〜 〜</Text>
            )}

            <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
              <TouchableOpacity
                onPress={isRecording ? undefined : handleStartRecording}
                className="w-16 h-16 rounded-full bg-accent items-center justify-center mb-4"
                style={{ shadowColor: '#7C6FFF', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.5, shadowRadius: 12 }}
              >
                <Text className="text-2xl">🎤</Text>
              </TouchableOpacity>
            </Animated.View>

            {isRecording ? (
              <>
                <Text className="text-text-primary text-xl font-bold mb-1">{formatDuration(duration)}</Text>
                <TouchableOpacity onPress={handleDone} className="bg-surface rounded-full px-8 py-3 mt-4">
                  <Text className="text-text-primary text-sm font-semibold">Done</Text>
                </TouchableOpacity>
              </>
            ) : (
              <Text className="text-text-tertiary text-sm">Tap to start recording</Text>
            )}
          </View>
        )}
      </View>
    </View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60).toString().padStart(2, '0');
  const s = (seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
