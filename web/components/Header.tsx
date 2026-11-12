import Link from "next/link";
import { site } from "@/content/site";

export function Header() {
  return (
    <header className="header">
      <div className="container header-inner">
        <Link href="/" className="brand">
          <img src="/icon.svg" alt="" width={34} height={34} />
          {site.name}
        </Link>

        <nav className="nav">
          <Link href="/#features">Features</Link>
          <Link href="/#privacy">Privacy</Link>
          <Link href="/#download">Download</Link>
          <Link href="/buy">Buy</Link>
        </nav>
      </div>
    </header>
  );
}
