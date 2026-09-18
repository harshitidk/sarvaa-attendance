import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import type { ErrorBoundaryProps } from "expo-router";
import { colors, radius, spacing } from "@/theme";

export function RouteErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.card}>
        <Text style={styles.title}>Something went wrong</Text>
        <Text style={styles.message}>{error.message}</Text>
        <TouchableOpacity style={styles.button} onPress={retry}>
          <Text style={styles.buttonText}>Try again</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  content: { flexGrow: 1, justifyContent: "center", padding: spacing.xl },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  title: { fontSize: 18, fontWeight: "700", color: colors.foreground },
  message: { marginTop: spacing.sm, fontSize: 14, color: colors.muted, lineHeight: 20 },
  button: {
    marginTop: spacing.lg,
    minHeight: 44,
    justifyContent: "center",
    backgroundColor: colors.primary,
    borderRadius: radius.sm,
    paddingVertical: spacing.md,
    alignItems: "center",
  },
  buttonText: { color: colors.primaryForeground, fontWeight: "600" },
});
