import { useState, useRef, useEffect } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  StatusBar, ScrollView, Platform,
  Animated, ActivityIndicator, Keyboard,
} from 'react-native';
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useDiagnosisStore } from '@/src/store/diagnosisStore';
import { requestSymptomsClarification } from '@/src/services/symptoms.service';
import type { SymptomsAnalysisRequest } from '@/src/services/symptoms.service';
import { PAPER, INK, INK_FAINT, ACCENT, RULE, RULE_STRONG, SUCCESS } from '../theme';

const AGE_GROUP_TO_AGE: Record<string, number> = {
  'Under 18': 16,
  '18 – 30': 24,
  '31 – 45': 38,
  '46 – 60': 53,
  'Over 60': 68,
};

const FEELING_TO_SEVERITY: Record<string, string> = {
  'Very unwell': 'Severe',
  'Unwell': 'Moderate',
  'Okay': 'Mild',
  'Good': 'Mild',
  'Great': 'Mild',
};

const DURATION_OPTIONS = ['Today', '1-3 days', '4-7 days', 'Longer than a week'];

const GENDER_OPTIONS: { label: string; value: string }[] = [
  { label: 'Female', value: 'female' },
  { label: 'Male', value: 'male' },
  { label: 'Prefer not to say', value: 'other' },
];

type Message = {
  role:    'assistant' | 'user';
  text:    string;
  typing?: boolean;
};

// 'clarify' is a real AI-generated follow-up question (content depends on
// what the user typed, via requestSymptomsClarification) — capped at two
// rounds server-side. 'duration' is a fixed fallback used only if the AI
// clarify step is unavailable, so a duration always gets collected either way.
type Stage = 'symptom' | 'clarify' | 'duration' | 'gender' | 'done';

const INITIAL_MESSAGES: Message[] = [
  {
    role: 'assistant',
    text: "Hi 👋 I'm your AfyaSmart Doctor Assistant.\n\nI'll help you understand what your symptoms might mean. What are you experiencing today?",
  },
];

export function SymptomChatScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const setPendingAnalysisRequest = useDiagnosisStore((s) => s.setPendingAnalysisRequest);
  const healthCheckAnswers = useDiagnosisStore((s) => s.healthCheckAnswers);

  const [messages, setMessages]   = useState<Message[]>(INITIAL_MESSAGES);
  const [input, setInput]         = useState('');
  const [sending, setSending]     = useState(false);
  const [stage, setStage]         = useState<Stage>('symptom');
  const [symptomText, setSymptomText] = useState('');
  const [durationAnswer, setDurationAnswer] = useState<string | null>(null);
  const [clarifyHistory, setClarifyHistory] = useState<{ question: string; answer: string }[]>([]);
  const [currentQuestion, setCurrentQuestion] = useState<string | null>(null);
  const [currentOptions, setCurrentOptions] = useState<string[]>([]);

  const scrollRef  = useRef<ScrollView>(null);
  const inputRef   = useRef<TextInput>(null);
  // Counts consecutive too-short submissions so the "tell me a bit more"
  // nudge only ever shows once — without this, someone who keeps typing
  // short answers gets the identical canned message appended again on every
  // attempt, which reads as the chat being stuck/broken rather than nudging.
  const shortAttempts = useRef(0);
  const dotAnim1   = useRef(new Animated.Value(0)).current;
  const dotAnim2   = useRef(new Animated.Value(0)).current;
  const dotAnim3   = useRef(new Animated.Value(0)).current;

  const startDots = () => {
    const dot = (a: Animated.Value, delay: number) =>
      Animated.loop(
        Animated.sequence([
          Animated.delay(delay),
          Animated.timing(a, { toValue: -6, duration: 300, useNativeDriver: true }),
          Animated.timing(a, { toValue: 0,  duration: 300, useNativeDriver: true }),
        ])
      );
    Animated.parallel([dot(dotAnim1, 0), dot(dotAnim2, 150), dot(dotAnim3, 300)]).start();
  };

  const stopDots = () => {
    dotAnim1.stopAnimation(); dotAnim1.setValue(0);
    dotAnim2.stopAnimation(); dotAnim2.setValue(0);
    dotAnim3.stopAnimation(); dotAnim3.setValue(0);
  };

  const [keyboardShown, setKeyboardShown] = useState(false);

  const scrollToBottom = () => {
    setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
  };

  useEffect(() => { scrollToBottom(); }, [messages]);

  useEffect(() => {
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';

    const showSub = Keyboard.addListener(showEvent, () => {
      setKeyboardShown(true);
      scrollToBottom();
    });
    const hideSub = Keyboard.addListener(hideEvent, () => setKeyboardShown(false));

    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, []);

  useEffect(() => {
    if (keyboardShown) {
      scrollToBottom();
    }
  }, [keyboardShown]);

  const pushTypingThen = (next: () => void, delay = 500) => {
    startDots();
    setMessages((prev) => [...prev, { role: 'assistant', text: '', typing: true }]);
    setTimeout(() => {
      stopDots();
      setMessages((prev) => prev.filter((m) => !m.typing));
      next();
    }, delay);
  };

  // Shows a typing bubble, asks the AI whether one more clarifying question
  // is worth asking about this specific symptom, and either shows that
  // question (stage 'clarify') or moves on. If the AI clarify call is
  // unavailable, it fails safe to the fixed duration chips so a duration is
  // always collected somehow.
  const runClarifyStep = async (
    symptom: string,
    history: { question: string; answer: string }[],
  ) => {
    startDots();
    setMessages((prev) => [...prev, { role: 'assistant', text: '', typing: true }]);

    const result = await requestSymptomsClarification({
      symptom,
      age: AGE_GROUP_TO_AGE[healthCheckAnswers?.age ?? ''] ?? 25,
      severity: FEELING_TO_SEVERITY[healthCheckAnswers?.feeling ?? ''] ?? 'Moderate',
      history,
    });

    stopDots();
    setMessages((prev) => prev.filter((m) => !m.typing));

    if (!result.done) {
      const question = result.question ?? 'Can you tell me a bit more?';
      setCurrentQuestion(question);
      setCurrentOptions(result.options ?? []);
      setMessages((prev) => [...prev, { role: 'assistant', text: question }]);
      setStage('clarify');
      return;
    }

    if (result.duration) {
      setDurationAnswer(result.duration);
      setMessages((prev) => [...prev, {
        role: 'assistant',
        text: 'Got it. And which best describes you?',
      }]);
      setStage('gender');
    } else {
      setMessages((prev) => [...prev, {
        role: 'assistant',
        text: 'Got it. How long have you had this?',
      }]);
      setStage('duration');
    }
  };

  // A one- or two-word description ("sick", "not well") still reaches the AI
  // analysis step and comes back looking like a confident, specific
  // diagnosis — the model isn't trained to say "I don't have enough to go
  // on." Catching it here, before it ever reaches the AI, is more reliable
  // than hoping the model hedges appropriately on its own.
  const MIN_SYMPTOM_WORDS = 3;

  const handleSendSymptom = () => {
    const text = input.trim();
    if (!text || stage !== 'symptom') return;

    const wordCount = text.split(/\s+/).filter(Boolean).length;
    if (wordCount < MIN_SYMPTOM_WORDS && shortAttempts.current === 0) {
      // Nudge once. If they submit another short answer right after, don't
      // repeat the identical message again — just proceed with it below.
      shortAttempts.current += 1;
      setInput('');
      setMessages((prev) => [
        ...prev,
        { role: 'user', text },
        {
          role: 'assistant',
          text: "Could you tell me a bit more? For example, where it hurts, what it feels like, or when it started — a few more details helps me give you a more useful analysis.",
        },
      ]);
      // Stage stays 'symptom' — input remains open for another attempt.
      return;
    }

    shortAttempts.current = 0;
    setInput('');
    setSymptomText(text);
    setMessages((prev) => [...prev, { role: 'user', text }]);
    setStage('done'); // lock the input while the AI decides on a follow-up
    runClarifyStep(text, []);
  };

  const handleClarifyPick = (option: string) => {
    if (!currentQuestion) return;

    const nextHistory = [...clarifyHistory, { question: currentQuestion, answer: option }];
    setClarifyHistory(nextHistory);
    setMessages((prev) => [...prev, { role: 'user', text: option }]);
    setStage('done'); // hide the chip row while the next step loads
    runClarifyStep(symptomText, nextHistory);
  };

  const handleDurationPick = (option: string) => {
    setDurationAnswer(option);
    setMessages((prev) => [...prev, { role: 'user', text: option }]);
    setStage('done'); // hide the chip row while the next question loads

    pushTypingThen(() => {
      setMessages((prev) => [...prev, {
        role: 'assistant',
        text: 'And which best describes you?',
      }]);
      setStage('gender');
    });
  };

  const handleGenderPick = (label: string, value: string) => {
    setMessages((prev) => [...prev, { role: 'user', text: label }]);
    setSending(true);
    setStage('done');

    const clarifyAnswers = Object.fromEntries(
      clarifyHistory.map((qa, i) => [`followup_${i + 1}_${qa.question}`, qa.answer]),
    );

    const request: SymptomsAnalysisRequest = {
      symptoms: [symptomText],
      age: AGE_GROUP_TO_AGE[healthCheckAnswers?.age ?? ''] ?? 25,
      gender: value,
      duration: durationAnswer ?? '1-3 days',
      severity: FEELING_TO_SEVERITY[healthCheckAnswers?.feeling ?? ''] ?? 'Moderate',
      answers: {
        ...(healthCheckAnswers?.concern ? { concern: healthCheckAnswers.concern } : {}),
        ...clarifyAnswers,
      },
    };
    setPendingAnalysisRequest(request);

    // Brief typing beat before handing off — the actual analysis runs on the
    // next screen, so this message can't claim findings it doesn't have yet.
    pushTypingThen(() => {
      setMessages((prev) => [...prev, {
        role: 'assistant',
        text: "Got it — let me analyze that for you now.",
      }]);

      setTimeout(() => {
        router.push('/(onboarding)/analysis-loading' as any);
      }, 700);
    });
  };

  const inputBottomPadding = keyboardShown ? 12 : Math.max(insets.bottom, 8) + 12;
  const headerTopPadding = Math.max(insets.top + 28, 52);

  return (
    <KeyboardAvoidingView
      style={styles.root}
      // KeyboardAvoidingView from react-native-keyboard-controller follows the
      // real IME frame on every platform, including Android under Expo SDK 54's
      // forced edge-to-edge window. "padding" keeps the composer above the
      // keyboard consistently across devices.
      behavior="padding"
      keyboardVerticalOffset={0}
    >
      <StatusBar barStyle="light-content" backgroundColor={INK} />

      {/* Header */}
      <View style={[styles.header, { paddingTop: headerTopPadding }]}>
        <View style={styles.headerLeft}>
          <View style={styles.avatar}>
            <View style={styles.crossV} />
            <View style={styles.crossH} />
          </View>
          <View>
            <Text style={styles.headerName}>AfyaSmart AI</Text>
            <View style={styles.onlineRow}>
              <View style={styles.onlineDot} />
              <Text style={styles.onlineText}>Online · Health Assistant</Text>
            </View>
          </View>
        </View>
        <View style={styles.secureChip}>
          <Ionicons name="shield-checkmark-outline" size={12} color={ACCENT} />
          <Text style={styles.secureText}>Private</Text>
        </View>
      </View>

      {/* Messages */}
      <ScrollView
        ref={scrollRef}
        style={styles.messages}
        contentContainerStyle={styles.messagesContent}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
      >
        {messages.map((msg, i) => (
          <View
            key={i}
            style={[
              styles.bubble,
              msg.role === 'user' ? styles.bubbleUser : styles.bubbleAI,
            ]}
          >
            {msg.typing ? (
              <View style={styles.typingDots}>
                <Text style={styles.analyzingText}>Analysing your symptoms</Text>
                <View style={styles.dotsRow}>
                  {[dotAnim1, dotAnim2, dotAnim3].map((a, di) => (
                    <Animated.View
                      key={di}
                      style={[styles.dot, { transform: [{ translateY: a }] }]}
                    />
                  ))}
                </View>
              </View>
            ) : (
              <Text style={msg.role === 'user' ? styles.bubbleTextUser : styles.bubbleTextAI}>
                {msg.text}
              </Text>
            )}
          </View>
        ))}
      </ScrollView>

      {/* Quick replies */}
      {stage === 'clarify' && (
        <View style={styles.chipsRow}>
          {currentOptions.map((option) => (
            <TouchableOpacity
              key={option}
              style={styles.chip}
              onPress={() => handleClarifyPick(option)}
              activeOpacity={0.75}
            >
              <Text style={styles.chipText}>{option}</Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
      {stage === 'duration' && (
        <View style={styles.chipsRow}>
          {DURATION_OPTIONS.map((option) => (
            <TouchableOpacity
              key={option}
              style={styles.chip}
              onPress={() => handleDurationPick(option)}
              activeOpacity={0.75}
            >
              <Text style={styles.chipText}>{option}</Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
      {stage === 'gender' && (
        <View style={styles.chipsRow}>
          {GENDER_OPTIONS.map((option) => (
            <TouchableOpacity
              key={option.value}
              style={styles.chip}
              onPress={() => handleGenderPick(option.label, option.value)}
              activeOpacity={0.75}
            >
              <Text style={styles.chipText}>{option.label}</Text>
            </TouchableOpacity>
          ))}
        </View>
      )}

      {/* Input */}
      <View style={[styles.inputRow, { paddingBottom: inputBottomPadding }]}>
        <TextInput
          ref={inputRef}
          style={styles.input}
          value={input}
          onChangeText={setInput}
          placeholder={
            stage === 'symptom'
              ? 'Describe your symptoms...'
              : stage === 'done'
                ? 'One moment...'
                : 'Choose an option above'
          }
          placeholderTextColor={INK_FAINT}
          selectionColor={ACCENT}
          cursorColor={ACCENT}
          multiline
          maxLength={500}
          editable={stage === 'symptom' && !sending}
          onSubmitEditing={handleSendSymptom}
          returnKeyType="send"
          onFocus={() => {
            // Only nudge the transcript back into view. The keyboard frame is
            // handled by KeyboardAvoidingView; changing layout here on focus
            // used to race the IME open on Android and drop the keyboard.
            scrollToBottom();
          }}
        />
        <TouchableOpacity
          style={[styles.sendBtn, (stage !== 'symptom' || !input.trim() || sending) && styles.sendBtnDisabled]}
          onPress={handleSendSymptom}
          disabled={stage !== 'symptom' || !input.trim() || sending}
          activeOpacity={0.8}
        >
          {sending
            ? <ActivityIndicator size="small" color={PAPER} />
            : <Ionicons name="arrow-up" size={18} color={PAPER} />
          }
        </TouchableOpacity>
      </View>

    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: PAPER },
  header: {
    backgroundColor: INK,
    paddingTop: 52, paddingBottom: 16,
    paddingHorizontal: 20,
    flexDirection: 'row', alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft:  { flexDirection: 'row', alignItems: 'center', gap: 12 },
  avatar: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(238,241,234,0.14)',
    alignItems: 'center', justifyContent: 'center',
  },
  crossV: { position: 'absolute', width: 3, height: 18, backgroundColor: PAPER, borderRadius: 1.5 },
  crossH: { position: 'absolute', width: 18, height: 3, backgroundColor: PAPER, borderRadius: 1.5 },
  headerName:  { color: PAPER, fontSize: 15, fontWeight: '600' },
  onlineRow:   { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 },
  onlineDot:   { width: 6, height: 6, borderRadius: 3, backgroundColor: SUCCESS },
  onlineText:  { color: 'rgba(238,241,234,0.6)', fontSize: 11 },
  secureChip: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: PAPER,
    paddingHorizontal: 10, paddingVertical: 5, borderRadius: 20,
  },
  secureText: { color: INK, fontSize: 11, fontWeight: '600' },
  messages:        { flex: 1 },
  messagesContent: { padding: 16, gap: 10, paddingBottom: 8 },
  bubble: {
    maxWidth: '80%', borderRadius: 4, padding: 14,
  },
  bubbleAI: {
    backgroundColor: PAPER, alignSelf: 'flex-start',
    borderWidth: 1, borderColor: RULE,
  },
  bubbleUser: {
    backgroundColor: INK, alignSelf: 'flex-end',
  },
  bubbleTextAI:   { color: INK, fontSize: 14, lineHeight: 22 },
  bubbleTextUser: { color: PAPER, fontSize: 14, lineHeight: 22 },
  typingDots:    { gap: 8 },
  analyzingText: { color: INK_FAINT, fontSize: 12, fontStyle: 'italic' },
  dotsRow:       { flexDirection: 'row', gap: 5, alignItems: 'center', marginTop: 4 },
  dot: {
    width: 6, height: 6, borderRadius: 3,
    backgroundColor: INK, opacity: 0.6,
  },
  chipsRow: {
    flexDirection: 'row', flexWrap: 'wrap', gap: 8,
    paddingHorizontal: 16, paddingTop: 4, paddingBottom: 12,
    backgroundColor: PAPER,
  },
  chip: {
    borderWidth: 1, borderColor: RULE_STRONG, borderRadius: 20,
    paddingHorizontal: 14, paddingVertical: 8,
  },
  chipText: { color: INK, fontSize: 13, fontWeight: '600' },
  inputRow: {
    flexDirection: 'row', alignItems: 'flex-end', gap: 10,
    paddingHorizontal: 16, paddingVertical: 12,
    backgroundColor: PAPER,
    borderTopWidth: 1, borderTopColor: RULE,
  },
  input: {
    flex: 1, minHeight: 46, backgroundColor: '#FFFFFF', borderRadius: 12,
    paddingHorizontal: 16,
    paddingTop: Platform.OS === 'ios' ? 13 : 9,
    paddingBottom: Platform.OS === 'ios' ? 13 : 9,
    fontSize: 15, color: INK, maxHeight: 120,
    borderWidth: 1.5, borderColor: RULE_STRONG,
  },
  sendBtn: {
    width: 46, height: 46, borderRadius: 23,
    backgroundColor: INK,
    alignItems: 'center', justifyContent: 'center',
  },
  sendBtnDisabled: { backgroundColor: RULE },
});
