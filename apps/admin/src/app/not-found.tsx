import Link from "next/link";

export default function NotFound() {
  return (
    <main className="flex min-h-[60vh] items-center justify-center p-6 text-center">
      <div>
        <p className="text-sm font-medium text-primary">404</p>
        <h1 className="mt-1 text-xl font-semibold">Page not found</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          The page you are looking for does not exist.
        </p>
        <Link href="/" className="mt-5 inline-block text-sm font-medium text-primary hover:underline">
          Go home
        </Link>
      </div>
    </main>
  );
}
