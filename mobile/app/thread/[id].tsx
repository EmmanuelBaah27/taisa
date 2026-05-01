import { useEffect, useRef, useState } from 'react';
import { View, Text, ScrollView, TextInput, TouchableOpacity, KeyboardAvoidingView, Platform, ActivityIndicator } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { TaisaReplyCard } from '../../src/components/TaisaReplyCard';
import { colors } from '../../src/constants/theme';
import type { ChatMessage } from '../../src/stores/threadStore';

export default function ThreadScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { currentSession, currentMessages, isLoadingMessages, isSending, fetchThread, sendMessage, clearThread } = useThreadStore();
  const [input, setInput] = useState('');
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    if (id) fetchThread(id);
    return () => clearThread();
  }, [id]);

  useEffect(() => {
    if (currentMessages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [currentMessages.length]);

  const handleSend = async () => {
    const text = input.trim();
    if (!text || !id || isSending) return;
    setInput('');
    await sendMessage(id, text);
  };

  if (isLoadingMessages && !currentSession) {
    return (
      <View className="flex-1 bg-background items-center justify-center">
        <ActivityIndicator color={colors.accent} />
      </View>
    );
  }

  const isVoiceEntry = currentSession?.isVoice ?? false;

  // For voice entries: first 2 messages (transcript + coach note) are displayed as the entry card
  const entryMessages = isVoiceEntry ? currentMessages.slice(0, 2) : [];
  const chatMessages = isVoiceEntry ? currentMessages.slice(2) : currentMessages;

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-background"
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={0}
    >
      {/* Header */}
      <View className="flex-row items-center px-4 pt-14 pb-3 border-b border-border-subtle">
        <TouchableOpacity onPress={() => router.back()} className="mr-3">
          <Text className="text-accent text-base">‹ Back</Text>
        </TouchableOpacity>
        <Text className="text-text-primary text-base font-semibold flex-1" numberOfLines={1}>
          {currentSession?.title ?? 'Thread'}
        </Text>
      </View>

      <ScrollView
        ref={scrollRef}
        className="flex-1"
        contentContainerStyle={{ padding: 16, paddingBottom: 24 }}
      >
        {/* Voice entry section */}
        {isVoiceEntry && entryMessages.length >= 1 && (
          <View className="mb-4">
            <View className="bg-surface rounded-lg px-3 py-2 mb-2">
              <Text className="text-accent text-xs font-bold mb-1">
                🎤 Voice{currentSession?.audioDurationSeconds ? ` · ${formatDuration(currentSession.audioDurationSeconds)}` : ''}
              </Text>
              <Text className="text-text-secondary text-sm leading-relaxed">
                {entryMessages[0]?.content ?? ''}
              </Text>
            </View>

            {entryMessages.length >= 2 && (
              <TaisaReplyCard content={entryMessages[1].content} />
            )}
          </View>
        )}

        {/* Loading shimmer for fresh voice entry */}
        {isVoiceEntry && isLoadingMessages && (
          <View className="bg-surface rounded-lg px-3 py-4 mb-2 opacity-40">
            <View className="h-3 bg-surface-elevated rounded mb-2 w-3/4" />
            <View className="h-3 bg-surface-elevated rounded w-1/2" />
          </View>
        )}

        {/* Regular chat messages */}
        {chatMessages.map(msg => (
          <MessageBubble key={msg.id} message={msg} />
        ))}

        {/* Sending indicator */}
        {isSending && (
          <View className="items-start mb-2">
            <View className="bg-surface rounded-lg px-3 py-2">
              <Text className="text-text-tertiary text-xs">Taisa is thinking…</Text>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Input bar */}
      <View className="flex-row items-center px-4 py-3 border-t border-border-subtle bg-background">
        <TextInput
          value={input}
          onChangeText={setInput}
          placeholder="Reply..."
          placeholderTextColor={colors.textTertiary}
          className="flex-1 bg-surface rounded-full px-4 py-2 text-text-primary text-sm mr-3"
          multiline
          maxLength={2000}
          onSubmitEditing={handleSend}
        />
        <TouchableOpacity
          onPress={handleSend}
          disabled={!input.trim() || isSending}
          className="w-9 h-9 rounded-full bg-accent items-center justify-center"
          style={{ opacity: !input.trim() || isSending ? 0.4 : 1 }}
        >
          <Text className="text-white text-base">↑</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

function MessageBubble({ message }: { message: ChatMessage }) {
  const isUser = message.role === 'user';
  return (
    <View className={`mb-2 ${isUser ? 'items-end' : 'items-start'}`}>
      {!isUser && (
        <Text className="text-accent text-xs font-bold mb-1 ml-1">Taisa</Text>
      )}
      <View
        className={`rounded-xl px-3 py-2 max-w-xs ${isUser ? 'bg-accent-muted rounded-tr-sm' : 'bg-surface rounded-tl-sm'}`}
        style={!isUser ? { borderLeftWidth: 2, borderLeftColor: '#7C6FFF' } : undefined}
      >
        <Text className={`text-sm leading-relaxed ${isUser ? 'text-text-primary' : 'text-text-secondary'}`}>
          {message.content}
        </Text>
      </View>
    </View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
