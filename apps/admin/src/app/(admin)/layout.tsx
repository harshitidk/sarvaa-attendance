import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Sidebar } from "@/components/sidebar";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("users")
    .select("name, email, role, status")
    .eq("id", user.id)
    .single();

  if (!profile || profile.role !== "admin" || profile.status !== "active") {
    return (
      <main className="flex min-h-screen items-center justify-center p-6 text-center">
        <div>
          <h1 className="text-xl font-semibold">Access denied</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            This account does not have active administrator access.
          </p>
        </div>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar name={profile.name} email={profile.email} />
      <main className="flex-1 overflow-x-hidden bg-muted/30">
        <div className="mx-auto max-w-7xl p-6 lg:p-8">{children}</div>
      </main>
    </div>
  );
}
