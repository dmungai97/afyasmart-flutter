import { forwardRef, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Platform,
  type TextInputProps,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

const TEAL = '#0B6E6E';
const BORDER = '#DCE3E3';
const BORDER_FOCUS = TEAL;
const ERROR = '#C62828';
const TEXT = '#12201F';
const MUTED = '#6B7A7A';

export type AppTextInputProps = TextInputProps & {
  label?: string;
  /** Ionicons name shown on the left of the field. */
  icon?: keyof typeof Ionicons.glyphMap;
  error?: string | null;
  hint?: string;
  /** Renders a show / hide toggle and manages secureTextEntry internally. */
  password?: boolean;
  containerStyle?: StyleProp<ViewStyle>;
  /** Optional node rendered on the right (e.g. a custom action). */
  rightSlot?: React.ReactNode;
};

/**
 * Shared text field for the whole app.
 *
 * Consistent height, radius, focus ring, icon slot and error state so every
 * screen looks the same and hits a comfortable 52px touch target on Android.
 */
export const AppTextInput = forwardRef<TextInput, AppTextInputProps>(function AppTextInput(
  {
    label,
    icon,
    error,
    hint,
    password,
    containerStyle,
    rightSlot,
    style,
    onFocus,
    onBlur,
    placeholderTextColor,
    ...rest
  },
  ref,
) {
  const [focused, setFocused] = useState(false);
  const [reveal, setReveal] = useState(false);

  const borderColor = error ? ERROR : focused ? BORDER_FOCUS : BORDER;

  return (
    <View style={[styles.group, containerStyle]}>
      {label ? <Text style={styles.label}>{label}</Text> : null}

      <View
        style={[
          styles.field,
          { borderColor },
          focused && !error && styles.fieldFocused,
        ]}
      >
        {icon ? (
          <Ionicons
            name={icon}
            size={18}
            color={error ? ERROR : focused ? TEAL : MUTED}
            style={styles.icon}
          />
        ) : null}

        <TextInput
          ref={ref}
          style={[styles.input, style]}
          placeholderTextColor={placeholderTextColor ?? '#9AA7A7'}
          secureTextEntry={password ? !reveal : rest.secureTextEntry}
          selectionColor={TEAL}
          cursorColor={TEAL}
          underlineColorAndroid="transparent"
          onFocus={(e) => {
            setFocused(true);
            onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            onBlur?.(e);
          }}
          {...rest}
        />

        {password ? (
          <TouchableOpacity
            onPress={() => setReveal((v) => !v)}
            hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
            style={styles.rightBtn}
          >
            <Ionicons
              name={reveal ? 'eye-off-outline' : 'eye-outline'}
              size={18}
              color={MUTED}
            />
          </TouchableOpacity>
        ) : null}

        {rightSlot ? <View style={styles.rightBtn}>{rightSlot}</View> : null}
      </View>

      {error ? (
        <Text style={styles.error}>{error}</Text>
      ) : hint ? (
        <Text style={styles.hint}>{hint}</Text>
      ) : null}
    </View>
  );
});

const styles = StyleSheet.create({
  group: { marginBottom: 16 },
  label: {
    fontSize: 13,
    fontWeight: '600',
    color: TEXT,
    marginBottom: 7,
  },
  field: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: 52,
    borderWidth: 1.5,
    borderRadius: 14,
    backgroundColor: '#F6F8F8',
    paddingHorizontal: 14,
  },
  fieldFocused: {
    backgroundColor: '#FFFFFF',
    // subtle focus ring
    shadowColor: TEAL,
    shadowOpacity: 0.18,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 0 },
    elevation: Platform.OS === 'android' ? 1 : 0,
  },
  icon: { marginRight: 10 },
  input: {
    flex: 1,
    fontSize: 15,
    color: TEXT,
    paddingVertical: Platform.OS === 'ios' ? 14 : 10,
  },
  rightBtn: { paddingLeft: 10 },
  error: { marginTop: 6, fontSize: 12, color: ERROR, fontWeight: '500' },
  hint: { marginTop: 6, fontSize: 12, color: MUTED },
});

export default AppTextInput;
