"use client";

import { Check, ShoppingBag } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { LicenceClient } from "./api";
import { PaddleCheckout } from "./paddle";

const perks = ["Up to 5 Macs and PCs", "Phones are always free", "Every future update"];

export function BuyPanel() {
  const checkout = useRef<PaddleCheckout | null>(null);
  const [price, setPrice] = useState<string>();
  const [boughtBy, setBoughtBy] = useState<string | null>(null);
  const [error, setError] = useState<string>();

  useEffect(() => {
    new LicenceClient()
      .checkout()
      .then((config) => {
        checkout.current = new PaddleCheckout(config);

        return checkout.current.price();
      })
      .then(setPrice)
      .catch(() => setError("Buying isn't open yet. Check back soon."));
  }, []);

  if (boughtBy !== null) {
    return (
      <div className="licence-panel">
        <h2>Thank you!</h2>
        <p className="lead">
          Open Aproid on your computer and sign in with {boughtBy || "the email you used"}.
        </p>
      </div>
    );
  }

  return (
    <div className="licence-panel">
      <span className="eyebrow">Lifetime</span>
      {price && <p className="price">{price}</p>}
      <p className="price-note">Pay once.</p>

      <ul className="checks">
        {perks.map((perk) => (
          <li key={perk}>
            <Check size={18} />
            {perk}
          </li>
        ))}
      </ul>

      <button
        className="button button-primary"
        disabled={!checkout.current || !!error}
        onClick={() => checkout.current?.open((email) => setBoughtBy(email ?? ""))}
      >
        <ShoppingBag size={18} />
        Buy Aproid
      </button>
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
