import { useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import { useAuth } from "@/providers/auth";
import { colors, radius, spacing } from "@/theme";

export default function LoginScreen() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit() {
    setError(null);
    setLoading(true);
    const { error: signInError } = await signIn(email.trim(), password);
    setLoading(false);
    if (signInError) setError(signInError);
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : undefined}
      style={styles.container}
    >
      <View style={styles.card}>
        <Text style={styles.brand}>Geofenced Attendance</Text>
        <Text style={styles.subtitle}>
          Your attendance is recorded automatically when you enter or leave your workplace.
        </Text>

        <Text style={styles.label}>Work email</Text>
        <TextInput
          style={styles.input}
          autoCapitalize="none"
          keyboardType="email-address"
          autoComplete="email"
          value={email}
          onChangeText={setEmail}
          placeholder="you@company.com"
          placeholderTextColor={colors.muted}
        />

        <Text style={styles.label}>Password</Text>
        <TextInput
          style={styles.input}
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          placeholder="••••••••"
          placeholderTextColor={colors.muted}
        />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <TouchableOpacity style={styles.button} onPress={onSubmit} disabled={loading}>
          {loading ? (
            <ActivityIndicator color={colors.primaryForeground} />
          ) : (
            <Text style={styles.buttonText}>Sign in</Text>
          )}
        </TouchableOpacity>

        <Text style={styles.footnote}>
          You will be asked to grant location permission after signing in.
        </Text>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: "center", padding: spacing.xl, backgroundColor: colors.background },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.lg,
    padding: spacing.xl,
    borderWidth: 1,
    borderColor: colors.border,
  },
  brand: { fontSize: 22, fontWeight: "700", color: colors.foreground },
  subtitle: { marginTop: spacing.sm, color: colors.muted, fontSize: 14, lineHeight: 20 },
  label: { marginTop: spacing.lg, marginBottom: spacing.xs, fontSize: 13, color: colors.foreground, fontWeight: "600" },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    fontSize: 16,
    color: colors.foreground,
    backgroundColor: colors.background,
  },
  error: { marginTop: spacing.md, color: colors.danger, fontSize: 13 },
  button: {
    marginTop: spacing.xl,
    minHeight: 44,
    justifyContent: "center",
    backgroundColor: colors.primary,
    borderRadius: radius.sm,
    paddingVertical: spacing.md,
    alignItems: "center",
  },
  buttonText: { color: colors.primaryForeground, fontWeight: "600", fontSize: 16 },
  footnote: { marginTop: spacing.lg, color: colors.muted, fontSize: 12, textAlign: "center" },
});

export { RouteErrorBoundary as ErrorBoundary } from "@/components/route-error";
