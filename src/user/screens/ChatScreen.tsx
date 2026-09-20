import { useState, useRef, useEffect, useCallback } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  ScrollView, StyleSheet,
  Platform, Animated, Modal, Pressable, Keyboard,
} from 'react-native';
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect, useRouter } from 'expo-router';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { useAuthStore } from '@/src/store/authStore';
import {
  sendMessage,
  getChatStatus,
  getChatHistory,
  ChatLimitError,
  ChatStatusResponse,
} from '@/src/services/chat.service';

const TEAL       = '#005454';
const TEAL_LIGHT = '#E6F4F4';
const PURPLE     = '#712ae2';

type Message = {
  role: 'user' | 'ai';
  text: string;
  time: string;
};

const QUICK_CHIPS = [
  'Headache & fever',
  'Stomach pain',
  'Cough & cold',
  'Body weakness',
  'Chest pain',
];

function getTime() {
  return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function TypingIndicator() {
  const dot1 = useRef(new Animated.Value(0)).current;
  const dot2 = useRef(new Animated.Value(0)).current;
  const dot3 = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const animate = (dot: Animated.Value, delay: number) =>
      Animated.loop(
        Animated.sequence([
          Animated.delay(delay),
          Animated.timing(dot, { toValue: -6, duration: 300, useNativeDriver: true }),
          Animated.timing(dot, { toValue: 0,  duration: 300, useNativeDriver: true }),
          Animated.delay(600),
        ])
      ).start();

    animate(dot1, 0);
    animate(dot2, 150);
    animate(dot3, 300);
  }, [dot1, dot2, dot3]);

  return (
    <View style={styles.typingBubble}>
      {[dot1, dot2, dot3].map((dot, i) => (
        <Animated.View
          key={i}
          style={[styles.typingDot, { transform: [{ translateY: dot }] }]}
        />
      ))}
    </View>
  );
}

const PLANS = [
  { key: 'daily',   label: 'Daily Access',   price: 'Ksh 20',  sub: 'Valid for 24 hours',  popular: false },
  { key: 'weekly',  label: 'Weekly Access',  price: 'Ksh 100', sub: 'Valid for 7 days',    popular: true  },
  { key: 'monthly', label: 'Monthly Access', price: 'Ksh 200', sub: 'Valid for 30 days',   popular: false },
];

type SubscribeModalProps = {
  visible: boolean;
  remaining: number;
  freeChatEligible: boolean;
  onClose: () => void;
  onSubscribe: (plan: string) => void;
};

function SubscribeModal({
  visible,
  remaining,
  freeChatEligible,
  onClose,
  onSubscribe,
}: SubscribeModalProps) {
  const [selected, setSelected] = useState('weekly');

  return (
    <Modal visible={visible} transparent statusBarTranslucent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.modalOverlay} onPress={onClose}>
        <Pressable style={styles.modalSheet} onPress={() => {}}>
          <View style={styles.modalHeader}>
            <Text style={styles.modalLock}>🔒</Text>
            <Text style={styles.modalTitle}>Unlock Full AI Chat</Text>
            <Text style={styles.modalSub}>
              {!freeChatEligible
                ? 'Your subscription has ended. Renew to continue chatting.'
                : remaining === 0
                ? 'You have used all your free chats.'
                : `Only ${remaining} free chat${remaining !== 1 ? 's' : ''} remaining.`}
            </Text>
          </View>

          <View style={styles.featureRow}>
            {['Full Diagnosis', 'Treatment Advice', 'Nearby Services', 'AI Chat Support'].map(f => (
              <View key={f} style={styles.featurePill}>
                <Text style={styles.featurePillText}>{f}</Text>
              </View>
            ))}
          </View>

          <Text style={styles.planLabel}>Choose a plan that works for you</Text>

          {PLANS.map(plan => (
            <TouchableOpacity
              key={plan.key}
              style={[styles.planRow, selected === plan.key && styles.planRowSelected]}
              onPress={() => setSelected(plan.key)}
              activeOpacity={0.8}
            >
              {plan.popular && (
                <View style={styles.popularBadge}>
                  <Text style={styles.popularText}>Most Popular</Text>
                </View>
              )}
              <View style={{ flex: 1 }}>
                <Text style={[styles.planName, selected === plan.key && styles.planNameSelected]}>
                  {plan.label}
                </Text>
                <Text style={styles.planSub}>{plan.sub}</Text>
              </View>
              <Text style={[styles.planPrice, selected === plan.key && styles.planPriceSelected]}>
                {plan.price}
              </Text>
              <View style={[styles.radio, selected === plan.key && styles.radioSelected]}>
                {selected === plan.key && <View style={styles.radioDot} />}
              </View>
            </TouchableOpacity>
          ))}

          <TouchableOpacity style={styles.subscribeBtn} onPress={() => onSubscribe(selected)}>
            <Ionicons name="lock-open-outline" size={16} color="#fff" />
            <Text style={styles.subscribeBtnText}>Continue to Payment</Text>
          </TouchableOpacity>

          <TouchableOpacity onPress={onClose} style={{ marginTop: 12, alignItems: 'center' }}>
            <Text style={{ color: '#aaa', fontSize: 13 }}>Maybe later</Text>
          </TouchableOpacity>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

export function ChatScreen() {
  const token  = useAuthStore((state) => state.token);
  const user = useAuthStore((state) => state.user);
  const router = useRouter();
  const tabBarHeight = useBottomTabBarHeight();

  const [messages, setMessages] = useState<Message[]>([
    {
      role: 'ai',
      text: "Hi 👋 I'm your AfyaSmart Doctor Assistant.\n\nWhat symptoms are you experiencing?",
      time: getTime(),
    },
  ]);
  const [input,      setInput]      = useState('');
  const [loading,    setLoading]    = useState(false);
  const [showModal,  setShowModal]  = useState(false);
  const [keyboardShown, setKeyboardShown] = useState(false);
  const [chatStatus, setChatStatus] = useState<ChatStatusResponse | null>(null);
  const scrollRef = useRef<ScrollView>(null);

  const refreshChatStatus = useCallback(() => {
    getChatStatus(token)
      .then(setChatStatus)
      .catch(() => {});
  }, [token]);

  useEffect(() => {
    refreshChatStatus();
  }, [refreshChatStatus, user?.is_subscribed, user?.subscription_expires_at]);

  // Loads the real conversation from the database once on mount. getChatHistory
  // existed but nothing ever called it — every reopen of this screen reset
  // to just the canned greeting, silently discarding a history that was
  // actually being saved correctly the whole time. Only replaces the
  // greeting if there's real history; a brand-new chat keeps it.
  useEffect(() => {
    let cancelled = false;

    getChatHistory(token)
      .then((res) => {
        if (cancelled || res.messages.length === 0) return;
        setMessages(
          res.messages.map((m) => ({
            role: m.role,
            text: m.text,
            time: m.time || getTime(),
          })),
        );
      })
      .catch(() => {
        // Fall back silently to the canned greeting already in state.
      });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useFocusEffect(
    useCallback(() => {
      refreshChatStatus();
    }, [refreshChatStatus]),
  );

  useEffect(() => {
    setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
  }, [messages, loading]);

  useEffect(() => {
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';

    const showSub = Keyboard.addListener(showEvent, () => {
      setKeyboardShown(true);
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 50);
    });
    const hideSub = Keyboard.addListener(hideEvent, () => setKeyboardShown(false));

    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, []);

  useEffect(() => {
    if (keyboardShown) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [keyboardShown]);

  const handleSend = async (text?: string) => {
    const userMessage = (text ?? input).trim();
    if (!userMessage || loading) return;

    if (chatStatus && !chatStatus.is_subscribed && chatStatus.limit_reached) {
      setShowModal(true);
      return;
    }

    setInput('');
    setMessages((prev) => [...prev, { role: 'user', text: userMessage, time: getTime() }]);
    setLoading(true);

    try {
      // Pass the current message list as context history (excluding the new userMessage we just typed)
      const data = await sendMessage(userMessage, token, messages);
      setMessages((prev) => [...prev, { role: 'ai', text: data.reply, time: getTime() }]);
      setChatStatus((prev) => prev ? {
        ...prev,
        chat_count:    data.chat_count,
        is_subscribed: isUserSubscribed,
        limit_reached: !isUserSubscribed && data.chat_count >= data.limit,
        remaining:     Math.max(0, data.limit - data.chat_count),
      } : prev);

      // The exchange is persisted server-side by the chat edge function, in
      // the same transaction that increments chat_count. This screen used to
      // ALSO write both messages here, so every exchange was stored twice and
      // getChatHistory replayed each line doubled. The client now holds no
      // insert grant on chat_messages at all, which makes that impossible.
    } catch (err) {
      if (err instanceof ChatLimitError) {
        setChatStatus((prev) => prev ? { ...prev, limit_reached: true, remaining: 0 } : prev);
        setShowModal(true);
      } else {
        setMessages((prev) => [
          ...prev,
          {
            role: 'ai',
            text: 'Sorry, I could not process your request. Please try again.',
            time: getTime(),
          },
        ]);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleSubscribe = (plan: string) => {
    setShowModal(false);
    router.push({ pathname: '/(tabs)/subscription', params: { plan } });
  };

  const isUserSubscribed = user?.is_subscribed ?? false;
  const remaining  = chatStatus?.remaining ?? null;
  const showCounter = chatStatus && !isUserSubscribed && !chatStatus.limit_reached;
  const isChatLocked = Boolean(chatStatus && !isUserSubscribed && chatStatus.limit_reached);

  const bottomSpacer = keyboardShown
    ? 0
    : Platform.OS === 'android'
    ? tabBarHeight + 10
    : tabBarHeight;

  return (
    <KeyboardAvoidingView
      style={styles.container}
      // KeyboardAvoidingView from react-native-keyboard-controller tracks the
      // real IME frame on every platform, including Android under the
      // edge-to-edge window that Expo SDK 54 forces on. "padding" keeps the
      // input row pinned just above the keyboard consistently across devices.
      behavior="padding"
      keyboardVerticalOffset={0}
    >
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <View style={[styles.avatarWrap, { backgroundColor: '#F3EEFF' }]}>
            <Ionicons name="chatbubble-ellipses" size={22} color={PURPLE} />
            <View style={styles.onlineDot} />
          </View>
          <View>
            <Text style={styles.headerTitle}>AfyaSmart AI</Text>
            <View style={styles.onlineRow}>
              <View style={styles.onlineDotSmall} />
              <Text style={styles.onlineText}>Online</Text>
            </View>
          </View>
        </View>

        <View style={styles.headerRight}>
          {showCounter && remaining !== null && (
            <View style={styles.counterBadge}>
              <Text style={styles.counterText}>{remaining} free left</Text>
            </View>
          )}
          {isChatLocked && (
            <TouchableOpacity style={styles.unlockBtn} onPress={() => setShowModal(true)}>
              <Ionicons name="lock-closed" size={12} color="#fff" />
              <Text style={styles.unlockBtnText}>Unlock</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={styles.headerBtn}>
            <Ionicons name="ellipsis-vertical" size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>

      {/* Quick Chips */}
      <View style={styles.chipsWrapper}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipsRow}
        >
          {QUICK_CHIPS.map((chip) => (
            <TouchableOpacity
              key={chip}
              style={styles.chip}
              onPress={() => handleSend(chip)}
              activeOpacity={0.75}
            >
              <Text style={styles.chipText}>{chip}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Messages */}
      <ScrollView
        ref={scrollRef}
        style={styles.messages}
        contentContainerStyle={styles.messagesContent}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
      >
        {messages.map((msg, i) => (
          <View
            key={i}
            style={[
              styles.bubbleRow,
              msg.role === 'user' ? styles.bubbleRowUser : styles.bubbleRowAi,
            ]}
          >
            {msg.role === 'ai' && (
              <View style={[styles.aiBadge, { backgroundColor: '#F3EEFF', borderColor: '#E8E0FF' }]}>
                <Ionicons name="chatbubble-ellipses" size={13} color={PURPLE} />
              </View>
            )}
            <View style={{ maxWidth: '75%' }}>
              <View style={[styles.bubble, msg.role === 'user' ? styles.userBubble : styles.aiBubble]}>
                <Text style={[styles.bubbleText, msg.role === 'user' ? styles.userText : styles.aiText]}>
                  {msg.text}
                </Text>
              </View>
              <Text style={[styles.timeText, msg.role === 'user' ? styles.timeRight : styles.timeLeft]}>
                {msg.time}
                {msg.role === 'user' && <Text style={styles.readTick}> ✓✓</Text>}
              </Text>
            </View>
          </View>
        ))}

        {loading && <TypingIndicator />}
      </ScrollView>

      {/* Input */}
      {isChatLocked ? (
        <TouchableOpacity
          style={[styles.lockedBar, { marginBottom: bottomSpacer }]}
          onPress={() => setShowModal(true)}
        >
          <Ionicons name="lock-closed" size={16} color={TEAL} />
          <Text style={styles.lockedBarText}>Subscribe to continue chatting</Text>
          <View style={styles.lockedBarBtn}>
            <Text style={styles.lockedBarBtnText}>Unlock</Text>
          </View>
        </TouchableOpacity>
      ) : (
        <View style={[styles.inputRow, { marginBottom: bottomSpacer }]}>
          <TextInput
            style={styles.input}
            placeholder="Type your symptoms..."
            placeholderTextColor="#9AA7A7"
            selectionColor={TEAL}
            cursorColor={TEAL}
            value={input}
            onChangeText={setInput}
            multiline
            maxLength={1000}
            returnKeyType="send"
            onSubmitEditing={() => handleSend()}
            blurOnSubmit={false}
            onFocus={() => {
              // Just keep the latest message in view. The keyboard frame
              // itself is handled by KeyboardAvoidingView above — mutating
              // layout here on focus used to race the IME open on Android
              // and drop the keyboard.
              setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 50);
            }}
          />
          <TouchableOpacity
            style={[styles.sendBtn, (!input.trim() || loading) && styles.sendDisabled]}
            onPress={() => handleSend()}
            disabled={!input.trim() || loading}
            activeOpacity={0.8}
          >
            <Ionicons name="send" size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      )}

      {/* Subscribe Modal */}
      <SubscribeModal
        visible={showModal}
        remaining={chatStatus?.remaining ?? 0}
        freeChatEligible={chatStatus?.free_chat_eligible ?? true}
        onClose={() => setShowModal(false)}
        onSubscribe={handleSubscribe}
      />

    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f0f4f4' },
  header: {
    backgroundColor: TEAL,
    paddingTop: 52,
    paddingBottom: 16,
    paddingHorizontal: 20,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft:  { flexDirection: 'row', alignItems: 'center', gap: 12 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  avatarWrap: {
    width: 42, height: 42, borderRadius: 21,
    backgroundColor: 'rgba(255,255,255,0.2)',
    alignItems: 'center', justifyContent: 'center',
  },
  onlineDot: {
    position: 'absolute', bottom: 1, right: 1,
    width: 10, height: 10, borderRadius: 5,
    backgroundColor: '#4CAF50',
    borderWidth: 1.5, borderColor: TEAL,
  },
  onlineRow:      { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 },
  onlineDotSmall: { width: 7, height: 7, borderRadius: 3.5, backgroundColor: '#4CAF50' },
  onlineText:     { color: 'rgba(255,255,255,0.8)', fontSize: 11 },
  headerTitle:    { color: '#fff', fontSize: 16, fontWeight: '700' },
  headerBtn: {
    width: 34, height: 34, borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center', justifyContent: 'center',
  },
  counterBadge: {
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderRadius: 12, paddingVertical: 3, paddingHorizontal: 10,
  },
  counterText: { color: '#fff', fontSize: 11, fontWeight: '600' },
  unlockBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: '#FF6B35',
    borderRadius: 12, paddingVertical: 4, paddingHorizontal: 10,
  },
  unlockBtnText: { color: '#fff', fontSize: 11, fontWeight: '700' },
  chipsWrapper:    { backgroundColor: '#fff', borderBottomWidth: 0.5, borderBottomColor: '#e8e8e8' },
  chipsRow:        { paddingHorizontal: 14, paddingVertical: 10, gap: 8 },
  chip:            { backgroundColor: TEAL_LIGHT, borderRadius: 20, paddingVertical: 6, paddingHorizontal: 14, borderWidth: 1, borderColor: '#c0dcdc' },
  chipText:        { fontSize: 12, color: TEAL, fontWeight: '600' },
  messages:        { flex: 1 },
  messagesContent: { padding: 16, gap: 6, paddingBottom: 24 },
  bubbleRow:       { flexDirection: 'row', alignItems: 'flex-end', gap: 8, marginBottom: 4 },
  bubbleRowAi:     { justifyContent: 'flex-start' },
  bubbleRowUser:   { justifyContent: 'flex-end' },
  aiBadge: {
    width: 30, height: 30, borderRadius: 15,
    backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center',
    borderWidth: 0.5, borderColor: '#e0e0e0', marginBottom: 18,
  },
  bubble:     { padding: 12, borderRadius: 18 },
  userBubble: { backgroundColor: TEAL, borderBottomRightRadius: 4 },
  aiBubble:   { backgroundColor: '#fff', borderBottomLeftRadius: 4, borderWidth: 0.5, borderColor: '#e0e0e0' },
  bubbleText: { fontSize: 14, lineHeight: 21 },
  userText:   { color: '#fff' },
  aiText:     { color: '#1a1a1a' },
  timeText:   { fontSize: 10, color: '#aaa', marginTop: 3 },
  timeRight:  { textAlign: 'right' },
  timeLeft:   { textAlign: 'left', marginLeft: 4 },
  readTick:   { color: '#4CAF50', fontSize: 10 },
  typingBubble: {
    flexDirection: 'row', backgroundColor: '#fff', alignSelf: 'flex-start',
    padding: 14, borderRadius: 18, borderBottomLeftRadius: 4,
    gap: 5, marginLeft: 38, borderWidth: 0.5, borderColor: '#e0e0e0',
  },
  typingDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: TEAL },
  inputRow: {
    flexDirection: 'row', paddingHorizontal: 12, paddingTop: 10, paddingBottom: 10,
    gap: 10, backgroundColor: '#fff',
    borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: '#e2eaea',
    alignItems: 'flex-end',
  },
  input: {
    flex: 1, minHeight: 46, backgroundColor: '#F1F6F6',
    borderWidth: 1.5, borderColor: '#DCE3E3',
    borderRadius: 23, paddingHorizontal: 18,
    paddingTop: Platform.OS === 'ios' ? 12 : 8,
    paddingBottom: Platform.OS === 'ios' ? 12 : 8,
    fontSize: 15, color: '#12201F', maxHeight: 120,
  },
  sendBtn: {
    backgroundColor: TEAL, width: 46, height: 46, borderRadius: 23,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: TEAL, shadowOpacity: 0.3, shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 }, elevation: 3,
  },
  sendDisabled: { backgroundColor: '#9DBFBF', shadowOpacity: 0, elevation: 0 },
  lockedBar: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#fff', padding: 16,
    borderTopWidth: 0.5, borderTopColor: '#e8e8e8',
  },
  lockedBarText:    { flex: 1, fontSize: 13, color: '#555' },
  lockedBarBtn:     { backgroundColor: TEAL, borderRadius: 16, paddingVertical: 7, paddingHorizontal: 16 },
  lockedBarBtnText: { color: '#fff', fontSize: 13, fontWeight: '700' },
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
  modalSheet: {
    backgroundColor: '#fff', borderTopLeftRadius: 24, borderTopRightRadius: 24,
    padding: 24, paddingBottom: 40,
  },
  modalHeader:  { alignItems: 'center', marginBottom: 16 },
  modalLock:    { fontSize: 32, marginBottom: 8 },
  modalTitle:   { fontSize: 20, fontWeight: '800', color: '#1a1a1a', marginBottom: 4 },
  modalSub:     { fontSize: 13, color: '#777', textAlign: 'center' },
  featureRow:   { flexDirection: 'row', flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginBottom: 20 },
  featurePill:  { backgroundColor: TEAL_LIGHT, borderRadius: 20, paddingVertical: 5, paddingHorizontal: 12, borderWidth: 1, borderColor: '#c0dcdc' },
  featurePillText: { fontSize: 12, color: TEAL, fontWeight: '600' },
  planLabel:    { fontSize: 13, color: '#777', marginBottom: 10 },
  planRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    borderWidth: 1.5, borderColor: '#e0e0e0', borderRadius: 14,
    padding: 14, marginBottom: 10,
  },
  planRowSelected: { borderColor: TEAL, backgroundColor: TEAL_LIGHT },
  popularBadge: {
    position: 'absolute', top: -10, left: 16,
    backgroundColor: TEAL, borderRadius: 10,
    paddingVertical: 2, paddingHorizontal: 10,
  },
  popularText:      { color: '#fff', fontSize: 10, fontWeight: '700' },
  planName:         { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  planNameSelected: { color: TEAL },
  planSub:          { fontSize: 11, color: '#999', marginTop: 2 },
  planPrice:        { fontSize: 15, fontWeight: '800', color: '#1a1a1a' },
  planPriceSelected:{ color: TEAL },
  radio:            { width: 20, height: 20, borderRadius: 10, borderWidth: 2, borderColor: '#ccc', alignItems: 'center', justifyContent: 'center' },
  radioSelected:    { borderColor: TEAL },
  radioDot:         { width: 10, height: 10, borderRadius: 5, backgroundColor: TEAL },
  subscribeBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    backgroundColor: TEAL, borderRadius: 16, paddingVertical: 16, marginTop: 8,
  },
  subscribeBtnText: { color: '#fff', fontSize: 16, fontWeight: '800' },
});
