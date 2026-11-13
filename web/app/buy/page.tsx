import type { Metadata } from "next";
import { BuyPanel } from "@/components/licence/BuyPanel";

export const metadata: Metadata = {
  title: "Buy",
  description: "Buy FlyyLink once and use it on all your computers.",
};

export default function BuyPage() {
  return (
    <main className="licence-page">
      <div className="container">
        <h1>Yours for life.</h1>
        <p className="lead">14 days free on your Mac or PC. Then pay once.</p>
        <BuyPanel />
        <p className="price-note">
          Already bought it? <a href="/account">Manage your computers</a>.
        </p>
      </div>
    </main>
  );
}
