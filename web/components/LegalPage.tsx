import type { ReactNode } from "react";
import { site } from "@/content/site";

type LegalPageProps = {
  title: string;
  children: ReactNode;
};

export function LegalPage({ title, children }: LegalPageProps) {
  return (
    <main className="legal">
      <div className="container">
        <article>
          <h1>{title}</h1>
          <p className="updated">Last updated {site.policyDate}</p>
          {children}
        </article>
      </div>
    </main>
  );
}
