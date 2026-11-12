import { Download } from "lucide-react";

export function DownloadButtons() {
  return (
    <div className="hero-actions">
      <a className="button button-primary" href="/#download">
        <Download size={18} />
        Download Aproid
      </a>
    </div>
  );
}
