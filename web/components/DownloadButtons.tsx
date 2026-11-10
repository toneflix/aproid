import { CodeXml, Download } from "lucide-react";
import { site } from "@/content/site";

export function DownloadButtons() {
  return (
    <div className="hero-actions">
      <a className="button button-primary" href={site.releases}>
        <Download size={18} />
        Download Aproid
      </a>
      <a className="button button-ghost" href={site.github}>
        <CodeXml size={18} />
        View on GitHub
      </a>
    </div>
  );
}
