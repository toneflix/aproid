import Link from "next/link";
import { site } from "@/content/site";

export function Footer() {
  return (
    <footer className="footer">
      <div className="container footer-inner">
        <span>
          © {new Date().getFullYear()} {site.legalEntity}.
        </span>

        <nav>
          <Link href="/account">Account</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
          <a href={`mailto:${site.contactEmail}`}>Contact</a>
        </nav>
      </div>
    </footer>
  );
}
