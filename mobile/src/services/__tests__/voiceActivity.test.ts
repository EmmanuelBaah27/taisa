import { classifyVoiceActivity } from '../voiceActivity';

describe('voice activity classification', () => {
  test('sustained speaking samples create a speech draft', () => {
    expect(classifyVoiceActivity([0.03, 0.12, 0.18, 0.16, 0.14, 0.11, 0.04])).toBe('speech');
  });

  test('elapsed silence never creates a voice draft', () => {
    expect(classifyVoiceActivity(Array.from({ length: 125 }, () => 0.015))).toBe('silence');
  });

  test('an isolated loud sound is uncertain but not eligible for a draft', () => {
    expect(classifyVoiceActivity([0.01, 0.01, 0.75, 0.01, 0.01, 0.01])).toBe('uncertain');
  });

  test('short borderline sound is uncertain rather than silently discarded', () => {
    expect(classifyVoiceActivity([0.02, 0.07, 0.08, 0.02])).toBe('uncertain');
  });

  test('an empty meter history is silence', () => {
    expect(classifyVoiceActivity([])).toBe('silence');
  });

  test('detected speech can be valid while the displayed timer still rounds to zero', () => {
    expect(classifyVoiceActivity([0.12, 0.16, 0.13])).toBe('speech');
  });
});
