import type { Metadata } from "next";
import { AccountPanel } from "@/components/licence/AccountPanel";

export const metadata: Metadata = {
  title: "Account",
  description: "Your FlyyLink licence and computers.",
};

export default function AccountPage() {
  return (
    <main className="licence-page">
      <div className="container">
        <h1>Your account</h1>
        <AccountPanel />
      </div>
    </main>
  );
}
