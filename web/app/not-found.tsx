import Link from "next/link";

export default function NotFound() {
  return (
    <main className="legal">
      <div className="container">
        <h1>Page not found</h1>
        <p className="updated">That page wandered off. Let&apos;s get you home.</p>
        <Link className="button button-primary" href="/">
          Back to FlyyLink
        </Link>
      </div>
    </main>
  );
}
