import { Directory, File, Paths } from 'expo-file-system';

export interface PersistRecordingInput {
  sourceUri: string;
  requestId: string;
}

export interface AudioFileStore {
  persistRecording(input: PersistRecordingInput): Promise<string>;
  deleteRecording(uri: string): Promise<void>;
}

const AUDIO_DIRECTORY_NAME = 'taisa-recordings';

export function createExpoAudioFileStore(): AudioFileStore {
  return {
    async persistRecording({ sourceUri, requestId }) {
      const source = new File(sourceUri);
      if (!source.exists) throw new Error('Recording is unavailable');
      const directory = new Directory(Paths.document, AUDIO_DIRECTORY_NAME);
      directory.create({ idempotent: true, intermediates: true });
      const extension = source.extension || '.m4a';
      const destination = new File(directory, `${requestId}${extension}`);
      if (!destination.exists) source.copy(destination);
      return destination.uri;
    },

    async deleteRecording(uri) {
      const file = new File(uri);
      if (file.exists) file.delete();
    },
  };
}
