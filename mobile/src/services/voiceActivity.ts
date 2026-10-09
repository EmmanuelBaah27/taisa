export type VoiceActivitySummary = 'speech' | 'silence' | 'uncertain';

const SPEECH_LEVEL = 0.09;
const POSSIBLE_AUDIO_LEVEL = 0.05;
const SUSTAINED_SPEECH_SAMPLES = 3;

export function classifyVoiceActivity(samples: readonly number[]): VoiceActivitySummary {
  let consecutiveSpeech = 0;
  let possibleAudio = false;

  for (const sample of samples) {
    const level = Number.isFinite(sample) ? Math.max(0, Math.min(1, sample)) : 0;
    if (level >= POSSIBLE_AUDIO_LEVEL) possibleAudio = true;
    if (level >= SPEECH_LEVEL) {
      consecutiveSpeech += 1;
      if (consecutiveSpeech >= SUSTAINED_SPEECH_SAMPLES) return 'speech';
    } else {
      consecutiveSpeech = 0;
    }
  }

  return possibleAudio ? 'uncertain' : 'silence';
}
