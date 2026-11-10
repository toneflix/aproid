import { Check } from "lucide-react";
import type { ReactNode } from "react";

type ShowcaseProps = {
  eyebrow: string;
  title: string;
  body?: string;
  points: string[];
  media: ReactNode;
  gold?: boolean;
  reverse?: boolean;
};

export function Showcase({ eyebrow, title, body, points, media, gold, reverse }: ShowcaseProps) {
  return (
    <div className={`showcase${reverse ? " reverse" : ""}`}>
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h3>{title}</h3>
        {body && <p className="lead">{body}</p>}

        <ul className="checks">
          {points.map((point) => (
            <li key={point}>
              <Check size={18} />
              {point}
            </li>
          ))}
        </ul>
      </div>

      <div className={`showcase-media${gold ? " gold" : ""}`}>{media}</div>
    </div>
  );
}
