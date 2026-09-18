import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { EmployeeNav } from "@/components/employee/employee-nav";

export default async function EmployeeLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("users")
    .select("name, role, status")
    .eq("id", user.id)
    .single();

  if (!profile || profile.status !== "active") {
    return (
      <main className="flex min-h-screen items-center justify-center p-6 text-center">
        <div>
          <h1 className="text-xl font-semibold">Account inactive</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Your account is not active. Contact an administrator.
          </p>
        </div>
      </main>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-muted/30">
      <EmployeeNav name={profile.name} isAdmin={profile.role === "admin"} />
      <main className="mx-auto max-w-3xl px-4 pb-28 pt-4 sm:pb-8">{children}</main>
    </div>
  );
}
