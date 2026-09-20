import { useCallback, useEffect, useState, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  StatusBar,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import Constants from 'expo-constants';
import * as Google from 'expo-auth-session/providers/google';
import * as WebBrowser from 'expo-web-browser';
import { AuthResponse, loginUser, signInWithGoogleIdToken } from '@/src/services/auth.service';
import { isSubscriptionActive } from '@/src/services/subscription.model';
import { useAuthStore } from '@/src/store/authStore';

const TEAL = '#005454';
const TEAL_DARK = '#004f50';

WebBrowser.maybeCompleteAuthSession();

type GoogleExtra = {
  googleWebClientId?: string;
  googleIosClientId?: string;
  googleAndroidClientId?: string;
};

export function LoginScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { plan } = useLocalSearchParams<{ plan?: string }>();

  const setAuth = useAuthStore((s) => s.setAuth);
  const completeOnboarding = useAuthStore((s) => s.completeOnboarding);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [focusedField, setFocusedField] = useState<string | null>(null);

  const isSubmitting = useRef(false);
  const googleExtra = (Constants.expoConfig?.extra?.google ?? {}) as GoogleExtra;
  const googleWebClientId =
    process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID ??
    googleExtra.googleWebClientId;
  const googleIosClientId =
    process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID ??
    googleExtra.googleIosClientId ??
    googleWebClientId;
  const googleAndroidClientId =
    process.env.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID ??
    googleExtra.googleAndroidClientId ??
    googleWebClientId;
  const googleConfigured = Boolean(googleWebClientId && googleAndroidClientId);
  const [googleRequest, googleResponse, promptGoogle] = Google.useIdTokenAuthRequest({
    clientId: googleWebClientId ?? 'not-configured.apps.googleusercontent.com',
    webClientId: googleWebClientId ?? 'not-configured.apps.googleusercontent.com',
    iosClientId: googleIosClientId ?? 'not-configured.apps.googleusercontent.com',
    androidClientId: googleAndroidClientId ?? 'not-configured.apps.googleusercontent.com',
  });

  const routeAfterAuth = useCallback(async (data: AuthResponse) => {
    await setAuth(data.token, data.user, data.isNewUser ?? false);

    if (plan) {
      router.replace({
        pathname: '/(tabs)/subscription' as any,
        params: { plan },
      });
      return;
    }

    if (isSubscriptionActive(data.user)) {
      await completeOnboarding();
    }

    if (data.user.role === 'admin' || data.user.role === 'super_admin') {
      router.replace('/admin' as any);
      return;
    }

    router.replace('/(tabs)' as any);
  }, [completeOnboarding, plan, router, setAuth]);

  useEffect(() => {
    const idToken =
      googleResponse?.type === 'success'
        ? (googleResponse.params?.id_token ?? googleResponse.authentication?.idToken)
        : null;

    if (!idToken) return;

    (async () => {
      setLoading(true);
      try {
        const data = await signInWithGoogleIdToken(idToken);
        await routeAfterAuth(data);
      } catch (error: any) {
        alert(error?.message ?? 'Google sign-in failed. Please try again.');
      } finally {
        setLoading(false);
      }
    })();
  }, [googleResponse, routeAfterAuth]);

  useEffect(() => {
    if (googleResponse) {
      console.log('Google Auth response received:', googleResponse.type, JSON.stringify(googleResponse));
      if (googleResponse.type === 'error') {
        console.error('Google Auth error details:', googleResponse.error);
        alert(googleResponse.error?.message ?? 'Google sign-in failed during prompt. Please verify configuration.');
      }
    }
  }, [googleResponse]);

  const handleLogin = async () => {
    if (!email || !password) {
      alert('Please enter email and password');
      return;
    }

    if (isSubmitting.current) return;
    isSubmitting.current = true;
    setLoading(true);

    try {
      const data = await loginUser(email, password);
      await routeAfterAuth(data);
    } catch (error: any) {
      const message =
        error?.response?.data?.message ||
        error?.message ||
        'Login failed. Please try again.';
      alert(message);
    } finally {
      setLoading(false);
      isSubmitting.current = false;
    }
  };

  const handleGoogleSignIn = async () => {
    if (!googleConfigured || !googleRequest) {
      alert('Google sign-in needs Google OAuth client IDs in app.json.');
      return;
    }

    await promptGoogle();
  };

  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior="padding"
    >
      <StatusBar
        barStyle="light-content"
        backgroundColor={TEAL_DARK}
        translucent
      />

      {/* Decorative Background */}
      <View style={styles.background}>
        <View style={styles.bgBase} />

        <View
          style={[
            styles.circle,
            {
              width: 320,
              height: 320,
              top: -80,
              right: -80,
              opacity: 0.12,
            },
          ]}
        />

        <View
          style={[
            styles.circle,
            {
              width: 200,
              height: 200,
              top: 60,
              left: -60,
              opacity: 0.08,
            },
          ]}
        />

        <View
          style={[
            styles.circle,
            {
              width: 150,
              height: 150,
              top: 180,
              right: 20,
              opacity: 0.06,
            },
          ]}
        />

        <View style={styles.crossPatternWrap}>
          {[...Array(6)].map((_, i) => (
            <View
              key={i}
              style={[
                styles.crossPattern,
                {
                  top: 40 + i * 60,
                  left: 20 + (i % 2) * 80,
                  opacity: 0.04 + i * 0.01,
                },
              ]}
            >
              <View style={styles.crossPatternV} />
              <View style={styles.crossPatternH} />
            </View>
          ))}
        </View>

        <View style={styles.heartbeatLine} />
      </View>

      <ScrollView
        contentContainerStyle={[styles.scroll, { paddingBottom: Math.max(insets.bottom, 24) }]}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {/* Top Brand Section */}
        <View style={[styles.top, { paddingTop: Math.max(insets.top, 36) + 32 }]}>
          <View style={styles.logoWrap}>
            <View style={styles.logoRing2}>
              <View style={styles.logoRing1}>
                <View style={styles.logoCore}>
                  <View style={styles.crossV} />
                  <View style={styles.crossH} />
                </View>
              </View>
            </View>

            <View style={styles.pulseDot} />
          </View>

          <Text style={styles.appName}>AfyaSmart</Text>

          <Text style={styles.tagline}>
            Your Personal Health Companion
          </Text>
        </View>

        {/* Form Card */}
        <View style={styles.card}>
          <View style={styles.cardAccent} />

          <Text style={styles.cardTitle}>Welcome back 👋</Text>

          <Text style={styles.cardSub}>
            Sign in to access your health dashboard
          </Text>

          {/* Email */}
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>
              Email address
            </Text>

            <View
              style={[
                styles.inputWrap,
                focusedField === 'email' && styles.inputWrapFocused,
              ]}
            >
              <View style={styles.inputIconWrap}>
                <Ionicons
                  name="mail-outline"
                  size={18}
                  color={focusedField === 'email' ? TEAL : '#718096'}
                />
              </View>

              <TextInput
                style={styles.input}
                placeholder="your@email.com"
                placeholderTextColor="#9AA7A7"
                selectionColor={TEAL}
                cursorColor={TEAL}
                keyboardType="email-address"
                autoCapitalize="none"
                autoCorrect={false}
                value={email}
                onChangeText={setEmail}
                onFocus={() => setFocusedField('email')}
                onBlur={() => setFocusedField(null)}
              />

              {email.length > 0 && (
                <Ionicons
                  name="checkmark-circle"
                  size={18}
                  color={TEAL}
                />
              )}
            </View>
          </View>

          {/* Password */}
          <View style={styles.inputGroup}>
            <Text style={styles.inputLabel}>
              Password
            </Text>

            <View
              style={[
                styles.inputWrap,
                focusedField === 'password' && styles.inputWrapFocused,
              ]}
            >
              <View style={styles.inputIconWrap}>
                <Ionicons
                  name="lock-closed-outline"
                  size={18}
                  color={focusedField === 'password' ? TEAL : '#718096'}
                />
              </View>

              <TextInput
                style={styles.input}
                placeholder="Enter your password"
                placeholderTextColor="#9AA7A7"
                selectionColor={TEAL}
                cursorColor={TEAL}
                secureTextEntry={!showPassword}
                autoCorrect={false}
                value={password}
                onChangeText={setPassword}
                onFocus={() => setFocusedField('password')}
                onBlur={() => setFocusedField(null)}
              />

              <TouchableOpacity
                onPress={() =>
                  setShowPassword(!showPassword)
                }
                style={styles.eyeBtn}
              >
                <Ionicons
                  name={
                    showPassword
                      ? 'eye-off-outline'
                      : 'eye-outline'
                  }
                  size={18}
                  color="#bbb"
                />
              </TouchableOpacity>
            </View>
          </View>

          {/* Forgot */}
          <TouchableOpacity style={styles.forgotRow}>
            <Text style={styles.forgotText}>
              Forgot password?
            </Text>
          </TouchableOpacity>

          {/* Sign in */}
          <TouchableOpacity
            style={[
              styles.signInBtn,
              loading && styles.signInBtnDisabled,
            ]}
            onPress={handleLogin}
            disabled={loading}
            activeOpacity={0.85}
          >
            <View style={styles.signInBtnInner}>
              {loading ? (
                <>
                  <Ionicons
                    name="reload-outline"
                    size={18}
                    color="#fff"
                  />

                  <Text style={styles.signInBtnText}>
                    Signing in...
                  </Text>
                </>
              ) : (
                <>
                  <Text style={styles.signInBtnText}>
                    Sign In
                  </Text>

                  <Ionicons
                    name="arrow-forward"
                    size={18}
                    color="#fff"
                  />
                </>
              )}
            </View>

            <View style={styles.btnShine} />
          </TouchableOpacity>

          {/* Divider */}
          <View style={styles.divider}>
            <View style={styles.dividerLine} />

            <Text style={styles.dividerText}>
              or continue with
            </Text>

            <View style={styles.dividerLine} />
          </View>

          {/* Social buttons */}
          <View style={styles.socialRow}>
            <TouchableOpacity
              style={styles.socialBtn}
              onPress={handleGoogleSignIn}
              disabled={loading}
            >
              <Ionicons
                name="logo-google"
                size={20}
                color="#EA4335"
              />

              <Text style={styles.socialBtnText}>
                Google
              </Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.socialBtn}>
              <Ionicons
                name="logo-apple"
                size={20}
                color="#000"
              />

              <Text style={styles.socialBtnText}>
                Apple
              </Text>
            </TouchableOpacity>
          </View>

          {/* Register */}
          <TouchableOpacity
            style={styles.registerRow}
            onPress={() => {
              if (plan) {
                router.push({
                  pathname: '/(auth)/register' as any,
                  params: { plan },
                });
                return;
              }

              router.push('/(auth)/register' as any);
            }}
          >
            <Text style={styles.registerText}>
              Don&apos;t have an account?
            </Text>

            <Text style={styles.registerLink}>
              {' '}
              Create one →
            </Text>
          </TouchableOpacity>

        </View>

        <Text style={styles.footer}>
          By signing in, you agree to our Terms &
          Privacy Policy
        </Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  background: {
    ...StyleSheet.absoluteFillObject,
  },
  bgBase: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: TEAL_DARK,
  },
  circle: {
    position: 'absolute',
    borderRadius: 999,
    backgroundColor: '#fff',
  },
  crossPatternWrap: {
    ...StyleSheet.absoluteFillObject,
  },
  crossPattern: {
    position: 'absolute',
    width: 20,
    height: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  crossPatternV: {
    position: 'absolute',
    width: 2,
    height: 14,
    backgroundColor: '#fff',
    borderRadius: 1,
  },
  crossPatternH: {
    position: 'absolute',
    width: 14,
    height: 2,
    backgroundColor: '#fff',
    borderRadius: 1,
  },
  heartbeatLine: {
    position: 'absolute',
    bottom: '35%',
    left: 0,
    right: 0,
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  scroll: {
    flexGrow: 1,
  },
  top: {
    alignItems: 'center',
    paddingTop: 64,
    paddingBottom: 32,
    paddingHorizontal: 24,
  },
  logoWrap: {
    marginBottom: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoRing2: {
    width: 96,
    height: 96,
    borderRadius: 48,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoRing1: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.25)',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  logoCore: {
    width: 54,
    height: 54,
    borderRadius: 27,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  crossV: {
    position: 'absolute',
    width: 5,
    height: 28,
    backgroundColor: '#fff',
    borderRadius: 3,
  },
  crossH: {
    position: 'absolute',
    width: 28,
    height: 5,
    backgroundColor: '#fff',
    borderRadius: 3,
  },
  pulseDot: {
    position: 'absolute',
    bottom: 4,
    right: 4,
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#4ADE80',
    borderWidth: 2,
    borderColor: TEAL_DARK,
  },
  appName: {
    color: '#fff',
    fontSize: 30,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginBottom: 6,
  },
  tagline: {
    color: 'rgba(255,255,255,0.65)',
    fontSize: 13,
    marginBottom: 24,
    letterSpacing: 0.3,
  },
  card: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 32,
    borderTopRightRadius: 32,
    padding: 28,
    paddingBottom: 16,
    flex: 1,
    overflow: 'hidden',
  },
  cardAccent: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 4,
    backgroundColor: TEAL,
    borderTopLeftRadius: 32,
    borderTopRightRadius: 32,
  },
  cardTitle: {
    fontSize: 22,
    fontWeight: '800',
    color: '#1a1a1a',
    marginBottom: 4,
    marginTop: 8,
  },
  cardSub: {
    fontSize: 13,
    color: '#888',
    marginBottom: 24,
    lineHeight: 20,
  },
  inputGroup: {
    marginBottom: 16,
  },
  inputLabel: {
    fontSize: 12,
    fontWeight: '700',
    color: '#555',
    marginBottom: 8,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  inputWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#F4F8F7',
    borderWidth: 1.5,
    borderColor: '#E3E9E9',
    borderRadius: 16,
    paddingLeft: 4,
    paddingRight: 14,
    minHeight: 56,
    gap: 2,
  },
  inputWrapFocused: {
    // Only colour changes here — no borderWidth/elevation/shadow. Those
    // relayout or re-composite the focused field's container on Android,
    // and doing that at the exact moment the IME is opening makes the
    // keyboard flash up and immediately close again.
    borderColor: TEAL,
    backgroundColor: '#fff',
  },
  inputIconWrap: {
    width: 48,
    height: 54,
    alignItems: 'center',
    justifyContent: 'center',
  },
  inputIconWrapFocused: {
    backgroundColor: 'transparent',
  },
  input: {
    flex: 1,
    fontSize: 15,
    color: '#12201F',
    paddingVertical: 12,
  },
  eyeBtn: {
    padding: 6,
  },
  forgotRow: {
    alignSelf: 'flex-end',
    marginBottom: 20,
    marginTop: -4,
  },
  forgotText: {
    fontSize: 13,
    color: TEAL,
    fontWeight: '600',
  },
  signInBtn: {
    backgroundColor: TEAL,
    borderRadius: 14,
    height: 54,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 20,
    overflow: 'hidden',
  },
  signInBtnDisabled: {
    opacity: 0.6,
  },
  signInBtnInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    zIndex: 2,
  },
  signInBtnText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  btnShine: {
    position: 'absolute',
    top: 0,
    left: '-30%',
    width: '40%',
    height: '100%',
    backgroundColor: 'rgba(255,255,255,0.15)',
    transform: [{ skewX: '-20deg' }],
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 12,
  },
  dividerLine: {
    flex: 1,
    height: 0.5,
    backgroundColor: '#E5E7EB',
  },
  dividerText: {
    fontSize: 12,
    color: '#aaa',
    fontWeight: '500',
  },
  socialRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  socialBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    borderWidth: 1.5,
    borderColor: '#E5E7EB',
    borderRadius: 12,
    height: 48,
    backgroundColor: '#FAFAFA',
  },
  socialBtnText: {
    fontSize: 14,
    color: '#333',
    fontWeight: '600',
  },
  registerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 20,
  },
  registerText: {
    fontSize: 14,
    color: '#888',
  },
  registerLink: {
    fontSize: 14,
    color: TEAL,
    fontWeight: '800',
  },
  trustRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginBottom: 8,
  },
  trustItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  trustText: {
    fontSize: 11,
    color: '#888',
    fontWeight: '500',
  },
  trustDot: {
    width: 3,
    height: 3,
    borderRadius: 2,
    backgroundColor: '#ddd',
  },
  footer: {
    textAlign: 'center',
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
    backgroundColor: TEAL_DARK,
    paddingVertical: 16,
    paddingHorizontal: 24,
  },
});
