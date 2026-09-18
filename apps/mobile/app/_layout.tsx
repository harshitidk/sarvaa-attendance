import "@/lib/geofencing";
import { useEffect } from "react";
import { Stack, useRouter, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { AuthProvider, useAuth } from "@/providers/auth";
import { colors } from "@/theme";

function AuthGate() {
  const { session, loading } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    const inTabs = segments[0] === "(tabs)";
    if (!session && inTabs) {
      router.replace("/login");
    } else if (session && !inTabs) {
      router.replace("/(tabs)/home");
    }
  }, [session, loading, segments, router]);

  return null;
}

export default function RootLayout() {
  return (
    <AuthProvider>
      <AuthGate />
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: colors.card },
          headerTintColor: colors.foreground,
          contentStyle: { backgroundColor: colors.background },
        }}
      >
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="login" options={{ headerShown: false }} />
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      </Stack>
    </AuthProvider>
  );
}

export { RouteErrorBoundary as ErrorBoundary } from "@/components/route-error";
