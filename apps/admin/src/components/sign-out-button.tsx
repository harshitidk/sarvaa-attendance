"use client";

import { useRouter } from "next/navigation";
import { LogOut } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button, type ButtonProps } from "@/components/ui/button";

export function SignOutButton({ variant = "ghost", size = "sm", className, ...rest }: ButtonProps) {
  const router = useRouter();

  async function signOut() {
    await createClient().auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <Button variant={variant} size={size} className={className} onClick={signOut} {...rest}>
      <LogOut className="h-4 w-4" /> Sign out
    </Button>
  );
}
