import { parseFile } from 'music-metadata';

export async function measureAudioDurationSeconds(filePath: string): Promise<number> {
  const metadata = await parseFile(filePath, { duration: true });
  const duration = metadata.format.duration;
  if (duration === undefined || !Number.isFinite(duration) || duration <= 0) {
    throw new Error('Unable to measure uploaded audio duration');
  }
  return duration;
}
