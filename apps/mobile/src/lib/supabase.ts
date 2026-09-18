import "react-native-url-polyfill/auto";

import AsyncStorage from "@react-native-async-storage/async-storage";
import * as SecureStore from "expo-secure-store";
import { createClient } from "@supabase/supabase-js";

/**
 * Session storage: SecureStore is used for small values; AsyncStorage is the
 * fallback because SecureStore has a ~2 KB per-item limit and Supabase JWTs can
 * exceed it. Never store the service-role key on the device.
 */
const CHUNK_LIMIT = 1800;

const storage = {
  async getItem(key: string): Promise<string | null> {
    const chunkCount = Number((await AsyncStorage.getItem(`${key}.chunks`)) ?? "0");
    if (chunkCount > 0) {
      const parts = await AsyncStorage.multiGet(
        Array.from({ length: chunkCount }, (_, i) => `${key}.${i}`),
      );
      return parts.map(([, value]) => value ?? "").join("");
    }
    try {
      return await SecureStore.getItemAsync(key);
    } catch {
      return AsyncStorage.getItem(key);
    }
  },
  async setItem(key: string, value: string): Promise<void> {
    if (value.length <= CHUNK_LIMIT) {
      try {
        await SecureStore.setItemAsync(key, value);
        await AsyncStorage.removeItem(`${key}.chunks`);
        return;
      } catch {
        // fall through to chunked storage
      }
    }
    const chunks = Math.ceil(value.length / CHUNK_LIMIT);
    const pairs: [string, string][] = [];
    for (let i = 0; i < chunks; i += 1) {
      pairs.push([`${key}.${i}`, value.slice(i * CHUNK_LIMIT, (i + 1) * CHUNK_LIMIT)]);
    }
    await AsyncStorage.multiSet(pairs);
    await AsyncStorage.setItem(`${key}.chunks`, String(chunks));
  },
  async removeItem(key: string): Promise<void> {
    const chunkCount = Number((await AsyncStorage.getItem(`${key}.chunks`)) ?? "0");
    if (chunkCount > 0) {
      await AsyncStorage.multiRemove([
        ...Array.from({ length: chunkCount }, (_, i) => `${key}.${i}`),
        `${key}.chunks`,
      ]);
    }
    try {
      await SecureStore.deleteItemAsync(key);
    } catch {
      // ignore
    }
  },
};

export const supabase = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL!,
  process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!,
  {
    auth: {
      storage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);
